import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/api_models.dart';
import 'package:fnmusic/app/services/feiniu/playlist_service.dart';
import 'package:fnmusic/app/state/song_state.dart';
import 'package:fnmusic/components/playlist/add_to_playlist_sheet.dart';

/// 「加入歌单」面板：列歌单点选加入 / 新建歌单并加入 / 拉取失败重试。
void main() {
  const SongEntity track = SongEntity(
    guid: 'trk_x',
    title: '测试歌',
    artistDisplay: '艺人',
    durationMs: 210000,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ApiClient.instance.setServerUrl('http://test');
    FnPlaylistService.fetchPlaylistsOverride = null;
    FnPlaylistService.createPlaylistOverride = null;
    FnPlaylistService.addTrackOverride = null;
  });

  tearDown(() {
    FnPlaylistService.fetchPlaylistsOverride = null;
    FnPlaylistService.createPlaylistOverride = null;
    FnPlaylistService.addTrackOverride = null;
  });

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                onPressed: () => showAddToPlaylistSheet(context, track),
                child: const Text('打开加入面板'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('点歌单 → addTrack 并回填 SnackBar', (WidgetTester tester) async {
    final List<(String, String)> adds = <(String, String)>[];
    FnPlaylistService.fetchPlaylistsOverride = () async => <FnPlaylist>[
          const FnPlaylist(guid: 'pl_1', name: '旅行', trackCount: 3),
          const FnPlaylist(guid: 'pl_2', name: '学习', trackCount: 0),
        ];
    FnPlaylistService.addTrackOverride = (String p, String t) async {
      adds.add((p, t));
    };

    await pumpHost(tester);
    await tester.tap(find.text('打开加入面板'));
    await tester.pumpAndSettle();

    // 面板列出歌单（名称 + 曲目数）。
    expect(find.text('加入歌单'), findsOneWidget);
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('3 首'), findsOneWidget);
    expect(find.text('学习'), findsOneWidget);

    await tester.tap(find.text('旅行'));
    await tester.pumpAndSettle();

    expect(adds, <(String, String)>[('pl_1', 'trk_x')]);
    expect(find.text('已加入《旅行》'), findsOneWidget);
  });

  testWidgets('新建歌单 → createPlaylist + addTrack', (WidgetTester tester) async {
    String? created;
    final List<(String, String)> adds = <(String, String)>[];
    FnPlaylistService.fetchPlaylistsOverride = () async => <FnPlaylist>[];
    FnPlaylistService.createPlaylistOverride = (String name) async {
      created = name;
      return 'pl_new';
    };
    FnPlaylistService.addTrackOverride = (String p, String t) async {
      adds.add((p, t));
    };

    await pumpHost(tester);
    await tester.tap(find.text('打开加入面板'));
    await tester.pumpAndSettle();
    expect(find.text('暂无歌单，先新建一个吧'), findsOneWidget);

    await tester.tap(find.text('新建歌单'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '我的精选');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(created, '我的精选');
    expect(adds, <(String, String)>[('pl_new', 'trk_x')]);
    expect(find.text('已加入《我的精选》'), findsOneWidget);
  });

  testWidgets('拉取失败显示错误并可重试', (WidgetTester tester) async {
    int calls = 0;
    FnPlaylistService.fetchPlaylistsOverride = () async {
      calls++;
      if (calls == 1) throw Exception('boom');
      return const <FnPlaylist>[FnPlaylist(guid: 'pl_1', name: '旅行')];
    };

    await pumpHost(tester);
    await tester.tap(find.text('打开加入面板'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Exception'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('旅行'), findsOneWidget);
  });
}
