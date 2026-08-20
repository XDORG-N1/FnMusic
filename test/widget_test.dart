import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnmusic/app/app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('App boots to onboarding on first launch', (WidgetTester tester) async {
    await tester.pumpWidget(const FnMusicApp());
    await tester.pumpAndSettle();

    // 首次启动显示引导页。
    expect(find.text('欢迎使用飞牛音乐'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);
  });
}
