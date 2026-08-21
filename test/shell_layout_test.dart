import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnmusic/app/router/app_router.dart';

void main() {
  // 首页 initState 会读写 SharedPreferences（本地首屏缓存），测试前预置空值。
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('窄屏使用底部导航栏', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: PrimaryNavigationShell(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('首页'), findsWidgets);
  });

  testWidgets('宽屏使用侧边导航栏', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: PrimaryNavigationShell(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('宽屏点击侧边导航切换 tab', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: PrimaryNavigationShell(),
    ));
    await tester.pumpAndSettle();

    // 初始在首页 tab；点击「音乐库」。
    await tester.tap(find.text('音乐库'));
    await tester.pumpAndSettle();

    expect(find.text('全部歌曲'), findsOneWidget);
  });
}
