import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnmusic/app/services/feiniu/account_entry.dart';
import 'package:fnmusic/app/services/feiniu/account_store.dart';
import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/auth_service.dart';
import 'package:fnmusic/app/services/session_cache.dart';
import 'package:fnmusic/app/state/settings_fn_state.dart';

/// 验证 401（token 失效）会把失效会话踢回登录页（回退重新登录），
/// 而不是让应用停留在「半登录不可用」状态。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AccountStore.instance.resetForTest();
    AuthService.instance.resetForTest();
    AppFnConnectionSettings.resetForTest();
    ApiClient.instance.setToken(null);
    ApiClient.instance.setRelayMode(false);
    ApiClient.instance.onUnauthorized = null;
  });

  tearDown(() {
    AccountStore.instance.resetForTest();
    AuthService.instance.resetForTest();
    AppFnConnectionSettings.resetForTest();
    ApiClient.instance.setToken(null);
    ApiClient.instance.setRelayMode(false);
    ApiClient.instance.onUnauthorized = null;
  });

  const String token = '0123456789abcdef0123456789abcdef';

  test('已登录时收到 401 回调 → 登出并回退登录页', () async {
    // 先恢复一个带 token 的激活账号，模拟登录成功后的会话。
    await AccountStore.instance.ensureLoaded();
    await AccountStore.instance.addAccount(AccountEntry(
      id: 'http://t|u',
      serverUrl: 'http://t',
      userName: 'u',
      displayName: '测试用户',
      token: token,
    ));
    // 启动校验走 override（true），避免测试环境真实网络。
    AuthService.validateSessionOverride = () async => true;

    await AuthService.instance.initialize();
    expect(AuthService.instance.status.value, AuthStatus.loggedIn);
    expect(ApiClient.instance.onUnauthorized, isNotNull);

    // 模拟任意 API 请求返回 401 时拦截器触发的回调。
    ApiClient.instance.onUnauthorized!();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(AuthService.instance.status.value, AuthStatus.loggedOut);
    expect(ApiClient.instance.token, isNull);
    expect(AccountStore.instance.activeAccount?.token, isNull);
  });

  test('未登录 / 登录中收到 401 不误触登出', () async {
    await AuthService.instance.initialize();
    // 无激活账号 → 初始 loggedOut；模拟登录请求进行中（connecting）。
    AuthService.instance.status.value = AuthStatus.connecting;
    ApiClient.instance.setToken(token);

    ApiClient.instance.onUnauthorized!();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(AuthService.instance.status.value, AuthStatus.connecting);
    expect(ApiClient.instance.token, isNotNull);
  });

  test('启动校验成功 → 恢复为已登录，补齐 relay / 安全码 / 连接信息', () async {
    await AccountStore.instance.ensureLoaded();
    await AccountStore.instance.addAccount(AccountEntry(
      id: 'https://nas|u',
      serverUrl: 'https://nas',
      userName: 'u',
      displayName: '中继用户',
      token: token,
      relayMode: true,
      accessCode: 'c2VjcmV0',
      fnId: 'fnid123456',
    ));
    AuthService.validateSessionOverride = () async => true;

    await AuthService.instance.initialize();

    expect(AuthService.instance.status.value, AuthStatus.loggedIn);
    expect(ApiClient.instance.token, token);
    expect(ApiClient.instance.relayMode, isTrue);
    expect(AppFnConnectionSettings.accessCode, 'c2VjcmV0');
    expect(AppFnConnectionSettings.currentConnectionUrl.value, 'https://nas');
  });

  test('启动校验失败（token 失效）→ 登出并清除持久化会话缓存', () async {
    // 预置上一账号的首页仪表盘缓存，模拟账号间串台数据。
    SharedPreferences.setMockInitialValues(<String, Object>{
      SessionCache.homeDashboardKey: '{"favorites":[]}',
    });
    await AccountStore.instance.ensureLoaded();
    await AccountStore.instance.addAccount(AccountEntry(
      id: 'http://t|u',
      serverUrl: 'http://t',
      userName: 'u',
      displayName: '测试用户',
      token: token,
    ));
    AuthService.validateSessionOverride = () async => false;

    await AuthService.instance.initialize();

    expect(AuthService.instance.status.value, AuthStatus.loggedOut);
    expect(ApiClient.instance.token, isNull);
    expect(AccountStore.instance.activeAccount?.token, isNull);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SessionCache.homeDashboardKey), isNull);
  });

  test('登出清除会话缓存（首页仪表盘）', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SessionCache.homeDashboardKey: '{"favorites":[]}',
    });
    await AccountStore.instance.ensureLoaded();
    await AccountStore.instance.addAccount(AccountEntry(
      id: 'http://t|u',
      serverUrl: 'http://t',
      userName: 'u',
      displayName: '测试用户',
      token: token,
    ));

    await AuthService.instance.logout();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SessionCache.homeDashboardKey), isNull);
    expect(AppFnConnectionSettings.accessCode, isNull);
  });

  test('switchToAccount：有 token 静默切换；token 已清（登出后）返回 false', () async {
    // 场景 A：带有效 token 的已保存账号 → 静默切换进首页。
    await AccountStore.instance.ensureLoaded();
    await AccountStore.instance.addAccount(AccountEntry(
      id: 'http://t|u',
      serverUrl: 'http://t',
      userName: 'u',
      displayName: '测试用户',
      token: token,
    ));
    final AccountEntry? account = AccountStore.instance.activeAccount;
    expect(account, isNotNull);
    final bool switched = await AuthService.instance.switchToAccount(account!);
    expect(switched, isTrue);
    expect(AuthService.instance.status.value, AuthStatus.loggedIn);
    expect(ApiClient.instance.token, token);

    // 场景 B：登出（token 被清除）后同一账号无法静默切换，
    // 需重新输入密码（回归：登出后一键登录曾停留在登录页）。
    await AuthService.instance.logout();
    final AccountEntry? signedOut = AccountStore.instance.activeAccount;
    expect(signedOut?.token, isNull);
    final bool again = await AuthService.instance.switchToAccount(signedOut!);
    expect(again, isFalse);
    expect(AuthService.instance.status.value, AuthStatus.loggedOut);
    expect(ApiClient.instance.token, isNull);
  });
}
