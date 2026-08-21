import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fnmusic/components/list/sort_sheet.dart';

void main() {
  testWidgets('SortSheet 渲染全部选项与当前选中项', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SortSheet(
            options: const <SortOption>[
              SortOption(key: 'name', label: '专辑名', icon: Icons.sort_by_alpha),
              SortOption(key: 'year', label: '发行年份', icon: Icons.calendar_today),
            ],
            currentKey: 'name',
            ascending: true,
            onSelectKey: (_) {},
            onSelectAscending: (_) {},
            title: '专辑排序',
          ),
        ),
      ),
    );

    expect(find.text('专辑排序'), findsOneWidget);
    expect(find.text('专辑名'), findsOneWidget);
    expect(find.text('发行年份'), findsOneWidget);
    expect(find.text('升序'), findsOneWidget);
    expect(find.text('降序'), findsOneWidget);
  });

  testWidgets('点击选项与升降序回调', (WidgetTester tester) async {
    String? selectedKey;
    bool? selectedAscending;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SortSheet(
            options: const <SortOption>[
              SortOption(key: 'name', label: '专辑名', icon: Icons.sort_by_alpha),
              SortOption(key: 'year', label: '发行年份', icon: Icons.calendar_today),
            ],
            currentKey: 'name',
            ascending: true,
            onSelectKey: (String key) => selectedKey = key,
            onSelectAscending: (bool asc) => selectedAscending = asc,
          ),
        ),
      ),
    );

    // 点击「发行年份」选项。
    await tester.tap(find.text('发行年份'));
    await tester.pumpAndSettle();
    expect(selectedKey, 'year');

    // 点击「降序」。
    await tester.tap(find.text('降序'));
    await tester.pumpAndSettle();
    expect(selectedAscending, false);

    // 再次点击「升序」。
    await tester.tap(find.text('升序'));
    await tester.pumpAndSettle();
    expect(selectedAscending, true);
  });
}
