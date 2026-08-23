import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'dart:convert';

import '../../state/settings_fn_state.dart';
import 'api_models.dart';

/// FNOS 音乐 API 客户端（Dio 单例）。
///
/// - baseUrl 形如 `http://<nas>/music/api/v1`（FN Connect 探测后确定）
/// - 鉴权：Cookie `music-token=<token>`
/// - 密码登录前需对密码做 SHA-256
class ApiClient {
  ApiClient._() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        contentType: Headers.jsonContentType,
      ),
    )..interceptors.add(InterceptorsWrapper(
        onRequest: _onRequest,
        onError: _onError,
      ));
  }

  static final ApiClient instance = ApiClient._();

  /// 应用包名：媒体通知/Android Auto 的 content:// 封面 Provider authority
  /// 前缀（`{kApplicationId}.coverart`）。与 `android/app/build.gradle.kts`
  /// 的 applicationId 保持一致。
  static const String kApplicationId = 'com.fnmusic.app';

  late final Dio _dio;

  String? _baseUrl;
  String? _token;
  bool _relayMode = false;

  /// 收到 401（token 失效）时的回调；由 AuthService 注册，用于把失效会话
  /// 踢回登录页，避免应用停留在「半登录不可用」状态。
  void Function()? onUnauthorized;

  /// 当前 API 基础地址（含 `/music/api/v1` 后缀）。
  String? get baseUrl => _baseUrl;

  /// 当前登录 token。
  String? get token => _token;

  /// 是否为中继链接（FN Connect 中继链路）。开启后所有请求额外携带
  /// `Cookie: mode=relay`，登录请求也以此在中继上通过鉴权。
  bool get relayMode => _relayMode;

  /// 设置/取消中继模式。
  void setRelayMode(bool value) {
    _relayMode = value;
  }

  /// 已设置安全码时自动携带 x-access-code / x-access-source。
  Map<String, String> _accessCodeHeaders() {
    final String? code = AppFnConnectionSettings.accessCode;
    if (code == null || code.isEmpty) return const <String, String>{};
    return <String, String>{
      'x-access-code': base64.encode(utf8.encode(code)),
      'x-access-source': 'app',
    };
  }

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final String? token = _token;
    if (token != null && token.isNotEmpty) {
      options.headers['Cookie'] = _relayMode
          ? 'music-token=$token; mode=relay'
          : 'music-token=$token';
    } else if (_relayMode) {
      options.headers['Cookie'] = 'mode=relay';
    }
    options.headers.addAll(_accessCodeHeaders());
    handler.next(options);
  }

  void _onError(DioException err, ErrorInterceptorHandler handler) {
    // 401 表示未登录 / token 失效：清除内存 token 并通知认证层回退登录页。
    if (err.response?.statusCode == 401) {
      _token = null;
      onUnauthorized?.call();
    }
    handler.next(err);
  }

  /// 配置服务器地址（服务器根地址，自动拼接 `/music/api/v1`）。
  void setServerUrl(String serverRoot) {
    _baseUrl = '${serverRoot.trimRight()}/music/api/v1';
  }

  void setToken(String? token) => _token = token;

  /// 构造封面图 URL（FNOS `/static/cover`）。
  String? coverUrl(String? coverId, {int size = 300}) {
    if (coverId == null || coverId.isEmpty || _baseUrl == null) return null;
    return '$_baseUrl/static/cover?coverId=$coverId&size=$size';
  }

  /// 曲目流地址（FNOS `/track/stream`）。
  String? streamUrl(String? guid) {
    if (guid == null || guid.isEmpty || _baseUrl == null) return null;
    return '$_baseUrl/track/stream?guid=$guid';
  }

  /// 当前会话的鉴权头（Cookie: music-token + 中继 + 安全码），供播放器原生请求头注入。
  Map<String, String> authHeaders() {
    final String? token = _token;
    return <String, String>{
      if (token != null && token.isNotEmpty)
        'Cookie': _relayMode ? 'music-token=$token; mode=relay' : 'music-token=$token'
      else if (_relayMode)
        'Cookie': 'mode=relay',
      ..._accessCodeHeaders(),
    };
  }

  /// 图片下载鉴权头（flutter_cache_manager / audio_service 加载封面时注入）。
  static Map<String, String> imageAuthHeaders() {
    return instance.authHeaders();
  }

  /// 密码登录。password 为明文，内部做 SHA-256。
  ///
  /// 真实 FNOS 要求字段 `username` + `deviceId`（32 位 hex）；缺 deviceId 时
  /// 用全 0 占位仍可登录（原设计语义），AuthService 会传入持久化设备号。
  Future<FnLoginResult> login({
    required String user,
    required String password,
    String deviceId = '00000000000000000000000000000000',
  }) async {
    final String hashed = sha256.convert(utf8.encode(password)).toString();
    final Response<dynamic> resp = await _dio.post<dynamic>(
      '$_baseUrl/user/password-login',
      data: <String, Object?>{
        'username': user,
        'password': hashed,
        'deviceId': deviceId,
      },
    );
    final ApiResponse<FnLoginResult> result = ApiResponse<FnLoginResult>.fromJson(
      _asMap(resp.data),
      (Object? data) => FnLoginResult.fromJson(_asMap(data)),
    );
    if (!result.isOk) {
      // 120001：账号或密码错误（服务端 msg 为英文，用户看不懂）。
      if (result.code == 120001) {
        throw ApiException(result.code, '用户名或密码错误，请重试！');
      }
      throw ApiException(result.code, result.message);
    }
    _token = result.data?.token;
    return result.data!;
  }

  /// 发起带鉴权的 GET，返回原始 data 字段。
  Future<dynamic> getData(String path, {Map<String, Object?>? query}) async {
    final Response<dynamic> resp = await _dio.get<dynamic>(
      '$_baseUrl$path',
      queryParameters: query,
    );
    final Map<String, Object?> json = _asMap(resp.data);
    final ApiResponse<dynamic> result = ApiResponse<dynamic>.fromJson(
      json,
      (Object? data) => data,
    );
    if (!result.isOk) {
      throw ApiException(result.code, result.message);
    }
    return result.data;
  }

  /// 发起带鉴权的 POST，返回原始 data 字段。
  Future<dynamic> postData(String path, {Object? body}) async {
    final Response<dynamic> resp = await _dio.post<dynamic>(
      '$_baseUrl$path',
      data: body,
    );
    final Map<String, Object?> json = _asMap(resp.data);
    final ApiResponse<dynamic> result = ApiResponse<dynamic>.fromJson(
      json,
      (Object? data) => data,
    );
    if (!result.isOk) {
      throw ApiException(result.code, result.message);
    }
    return result.data;
  }

  /// 下载 URL 到本地文件（带鉴权；用于流缓存/转码拼接）。
  Future<void> downloadToFile(String url, String savePath) async {
    await _dio.download(url, savePath);
  }

  /// 请求服务端 HLS 转码，返回播放列表地址（相对或绝对）。
  Future<String?> requestTranscode(String guid) async {
    final Object? data = await postData(
      '/track/transcode',
      body: <String, Object?>{'guid': guid},
    );
    return _asMap(data)['url']?.toString();
  }

  /// 通知服务端停止转码（切歌/停止时调用，幂等）。
  Future<void> quitTranscode(String guid) async {
    try {
      await postData('/track/transcode/quit', body: <String, Object?>{'guid': guid});
    } catch (_) {}
  }

  /// 把转码播放列表地址解析为可直接播放的 URL：相对路径拼到 API base 上。
  String? resolvePlayUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final Uri u = Uri.parse(url);
    if (u.hasScheme) return url;
    final String? base = _baseUrl;
    if (base == null) return null;
    // base 无尾斜杠时相对解析会丢掉最后一段（/music/api/v1 → /music），
    // 补上尾斜杠使相对路径正确拼在 base 之后。
    final String baseWithSlash = base.endsWith('/') ? base : '$base/';
    return Uri.parse(baseWithSlash).resolveUri(u).toString();
  }

  /// 漫游随机播放：服务端随机返回一首曲目（[deviceId] 标识漫游流会话）。
  ///
  /// 真实 FNOS 响应 `data.current`（含 roamId + track），可选 `data.next`。
  Future<FnRoamStartResponse> roamStart(String deviceId) async {
    final Object? data = await getData(
      '/track/roam-start',
      query: <String, Object?>{'deviceId': deviceId},
    );
    return FnRoamStartResponse.fromJson(_asMap(data));
  }

  /// 漫游随机播放：接续 [roamStart] 建立的会话，服务端再随机给一首。
  ///
  /// [relativeRoamId] 为上一首的 roamId，服务端据此推进同一条漫游链。
  Future<FnRoamNextResponse> roamNext(String deviceId, String relativeRoamId) async {
    final Object? data = await getData(
      '/track/roam-next',
      query: <String, Object?>{
        'deviceId': deviceId,
        'relativeRoamId': relativeRoamId,
      },
    );
    return FnRoamNextResponse.fromJson(_asMap(data));
  }

  /// 获取曲目歌词列表（FNOS `/lyric/list`）。
  Future<FnLyricResponse> getLyrics(String trackGUID) async {
    final Object? data = await getData(
      '/lyric/list',
      query: <String, Object?>{'trackGUID': trackGUID},
    );
    return FnLyricResponse.fromJson(_asMap(data));
  }

  /// 获取首选歌词文本（LRC 格式）；无歌词时返回 null。
  Future<String?> getLyricText(String trackGUID) async {
    final FnLyricResponse lyricResponse = await getLyrics(trackGUID);
    final String? preferred = lyricResponse.preferred;
    if (preferred != null && preferred.isNotEmpty) {
      final FnLyric? matched = lyricResponse.list
          .where((l) => l.guid == preferred)
          .firstOrNull;
      if (matched != null) return matched.content;
    }
    if (lyricResponse.list.isNotEmpty) {
      return lyricResponse.list.first.content;
    }
    return null;
  }

  /// 播放历史（FNOS `/play-history/list`），供 Android Auto「最近」节点。
  Future<List<FnTrack>> getPlayHistory({int page = 1, int size = 40}) async {
    final Object? data = await getData(
      '/play-history/list',
      query: <String, Object?>{'page': page, 'size': size},
    );
    final Map<String, Object?> json = _asMap(data);
    final List<Object?> raw = (json['list'] as List<Object?>?) ??
        const <Object?>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnTrack.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  static Map<String, Object?> _asMap(Object? data) {
    if (data is Map<Object?, Object?>) {
      return data.cast<String, Object?>();
    }
    return const <String, Object?>{};
  }
}

/// API 层业务异常。
class ApiException implements Exception {
  const ApiException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => 'ApiException($code): $message';
}
