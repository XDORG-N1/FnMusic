import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnmusic/app/services/feiniu/account_entry.dart';
import 'package:fnmusic/app/services/feiniu/account_store.dart';
import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/auth_service.dart';
import 'package:fnmusic/app/state/settings_fn_state.dart';
import 'package:fnmusic/pages/login/login_page.dart';

/// 回归：登出（token 已清除）后，点「已保存账号」不再假装一键登录——
/// 停留在登录页、自动预填并提示重新输入密码，而不是错误地切走或停留在
/// 无提示的登录页。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AccountStore.instance.resetForTest();
    AuthService.instance.resetForTest();
    AppFnConnectionSettings.resetForTest();
    ApiClient.instance.setToken(null);
    ApiClient.instance.setRelayMode(false);
  });

  tearDown(() {
    AccountStore.instance.resetForTest();
    AuthService.instance.resetForTest();
    AppFnConnectionSettings.resetForTest();
    ApiClient.instance.setToken(null);
    ApiClient.instance.setRelayMode(false);
  });

  testWidgets('已退出登录的账号：点保存卡片 → 预填 + 提示重新输入密码，不切走', (WidgetTester tester) async {
    await AccountStore.instance.ensureLoaded();
    await AccountStore.instance.addAccount(AccountEntry(
      id: 'http://t|u',
      serverUrl: 'http://t',
      userName: 'u',
      displayName: '测试用户',
      // 登出后 token 为 null（模拟退出登录后的已保存账号）。
      token: null,
    ));

    await tester.pumpWidget(
      const MaterialApp(home: LoginPage()),
    );
    await tester.pumpAndSettle();

    // 登录页 + 已保存账号卡片可见（displayName 也预填进了账号名称输入框，
    // 故用 ListTile 限定只匹配卡片）。
    expect(find.text('已保存账号'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '测试用户'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ListTile, '测试用户'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '测试用户'));
    await tester.pumpAndSettle();

    // 仍停留在登录页（无 token，无法静默登录）。
    expect(find.text('登录飞牛音乐'), findsOneWidget);
    // 提示重新输入密码。
    expect(
      find.text('测试用户 已退出登录，请重新输入密码'),
      findsOneWidget,
    );
    expect(AuthService.instance.status.value, AuthStatus.loggedOut);
  });
}
