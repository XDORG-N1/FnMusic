import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnmusic/app/services/feiniu/account_entry.dart';
import 'package:fnmusic/app/services/feiniu/account_store.dart';
import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/auth_service.dart';
import 'package:fnmusic/app/services/session_cache.dart';
import 'package:fnmusic/app/state/settings_fn_state.dart';
import 'package:fnmusic/pages/settings/settings_page.dart';

import '../../helpers/fake_engine.dart';

/// 设置页「账号」区 + 退出登录。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AccountStore.instance.resetForTest();
    AuthService.instance.resetForTest();
    AppFnConnectionSettings.resetForTest();
    ApiClient.instance.setToken(null);
    ApiClient.instance.setRelayMode(false);
    ApiClient.instance.onUnauthorized = null;
    // 预置一个带 token 的激活账号，走 override 启动校验避免真实网络。
    await AccountStore.instance.ensureLoaded();
    await AccountStore.instance.addAccount(AccountEntry(
      id: 'http://t|u',
      serverUrl: 'http://t',
      userName: 'u',
      displayName: '测试用户',
      token: '0123456789abcdef0123456789abcdef',
    ));
    AuthService.validateSessionOverride = () async => true;
    await AuthService.instance.initialize();
    expect(AuthService.instance.status.value, AuthStatus.loggedIn);
    setupPlayerForTest(FakeEngine());
  });

  tearDown(() {
    AccountStore.instance.resetForTest();
    AuthService.instance.resetForTest();
    AppFnConnectionSettings.resetForTest();
    ApiClient.instance.setToken(null);
    ApiClient.instance.setRelayMode(false);
    ApiClient.instance.onUnauthorized = null;
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('渲染账号区：当前账号 + 退出登录', (WidgetTester tester) async {
    await pumpSettings(tester);

    expect(find.text('账号'), findsOneWidget);
    expect(find.text('测试用户'), findsOneWidget);
    expect(find.text('u · http://t'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
  });

  testWidgets('确认对话框点「取消」不登出', (WidgetTester tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    // 对话框出现：取消 + 退出登录 两个按钮。
    expect(
      find.textContaining('已保存的账号与连接信息仍保留'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(AuthService.instance.status.value, AuthStatus.loggedIn);
    expect(find.text('退出登录'), findsOneWidget);
  });

  testWidgets('确认退出登录 → 登出并清除会话缓存', (WidgetTester tester) async {
    // 预置上一账号的首页缓存，验证登出会清掉。
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(SessionCache.homeDashboardKey, '{"favorites":[]}');

    await pumpSettings(tester);

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '退出登录'));
    await tester.pumpAndSettle();

    expect(AuthService.instance.status.value, AuthStatus.loggedOut);
    expect(ApiClient.instance.token, isNull);
    expect(AccountStore.instance.activeAccount?.token, isNull);
    final SharedPreferences after = await SharedPreferences.getInstance();
    expect(after.getString(SessionCache.homeDashboardKey), isNull);
  });
}
