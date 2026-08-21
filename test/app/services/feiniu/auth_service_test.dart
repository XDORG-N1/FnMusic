import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnmusic/app/services/feiniu/account_entry.dart';
import 'package:fnmusic/app/services/feiniu/account_store.dart';
import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/auth_service.dart';

/// 验证 401（token 失效）会把失效会话踢回登录页（回退重新登录），
/// 而不是让应用停留在「半登录不可用」状态。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AccountStore.instance.resetForTest();
    AuthService.instance.resetForTest();
    ApiClient.instance.setToken(null);
    ApiClient.instance.onUnauthorized = null;
  });

  tearDown(() {
    AccountStore.instance.resetForTest();
    AuthService.instance.resetForTest();
    ApiClient.instance.setToken(null);
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
}
