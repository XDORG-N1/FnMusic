import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/api_models.dart';
import 'package:fnmusic/app/services/feiniu/playlist_service.dart';
import 'package:fnmusic/app/services/player/stream_cache_service.dart';
import 'package:fnmusic/app/services/stats_service.dart';
import 'package:fnmusic/app/state/player_state.dart';
import 'package:fnmusic/pages/library/playlists_page.dart';
import 'package:fnmusic/pages/player/player_page.dart';

import '../../helpers/fake_engine.dart';

FnPlaylist _playlist(String guid, String name, {int trackCount = 0}) {
  return FnPlaylist(guid: guid, name: name, trackCount: trackCount);
}

FnTrack _track(int i) {
  return FnTrack.fromJson(<String, Object?>{
    'guid': 'trk_$i',
    'title': '歌$i',
    'duration': 210000,
    'artists': <Object?>[
      <String, Object?>{'guid': 'art-$i', 'name': '艺人$i'},
    ],
    'album': <String, Object?>{'guid': 'album-$i', 'name': '专辑$i'},
  });
}

/// 歌单页 + 歌单详情页：网格 / hero / 播放跳转播放器 / 更多菜单移除·加入。
void main() {
  late FakeEngine fakeMain;

  setUp(() {
    // 关闭播放器页动画：播放会跳转播放器页，动态渐变与旋转封面均为
    // `..repeat()` 无限动画，会让 pumpAndSettle 超时。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'dynamic_gradient_enabled': false,
      'player_rotate_cover': false,
    });
    ApiClient.instance.setServerUrl('http://test');
    StreamCacheService.instance.enabled = false;
    fakeMain = FakeEngine();
    setupPlayerForTest(fakeMain);
    StatsService.recordPlaylistPlayOverride = null;
    FnPlaylistService.fetchPlaylistsOverride = null;
    FnPlaylistService.fetchPlaylistTracksOverride = null;
    FnPlaylistService.addTrackOverride = null;
    FnPlaylistService.removeTrackOverride = null;
  });

  tearDown(() {
    StatsService.recordPlaylistPlayOverride = null;
    FnPlaylistService.fetchPlaylistsOverride = null;
    FnPlaylistService.fetchPlaylistTracksOverride = null;
    FnPlaylistService.addTrackOverride = null;
    FnPlaylistService.removeTrackOverride = null;
  });

  Future<void> pumpGrid(
    WidgetTester tester, {
    List<FnPlaylist> playlists = const <FnPlaylist>[],
  }) async {
    FnPlaylistService.fetchPlaylistsOverride = () async => playlists;
    await tester.pumpWidget(const MaterialApp(home: PlaylistsPage()));
    await tester.pumpAndSettle();
  }

  Future<void> pumpDetail(
    WidgetTester tester, {
    List<FnTrack> tracks = const <FnTrack>[],
  }) async {
    FnPlaylistService.fetchPlaylistTracksOverride = (String guid) async => tracks;
    await tester.pumpWidget(
      MaterialApp(
        home: PlaylistDetailPage(
          playlistGuid: 'pl_1',
          playlistName: '旅行',
          playlistTrackCount: tracks.length,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('网格渲染歌单：名称 + 曲目数', (WidgetTester tester) async {
    await pumpGrid(tester, playlists: <FnPlaylist>[
      _playlist('pl_1', '旅行', trackCount: 5),
      _playlist('pl_2', '学习'),
    ]);

    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('5 首'), findsOneWidget);
    expect(find.text('学习'), findsOneWidget);
    expect(find.text('0 首'), findsOneWidget);
  });

  testWidgets('点歌单进入详情 hero：共 N 首 + 歌曲节', (WidgetTester tester) async {
    FnPlaylistService.fetchPlaylistTracksOverride = (String guid) async =>
        <FnTrack>[_track(1), _track(2)];
    await pumpGrid(tester, playlists: <FnPlaylist>[
      _playlist('pl_1', '旅行', trackCount: 2),
    ]);

    await tester.tap(find.text('旅行'));
    await tester.pumpAndSettle();

    expect(find.byType(PlaylistDetailPage), findsOneWidget);
    // AppBar + hero 各一处名称。
    expect(find.text('旅行'), findsWidgets);
    expect(find.text('歌单'), findsOneWidget); // kicker
    expect(find.text('共 2 首'), findsOneWidget);
    expect(find.text('歌曲'), findsOneWidget);
    expect(find.text('播放全部'), findsOneWidget);
    expect(find.text('歌1'), findsOneWidget);
    expect(find.text('歌2'), findsOneWidget);
  });

  testWidgets('空歌单显示空态', (WidgetTester tester) async {
    await pumpDetail(tester);

    expect(find.text('歌单暂无歌曲'), findsOneWidget);
  });

  testWidgets('播放全部跳转播放器页', (WidgetTester tester) async {
    StatsService.recordPlaylistPlayOverride = (String id, String title) async {};
    await pumpDetail(tester, tracks: <FnTrack>[_track(1), _track(2)]);

    await tester.tap(find.text('播放全部'));
    await tester.pumpAndSettle();

    expect(fakeMain.playCalls, greaterThanOrEqualTo(1));
    expect(find.byType(PlayerPage), findsOneWidget);
  });

  testWidgets('点按曲目以整表为队列播放并跳转播放器页', (WidgetTester tester) async {
    StatsService.recordPlaylistPlayOverride = (String id, String title) async {};
    await pumpDetail(tester, tracks: <FnTrack>[_track(1), _track(2)]);

    await tester.tap(find.text('歌2'));
    await tester.pumpAndSettle();

    expect(fakeMain.playCalls, greaterThanOrEqualTo(1));
    expect(AppPlayerState.instance.currentIndex.value, 1);
    expect(AppPlayerState.instance.queue.value.length, 2);
    expect(find.byType(PlayerPage), findsOneWidget);
  });

  testWidgets('更多菜单：从歌单移除', (WidgetTester tester) async {
    String? removedPl;
    String? removedTrack;
    FnPlaylistService.removeTrackOverride = (String p, String t) async {
      removedPl = p;
      removedTrack = t;
    };
    await pumpDetail(tester, tracks: <FnTrack>[_track(1), _track(2)]);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('从歌单移除'));
    await tester.pumpAndSettle();

    // 确认对话框 → 移出后行消失。
    expect(find.text('移出歌单'), findsOneWidget);
    await tester.tap(find.text('移出'));
    await tester.pumpAndSettle();

    expect(removedPl, 'pl_1');
    expect(removedTrack, 'trk_1');
    expect(find.text('歌1'), findsNothing);
    expect(find.text('歌2'), findsOneWidget);
  });

  testWidgets('更多菜单：加入歌单弹出面板', (WidgetTester tester) async {
    FnPlaylistService.fetchPlaylistsOverride = () async => <FnPlaylist>[
          _playlist('pl_9', '收藏夹'),
        ];
    await pumpDetail(tester, tracks: <FnTrack>[_track(1)]);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入歌单'));
    await tester.pumpAndSettle();

    // 面板标题 + 列表中的歌单。
    expect(find.text('加入歌单'), findsOneWidget);
    expect(find.text('收藏夹'), findsOneWidget);
  });
}
