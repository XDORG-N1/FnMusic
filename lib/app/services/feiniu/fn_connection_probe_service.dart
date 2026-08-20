import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../state/settings_fn_state.dart';
import 'api_client.dart';
import 'fn_models.dart';

/// 探测响应是否判定候选「可用」。
///
/// [authChecked] 为 true（已登录、探测携带 token）时，候选必须通过鉴权才算
/// 可用：TCP 可达但 token 被拒的地址（HTTP 401/403、5xx，或业务码非 0 如
/// `INVALID TOKEN`）会被排除。未鉴权检查（登录前 TCP-only）时一律视为可用。
bool fnProbeResponseUsable(
  dynamic response, {
  required bool authChecked,
}) {
  if (!authChecked) return true;
  if (response is! Response) return false;
  final int status = response.statusCode ?? 0;
  if (status >= 400) return false;
  final dynamic data = response.data;
  if (data is Map<String, dynamic>) {
    final dynamic code = data['code'];
    if (code is num) return code == 0;
  }
  return true;
}

/// 早停并行探测的返回结果。
///
/// - [best]：优先级最高且已确认可达的候选；全部不可达时为 null。
/// - [bestIndex]：[best] 在候选列表中的索引。
/// - [decided]：返回时已得出探测结论的候选结果。
typedef ProbeBestReachableResult = ({
  ProbeCandidateResult? best,
  int? bestIndex,
  List<ProbeCandidateResult> decided,
});

/// 探测单条候选链路的超时。中继链路最长（10s），直连 IP 3s。
Duration fnProbeTimeout(bool isRelay) =>
    isRelay ? const Duration(seconds: 10) : const Duration(seconds: 3);

/// 缓存/回前台校验直连缓存的 connect 超时。3s 避免对「慢但可达」地址误判。
const Duration kFnCachedProbeConnectTimeout = Duration(seconds: 3);

/// 缓存/回前台校验的 connect 超时，按中继语义区分。
Duration cachedProbeTimeout(bool isRelay) =>
    isRelay ? fnProbeTimeout(true) : kFnCachedProbeConnectTimeout;

/// 缓存可达后的「升级扫描」超时。升级是锦上添花，收紧到 400ms。
const Duration kFnUpgradeProbeTimeout = Duration(milliseconds: 400);

/// FN 连接探测服务（单例）
///
/// 核心职责：
/// 1. 调用 FN 接口（5ddd.com/api/v1/fn/con，authx 签名）获取连接参数
/// 2. 按优先级分层探测可用链路（直连 3 秒 / 中继 10 秒超时）
/// 3. 返回首个可用的连接地址
///
/// 探测规则：
/// - 内网 IPv4 永久最高优先级
/// - 公网优先模式探测公网 IPv6 → IPv4 → 中继
/// - 单链路探测超时：直连 IP 3 秒，中继/域名 10 秒（见 [fnProbeTimeout]）
class FnConnectionProbeService {
  FnConnectionProbeService._();

  static final FnConnectionProbeService instance = FnConnectionProbeService._();

  /// FN 接口签名常量
  static const String _authxPrefix = 'NDzZTVxnRKP8Z0jXg1VAMonaG8akvh';
  static const String _apiKey = 'zIGtkc3dqZnJpd29qZXJqa2w7c';

  /// 是否正在探测中
  final ValueNotifier<bool> isProbing = ValueNotifier(false);

  /// 过滤掉已禁用分组的连接优先级顺序。
  static List<ProbeCandidateGroup> effectiveOrder(
    List<ProbeCandidateGroup>? order,
  ) {
    final base = order ?? AppFnConnectionSettings.connectionOrder.value;
    final disabled = AppFnConnectionSettings.disabledGroups.value;
    if (disabled.isEmpty) return List.of(base);
    return [
      for (final g in base)
        if (!disabled.contains(g)) g,
    ];
  }

