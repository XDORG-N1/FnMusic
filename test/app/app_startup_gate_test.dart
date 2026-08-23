import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnmusic/app/app.dart';
import 'package:fnmusic/app/router/app_router.dart';
import 'package:fnmusic/app/services/feiniu/account_entry.dart';
import 'package:fnmusic/app/services/feiniu/account_store.dart';
import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/auth_service.dart';
import 'package:fnmusic/app/state/settings_fn_state.dart';
import 'package:fnmusic/app/state/settings_onboarding.dart';

/// 启动门（AppStartupGate）分流：restoring 闪屏 / 登录页 / 主外壳。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SettingsOnboarding.completed.value = false;
    await SettingsOnboarding.setCompleted(true);
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

  Future<void> seedAccount({
    String serverUrl = 'http://t',
    String userName = 'u',
    String displayName = '测试用户',
  }) async {
    await AccountStore.instance.ensureLoaded();
    await AccountStore.instance.addAccount(AccountEntry(
      id: '$serverUrl|$userName',
      serverUrl: serverUrl,
      userName: userName,
      displayName: displayName,
      token: token,
    ));
  }

  Future<void> pumpGate(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: const AppStartupGate()),
    );
  }

  testWidgets('无已保存账号 → 直接到登录页（不闪首页）', (WidgetTester tester) async {
    await pumpGate(tester);
    await tester.pumpAndSettle();

    expect(find.byType(PrimaryNavigationShell), findsNothing);
    expect(find.text('登录飞牛音乐'), findsOneWidget);
  });

  testWidgets('恢复会话期间显示闪屏，而非登录页', (WidgetTester tester) async {
    await seedAccount();
    // 永不完成的校验：initialize 停在 restoring。
    AuthService.validateSessionOverride = () => Completer<bool>().future;

    await pumpGate(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('正在恢复会话…'), findsOneWidget);
    expect(find.text('登录飞牛音乐'), findsNothing);
    expect(find.byType(PrimaryNavigationShell), findsNothing);
    expect(AuthService.instance.status.value, AuthStatus.restoring);
  });

  testWidgets('启动校验失败（token 失效）→ 回登录页', (WidgetTester tester) async {
    await seedAccount();
    AuthService.validateSessionOverride = () async => false;

    await pumpGate(tester);
    await tester.pumpAndSettle();

    expect(AuthService.instance.status.value, AuthStatus.loggedOut);
    expect(find.byType(PrimaryNavigationShell), findsNothing);
    expect(find.text('登录飞牛音乐'), findsOneWidget);
  });

  testWidgets('启动校验成功 → 进入主外壳', (WidgetTester tester) async {
    await seedAccount();
    AuthService.validateSessionOverride = () async => true;

    await pumpGate(tester);
    await tester.pumpAndSettle();

    expect(AuthService.instance.status.value, AuthStatus.loggedIn);
    expect(find.byType(PrimaryNavigationShell), findsOneWidget);
    expect(find.text('登录飞牛音乐'), findsNothing);
  });
}
