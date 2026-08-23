import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../state/settings_fn_state.dart';
import '../session_cache.dart';
import 'account_entry.dart';
import 'account_store.dart';
import 'api_client.dart';
import 'api_models.dart';

/// 登录状态。
enum AuthStatus { restoring, loggedOut, connecting, loggedIn }

/// 认证服务：登录 / 登出 / 会话恢复。
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const String _prefsDeviceId = 'auth_device_id';

  final ValueNotifier<AuthStatus> status =
      ValueNotifier<AuthStatus>(AuthStatus.loggedOut);

  bool _initialized = false;

  String? _deviceId;
  String? _cachedDeviceId;

  /// 启动校验钩子（测试注入）：返回 true 视为会话有效，false 视为失效。
  @visibleForTesting
  static Future<bool> Function()? validateSessionOverride;

  /// 启动时恢复已保存账号的会话。
  ///
  /// 先进入 [AuthStatus.restoring]（启动门显示闪屏，避免「先登录页后首页」
  /// 的闪烁）；随后恢复账号上下文并轻量校验 token，再落到 [AuthStatus.loggedIn]
  /// 或 [AuthStatus.loggedOut]。
  Future<void> initialize() async {
    // 401（token 失效）→ 登出并回退登录页。注册放在 early-return 之前，
    // 保证无论何时初始化回调都生效；仅当处于已登录态才触发，避免干扰
    // 恢复中（restoring）、登录中（connecting）或已登出（loggedOut）的其它
    // 401 场景。
    ApiClient.instance.onUnauthorized = () {
      if (status.value == AuthStatus.loggedIn) {
        unawaited(logout());
      }
    };
    if (_initialized) return;
    // 同步置位：恢复期间首页/登录页都不展示。
    status.value = AuthStatus.restoring;
    await AccountStore.instance.ensureLoaded();
    final AccountEntry? account = AccountStore.instance.activeAccount;
    if (account != null && account.token != null && account.token!.isNotEmpty) {
      ApiClient.instance.setServerUrl(account.serverUrl);
      ApiClient.instance.setRelayMode(account.relayMode);
      ApiClient.instance.setToken(account.token);
      // 补齐连接上下文：重启后首页请求需带上安全码 / 中继 / 连接信息，
      // 否则带安全码或中继的账号请求会被服务器拒绝而显示异常。
      await AppFnConnectionSettings.restoreConnection(
        url: account.serverUrl,
        isRelay: account.relayMode,
        fnId: account.fnId,
        method: account.relayMode ? '中继链接' : null,
      );
      await AppFnConnectionSettings.setAccessCode(account.accessCode);
      final bool valid = await _validateSession();
      if (valid) {
        status.value = AuthStatus.loggedIn;
      } else {
        // token 已失效：清掉持久化 token，避免下次启动再次进入失效会话。
        await logout();
      }
    } else {
      status.value = AuthStatus.loggedOut;
    }
    _initialized = true;
  }

  /// 轻量会话校验：打 `/track/list`（与连接探测的 authChecked 端点一致）。
  ///
  /// - 200 → 有效；
  /// - 401 → 失效（Dio 拦截器已置空内存 token，这里只需返回 false）；
  /// - 超时 / 无网 → 视为离线，保留会话，首页走本地缓存。
  Future<bool> _validateSession() async {
    final Future<bool> Function()? override = validateSessionOverride;
    if (override != null) return override();
    try {
      await ApiClient.instance
          .getData('/track/list', query: <String, Object?>{'page': 1, 'size': 1})
          .timeout(const Duration(seconds: 5));
      return true;
    } on DioException catch (e) {
      return e.response?.statusCode != 401;
    } catch (_) {
      return true;
    }
  }

  /// 生成设备 ID（32 位 hex）。
  static String generateDeviceId() {
    final Random random = Random();
    return List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// 获取设备 ID（首次生成并持久化，回退全 0 占位）。
  String getOrCreateDeviceId() {
    if (_deviceId != null) return _deviceId!;
    _deviceId = _cachedDeviceId;
    if (_deviceId != null) return _deviceId!;
    // 异步生成；未就绪前先用全 0 占位（原设计语义）。
    unawaited(_initDeviceId());
    return _deviceId ?? '00000000000000000000000000000000';
  }

  Future<void> _initDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_prefsDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = generateDeviceId();
      await prefs.setString(_prefsDeviceId, deviceId);
    }
    _deviceId = deviceId;
  }

  /// 登录并保存账号。
  ///
  /// [relayMode] 为 true 时，登录请求及后续所有 API 请求自动携带
  /// `Cookie: mode=relay`（FN Connect 中继链路）。[fnId] 记录来源 FNID。
  Future<AccountEntry> login({
    required String serverUrl,
    required String user,
    required String password,
    String? displayName,
    bool relayMode = false,
    String? fnId,
  }) async {
    status.value = AuthStatus.connecting;
    try {
      ApiClient.instance.setServerUrl(serverUrl);
      ApiClient.instance.setRelayMode(relayMode);
      final FnLoginResult result = await ApiClient.instance.login(
        user: user,
        password: password,
        deviceId: getOrCreateDeviceId(),
      );
      final AccountEntry entry = AccountEntry(
        id: '$serverUrl|$user',
        serverUrl: serverUrl,
        userName: user,
        displayName: displayName ?? result.name,
        token: result.token,
        relayMode: relayMode,
        accessCode: AppFnConnectionSettings.accessCode,
        fnId: fnId,
      );
      await AccountStore.instance.addAccount(entry);
      await AccountStore.instance.setActiveAccount(entry.id);
      status.value = AuthStatus.loggedIn;
      return entry;
    } catch (e) {
      status.value = AuthStatus.loggedOut;
      rethrow;
    }
  }

  /// 切换账号（使用已保存的 token）。
  ///
  /// 返回是否真正切入了会话。登出会清除持久化 token，此时账号虽保留但已失效，
  /// 无法静默登录（否则下次启动会自动登录，违背「退出登录」语义），调用方应
  /// 引导用户重新输入密码。
  Future<bool> switchToAccount(AccountEntry account) async {
    await AccountStore.instance.setActiveAccount(account.id);
    if (account.token == null || account.token!.isEmpty) return false;
    ApiClient.instance.setServerUrl(account.serverUrl);
    ApiClient.instance.setRelayMode(account.relayMode);
    ApiClient.instance.setToken(account.token);
    status.value = AuthStatus.loggedIn;
    return true;
  }

  /// 登出。
  Future<void> logout() async {
    final AccountEntry? account = AccountStore.instance.activeAccount;
    if (account != null) {
      // clearToken: 登出必须真正清除持久化的 token，否则重启后 initialize()
      // 会再次恢复这条已失效的会话（token ?? this.token 无法置 null）。
      final AccountEntry updated = account.copyWith(clearToken: true);
      await AccountStore.instance.addAccount(updated);
    }
    ApiClient.instance.setToken(null);
    ApiClient.instance.setRelayMode(false);
    // 清连接信息（安全码 / 连接地址等，保留 FNID 供登录页预填）与会话缓存，
    // 避免账号间数据串台。
    await AppFnConnectionSettings.clearConnection();
    await SessionCache.clearAll();
    status.value = AuthStatus.loggedOut;
  }

  /// 测试用：重置内存状态（SharedPreferences mock 由测试方重置）。
  @visibleForTesting
  void resetForTest() {
    _initialized = false;
    _deviceId = null;
    _cachedDeviceId = null;
    validateSessionOverride = null;
    status.value = AuthStatus.loggedOut;
  }
}