  /// 独立 Dio 实例，不与主 API 客户端共享配置
  final Dio _probeDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
      sendTimeout: const Duration(seconds: 3),
      followRedirects: false,
    ),
  );

  CancelToken? _cancelToken;

  /// 在途连接探测（probeSmart 单飞行共用）
  Future<ConnectionProbeResult>? _inflightProbe;
  String? _inflightProbeFnId;

  /// 单飞行入口：相同 FNID 的并发探测复用同一在途请求，结果共享。
  Future<ConnectionProbeResult> _joinOrStartProbe({
    required String fnId,
    required Future<ConnectionProbeResult> Function() start,
  }) {
    final inflight = _inflightProbe;
    if (inflight != null) {
      if (_inflightProbeFnId == fnId) {
        return inflight; // 复用同一探测，结果共享
      }
      throw Exception('探测正在进行中，请等待完成');
    }
    if (isProbing.value) {
      throw Exception('探测正在进行中，请等待完成');
    }
    final future = start();
    final tracked = future.whenComplete(_clearInflightProbe);
    _inflightProbe = tracked;
    _inflightProbeFnId = fnId;
    return tracked;
  }

  void _clearInflightProbe() {
    _inflightProbe = null;
    _inflightProbeFnId = null;
  }

  @visibleForTesting
  void resetForTest() {
    _inflightProbe = null;
    _inflightProbeFnId = null;
    _cancelToken = null;
    isProbing.value = false;
  }

  /// 取消当前探测
  void cancel() {
    _cancelToken?.cancel();
  }

  /// 缓存优先探测（仅升级，不降级）
  ///
  /// 下次打开优先验证上次成功连接的 URL 是否仍可用（快探）：
  /// - 缓存可达：仅探测优先级高于缓存的候选，若更高优先级链路可达则自动切换（升级）；
  ///   否则保持缓存连接（不降级）。
  /// - 缓存不可达或已不在当前候选列表：回退到完整分层探测。
  ///
  /// 所有链路失败时抛出 [Exception]。
  Future<ConnectionProbeResult> probeSmart({
    required String fnId,
    String? cachedUrl,
    bool cachedIsRelay = false,
    List<ProbeCandidateGroup>? order,
  }) {
    return _joinOrStartProbe(
      fnId: fnId,
      start: () => _probeSmartCore(
        fnId: fnId,
        cachedUrl: cachedUrl,
        cachedIsRelay: cachedIsRelay,
        order: order,
      ),
    );
  }

  /// 缓存优先探测核心实现（被 [probeSmart] 调用，受单飞行守卫）
  Future<ConnectionProbeResult> _probeSmartCore({
    required String fnId,
    String? cachedUrl,
    bool cachedIsRelay = false,
    List<ProbeCandidateGroup>? order,
  }) async {
    final effOrder = effectiveOrder(
      order ?? AppFnConnectionSettings.connectionOrder.value,
    );

    isProbing.value = true;
    _cancelToken = CancelToken();

    try {
      if (kDebugMode) {
        debugPrint('[FnProbe] Trying cached connection: $cachedUrl');
      }

      // Step 1: 获取参数并构建按优先级排序的候选列表
      final params = await _callFnConnectionApi(fnId, _cancelToken!);
      final candidates = buildProbeCandidateSpecs(
        fnId: fnId,
        params: params,
        order: effOrder,
      );

      // Step 2: 缓存优先快探
      if (cachedUrl != null && cachedUrl.isNotEmpty) {
        final cachedIndex = candidates.indexWhere(
          (c) => c.address == cachedUrl,
        );
        if (cachedIndex >= 0) {
          final cacheOk = await _tryCachedAddress(
            cachedUrl,
            cachedIsRelay,
            _cancelToken!,
          );
          if (cacheOk) {
            if (_cancelToken!.isCancelled) throw Exception('探测已取消');

            // 探测优先级更高的候选（索引 < cachedIndex），首个可达者即升级。
            final better = candidates.sublist(0, cachedIndex);
            if (better.isNotEmpty) {
              final ProbeBestReachableResult upgrade =
                  await _probeBestReachable(
                    better,
                    _cancelToken!,
                    timeoutOverride: (_) => kFnUpgradeProbeTimeout,
                  );
              if (upgrade.best != null) {
                if (kDebugMode) {
                  debugPrint(
                    '[FnProbe] ✓ Upgraded (priority ${upgrade.bestIndex! + 1}): '
                    '${upgrade.best!.description}',
                  );
                }
                return ConnectionProbeResult(
                  serverUrl: upgrade.best!.address,
                  probeMethod: upgrade.best!.description,
                  isRelay: upgrade.best!.isRelay,
                );
              }
            }

            // 无更高优先级可达，保持缓存连接
            if (kDebugMode) {
              debugPrint('[FnProbe] Cached connection still valid: $cachedUrl');
            }
            return ConnectionProbeResult(
              serverUrl: cachedUrl,
              probeMethod: '缓存连接',
              isRelay: cachedIsRelay,
            );
          }
          // 缓存不可达 → 回退完整探测
        }
        // 缓存不在当前候选列表（陈旧地址）→ 忽略缓存，完整探测
      }

      // Step 3: 完整分层探测
      final result = await _hierarchicalProbe(
        fnId,
        params,
        cancelToken: _cancelToken!,
        order: effOrder,
      );

      if (kDebugMode) {
        debugPrint(
          '[FnProbe] Full probe succeeded: ${result.serverUrl} (${result.probeMethod})',
        );
      }
      return result;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw Exception('探测已取消');
      }
      if (kDebugMode) {
        debugPrint(
          '[FnProbe] DioException type=${e.type} message=${e.message} '
          'error=${e.error}',
        );
      }
      throw Exception('连接探测失败：${_dioErrorMessage(e)}');
    } finally {
      isProbing.value = false;
      _cancelToken = null;
      _clearInflightProbe();
    }
  }

  /// 快速验证某个地址是否可达（快探）。被其他探测占用时返回 null。
  Future<bool?> isAddressReachable(String url, {bool isRelay = false}) async {
    if (isProbing.value) return null;
    isProbing.value = true;
    _cancelToken = CancelToken();
    try {
      return await _tryCachedAddress(url, isRelay, _cancelToken!);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return null;
      }
      return false;
    } finally {
      isProbing.value = false;
      _cancelToken = null;
    }
  }

  /// 快速验证缓存连接是否可达（[cachedProbeTimeout] 快探）
  Future<bool> _tryCachedAddress(
    String url,
    bool isRelay,
    CancelToken cancelToken,
  ) async {
    final token = ApiClient.instance.token ?? '';
    final authChecked = token.isNotEmpty;
    try {
      // 已登录时缓存校验也打鉴权接口：TCP 可达但 token 被拒的缓存地址应视为失效。
      final probePath = authChecked ? '/music/api/v1/track/list' : '';
      final response = await _probeDio.getUri(
        Uri.parse(url + probePath),
        cancelToken: cancelToken,
        options: Options(
          connectTimeout: cachedProbeTimeout(isRelay),
          receiveTimeout: const Duration(seconds: 1),
          sendTimeout: const Duration(seconds: 1),
          followRedirects: false,
          validateStatus: (_) => true,
          // 鉴权与中继合并进同一个 Cookie 头，避免拆成两个键互相覆盖丢 mode=relay。
          headers: {
            if (authChecked)
              'Cookie': isRelay
                  ? 'music-token=$token; mode=relay'
                  : 'music-token=$token'
            else if (isRelay)
              'Cookie': 'mode=relay',
          },
        ),
      );
      if (!fnProbeResponseUsable(response, authChecked: authChecked)) {
        if (kDebugMode) {
          debugPrint(
            '[FnProbe] Cached check REJECTED $url (status ${response.statusCode})',
          );
        }
        return false;
      }
      return true;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        rethrow;
      }
      if (kDebugMode) {
        debugPrint(
          '[FnProbe] Cached check FAILED $url: ${_dioErrorMessage(e)}',
        );
      }
      return false;
    }
  }

  /// 调用 FN 接口获取连接参数
  Future<FnConnectionParams> _callFnConnectionApi(
    String fnId,
    CancelToken cancelToken,
  ) async {
    const apiPath = '/api/v1/fn/con';
    final url = 'https://5ddd.com$apiPath';
    final data = {'fnId': fnId};

    final response = await _probeDio.post(
      url,
      data: data,
      cancelToken: cancelToken,
      options: Options(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'authx': _computeAuthx('post', apiPath, data)},
      ),
    );

    final parsed = FnConnectionResponse.fromJson(
      response.data as Map<String, dynamic>,
    );

    if (!parsed.isSuccess || parsed.data == null) {
      throw Exception(parsed.msg.isNotEmpty ? parsed.msg : 'FNID 查询失败，请检查输入');
    }

    return parsed.data!;
  }

  /// 计算 authx 签名请求头
  ///
  /// 算法：
  ///   raw = PREFIX + url + nonce + timestamp + md5(参数) + apiKey
  ///   sign = md5(raw)
  ///   authx = nonce=xxx&timestamp=xxx&sign=xxx
  static String _computeAuthx(String method, String url, dynamic data) {
    final c = method == 'get'
        ? _sortAndSerializeQuery(data as Map<String, dynamic>?)
        : jsonEncode(data);
    final nonce = (Random().nextInt(900000) + 100000).toString().padLeft(
      6,
      '0',
    );
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final raw = [
      _authxPrefix,
      url,
      nonce,
      timestamp,
      _md5(c),
      _apiKey,
    ].join('_');
    final sign = _md5(raw);
    return 'nonce=$nonce&timestamp=$timestamp&sign=$sign';
  }

  static String _md5(String input) {
    return crypto.md5.convert(utf8.encode(input)).toString();
  }

  static String _sortAndSerializeQuery(Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) return '';
    final keys = params.keys.toList()..sort();
    return keys
        .map((k) => '$k=${Uri.encodeComponent(params[k].toString())}')
        .join('&');
  }

  /// 探测所有候选链路（用于「FN Connect」设置页完整展示）
  Future<
    ({
      List<ProbeCandidateResult> candidates,
      ConnectionProbeResult? firstSuccess,
    })
  >
  probeAllCandidates({
    required String fnId,
    List<ProbeCandidateGroup>? order,
  }) async {
    if (isProbing.value) {
      throw Exception('探测正在进行中，请等待完成');
    }

    isProbing.value = true;
    _cancelToken = CancelToken();

    try {
      final params = await _callFnConnectionApi(fnId, _cancelToken!);
      final candidates = buildProbeCandidateSpecs(
        fnId: fnId,
        params: params,
        order: effectiveOrder(
          order ?? AppFnConnectionSettings.connectionOrder.value,
        ),
      );

      // 并行探测所有候选
      final results = await Future.wait(
        candidates.map((c) => _tryAddressWithDetail(c, _cancelToken!)),
      );

      final firstSuccess = results
          .where((r) => r.isReachable)
          .map(
            (r) => ConnectionProbeResult(
              serverUrl: r.address,
              probeMethod: r.description,
              isRelay: r.isRelay,
            ),
          )
          .firstOrNull;

      return (candidates: results, firstSuccess: firstSuccess);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw Exception('探测已取消');
      }
      throw Exception('连接探测失败：${_dioErrorMessage(e)}');
    } finally {
      isProbing.value = false;
      _cancelToken = null;
    }
  }

  /// 并发探测所有候选，按优先级取「首个已确认可达」的链路，支持早停。
  Future<ProbeBestReachableResult> _probeBestReachable(
    List<ProbeCandidateSpec> candidates,
    CancelToken cancelToken, {
    Future<ProbeCandidateResult> Function(ProbeCandidateSpec, CancelToken)?
        probe,
    Duration Function(bool isRelay)? timeoutOverride,
  }) async {
    final pickTimeout = timeoutOverride ?? fnProbeTimeout;
    final doProbe = probe ??
        (ProbeCandidateSpec c, CancelToken token) =>
            _tryAddressWithDetail(c, token, timeoutOverride: pickTimeout);
    if (candidates.isEmpty) {
      return (
        best: null,
        bestIndex: null,
        decided: <ProbeCandidateResult>[],
      );
    }

    // 每个候选的探测 future 携带自身索引，Future.any 直接返回 (idx, result)。
    final pending = <int, Future<(int, ProbeCandidateResult)>>{
      for (var i = 0; i < candidates.length; i++)
        i: doProbe(candidates[i], cancelToken).then((r) => (i, r)),
    };

    ProbeCandidateResult? best;
    int? bestIndex;
    final decided = <ProbeCandidateResult>[];

    while (pending.isNotEmpty) {
      final (idx, r) = await Future.any(pending.values);
      pending.remove(idx);
      decided.add(r);

      if (cancelToken.isCancelled) throw Exception('探测已取消');

      if (r.isReachable) {
        if (bestIndex == null || idx < bestIndex) {
          bestIndex = idx;
          best = r;
        }
      }
      // 早停：已有确认可达者，且不存在仍未决定（索引更小）的更高优先级候选。
      final noBetterPending = bestIndex != null &&
          (bestIndex == 0 || !pending.keys.any((i) => i < bestIndex!));
      if (noBetterPending) {
        if (cancelToken.isCancelled) throw Exception('探测已取消');
        return (best: best, bestIndex: bestIndex, decided: decided);
      }
    }

    return (best: best, bestIndex: bestIndex, decided: decided);
  }

  /// 并发探测所有候选地址，按优先级取首个可用
  Future<ConnectionProbeResult> _hierarchicalProbe(
    String fnId,
    FnConnectionParams params, {
    required CancelToken cancelToken,
    required List<ProbeCandidateGroup> order,
  }) async {
    final candidates = buildProbeCandidateSpecs(
      fnId: fnId,
      params: params,
      order: effectiveOrder(order),
    );

    final ProbeBestReachableResult probeResult =
        await _probeBestReachable(candidates, cancelToken);

    final best = probeResult.best;
    if (best != null) {
      if (kDebugMode) {
        debugPrint(
          '[FnProbe] ✓ Success (priority ${probeResult.bestIndex! + 1}): '
          '${best.description}',
        );
      }
      return ConnectionProbeResult(
        serverUrl: best.address,
        probeMethod: best.description,
        isRelay: best.isRelay,
      );
    }

    // 全部失败：收集去重后的失败原因，帮助用户定位。
    final reasons = <String>[
      for (final r in probeResult.decided)
        if (!r.isReachable && r.error != null && r.error!.isNotEmpty)
          r.error!.replaceFirst(RegExp(r'^连接失败：'), ''),
    ];
    final distinct = reasons.toSet().toList();
    final detail = distinct.length <= 2
        ? distinct.join('；')
        : '${distinct.take(2).join('；')} 等 ${distinct.length} 种原因';
    final summary = detail.isNotEmpty
        ? '所有链路均无法连接：$detail。请检查网络、端口或稍后重试。'
        : '所有链路均无法连接，请检查网络或稍后重试。';
    throw Exception(summary);
  }

  /// 探测单条链路并返回探测结果详情
  Future<ProbeCandidateResult> _tryAddressWithDetail(
    ProbeCandidateSpec candidate,
    CancelToken cancelToken, {
    Duration Function(bool isRelay)? timeoutOverride,
  }) async {
    final timeout = (timeoutOverride ?? fnProbeTimeout)(candidate.relayMode);
    // 已登录时探测携带当前 token：候选须通过鉴权才算「可用」。
    final token = ApiClient.instance.token ?? '';
    final authChecked = token.isNotEmpty;
    try {
      final options = Options(
        connectTimeout: timeout,
        receiveTimeout: timeout,
        sendTimeout: timeout,
        followRedirects: false,
        validateStatus: (_) => true,
        headers: {
          if (authChecked)
            'Cookie': candidate.relayMode
                ? 'music-token=$token; mode=relay'
                : 'music-token=$token'
          else if (candidate.relayMode)
            'Cookie': 'mode=relay',
        },
      );

      // 已登录：打一个轻量鉴权接口验证 token 是否被该地址接受；未登录则探测根路径。
      final probePath = authChecked ? '/music/api/v1/track/list' : '';
      final response = await _probeDio.getUri(
        Uri.parse(candidate.address + probePath),
        options: options,
        cancelToken: cancelToken,
      );

      if (!fnProbeResponseUsable(response, authChecked: authChecked)) {
        if (kDebugMode) {
          debugPrint(
            '[FnProbe] Probe REJECTED ${candidate.description} '
            '(status ${response.statusCode})',
          );
        }
        return ProbeCandidateResult(
          address: candidate.address,
          description: candidate.description,
          group: candidate.group,
          ipLabel: candidate.ipLabel,
          isRelay: candidate.relayMode,
          isReachable: false,
          error: '连接可用但登录校验失败（token 未被该地址接受）',
        );
      }

      return ProbeCandidateResult(
        address: candidate.address,
        description: candidate.description,
        group: candidate.group,
        ipLabel: candidate.ipLabel,
        isRelay: candidate.relayMode,
        isReachable: true,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        rethrow;
      }
      if (kDebugMode) {
        debugPrint(
          '[FnProbe] Probe FAILED ${candidate.description}: ${_dioErrorMessage(e)}',
        );
      }
      return ProbeCandidateResult(
        address: candidate.address,
        description: candidate.description,
        group: candidate.group,
        ipLabel: candidate.ipLabel,
        isRelay: candidate.relayMode,
        isReachable: false,
        error: _dioErrorMessage(e),
      );
    }
  }

  /// 把 [DioException] 映射为可读的中文错误描述。
  String _dioErrorMessage(DioException e, {String? target}) {
    final targetPart =
        (target != null && target.isNotEmpty) ? '（$target）' : '';
    final detail = _extractConnectionDetail(e);
    if (detail.isNotEmpty) {
      switch (e.type) {
        case DioExceptionType.badResponse:
        case DioExceptionType.badCertificate:
        case DioExceptionType.cancel:
          break;
        default:
          return '$targetPart$detail';
      }
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时$targetPart';
      case DioExceptionType.receiveTimeout:
        return '响应超时$targetPart';
      case DioExceptionType.sendTimeout:
        return '发送超时$targetPart';
      case DioExceptionType.connectionError:
        return '连接失败$targetPart';
      case DioExceptionType.badResponse:
        return '服务器返回错误 (${e.response?.statusCode})$targetPart';
      case DioExceptionType.badCertificate:
        return '证书校验失败$targetPart';
      case DioExceptionType.cancel:
        return '请求已取消';
      default:
        return e.message ?? '未知网络错误';
    }
  }

  /// 从 [DioException] 提取底层连接错误的具体原因。
  String _extractConnectionDetail(DioException e) {
    if (e.error != null) {
      final detail = _describeConnectionError(e.error!);
      if (detail.isNotEmpty) return detail;
    }
    final msg = e.message ?? '';
    if (msg.isNotEmpty) {
      final detail = _describeConnectionError(msg);
      if (detail.isNotEmpty) return detail;
    }
    return '';
  }

  /// 识别单个错误对象/文本描述的具体连接失败原因。
  String _describeConnectionError(Object err) {
    final text = err.toString();
    final lower = text.toLowerCase();
    if (lower.contains('connection refused') ||
        lower.contains('econnrefused') ||
        lower.contains('10061')) {
      return '连接被拒绝（端口不通或服务未启动）';
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return '连接超时（端口无响应）';
    }
    if (lower.contains('network is unreachable') ||
        lower.contains('network unreachable') ||
        lower.contains('ehostunreach') ||
        lower.contains('enetunreach')) {
      return '网络不可达（目标主机不在当前网络）';
    }
    if (lower.contains('host not found') ||
        lower.contains('cannot resolve') ||
        lower.contains('failed to resolve') ||
        lower.contains('name or service not known')) {
      return '无法解析主机（DNS）';
    }
    if (lower.contains('handshake') || lower.contains('certificate')) {
      return 'TLS 握手失败（证书或 HTTPS 端口异常）';
    }
    return '';
  }

  /// 探测服务器根地址是否可达（检查 `/music/api/v1/health`）。
  /// 返回可达的服务器根地址（去掉尾斜杠）。
  Future<String?> probeServer(String serverRoot) async {
    final String root = serverRoot.trim().replaceAll(RegExp(r'/+$'), '');
    if (root.isEmpty) return null;
    try {
      final Response<dynamic> resp =
          await _probeDio.get<dynamic>('$root/music/api/v1/health');
      if (resp.statusCode == 200) return root;
    } catch (_) {}
    return null;
  }

  /// 顺序探测多个候选地址，返回第一个可达的（连接回退）。
  Future<String?> probeServers(List<String> candidates) async {
    for (final String c in candidates) {
      final String? ok = await probeServer(c);
      if (ok != null) return ok;
    }
    return null;
  }
}
