import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/api_models.dart';
import 'package:fnmusic/app/services/feiniu/album_service.dart';
import 'package:fnmusic/app/services/feiniu/artist_service.dart';
import 'package:fnmusic/app/services/player/stream_cache_service.dart';
import 'package:fnmusic/app/state/player_state.dart';
import 'package:fnmusic/pages/library/library_detail_pages.dart';

import '../../helpers/fake_engine.dart';

FnArtist _artist(String name) {
  return FnArtist.fromJson(<String, Object?>{
    'guid': 'g-$name',
    'name': name,
  });
}

FnTrack _track(
  int i, {
  int? trackNo,
  int? year,
  List<FnArtist>? artists,
  int duration = 210000,
}) {
  return FnTrack.fromJson(<String, Object?>{
    'guid': 'track-$i',
    'title': '歌$i',
    'trackNo': trackNo,
    'year': year,
    'duration': duration,
    'artists': (artists ?? <FnArtist>[_artist('艺人$i')])
        .map((FnArtist a) => <String, Object?>{
              'guid': a.guid,
              'name': a.name,
            })
        .toList(),
    'album': <String, Object?>{'guid': 'album-A', 'name': '专辑A'},
  });
}

void main() {
  late FakeEngine fakeMain;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ApiClient.instance.setServerUrl('http://test');
    StreamCacheService.instance.enabled = false;
    fakeMain = FakeEngine();
    setupPlayerForTest(fakeMain);
    FnAlbumService.fetchAlbumTracksOverride = null;
    FnArtistService.fetchArtistTracksOverride = null;
  });

  tearDown(() {
    FnAlbumService.fetchAlbumTracksOverride = null;
    FnArtistService.fetchArtistTracksOverride = null;
  });

  Future<void> pumpDetail(
    WidgetTester tester, {
    List<FnTrack> tracks = const <FnTrack>[],
  }) async {
    FnAlbumService.fetchAlbumTracksOverride =
        (String albumGuid) async => tracks;
    await tester.pumpWidget(
      MaterialApp(
        home: AlbumDetailPage(
          albumGuid: 'al',
          albumName: '专辑A',
          albumYear: 2001,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('专辑详情渲染头部信息与曲目列表', (WidgetTester tester) async {
    await pumpDetail(tester, tracks: <FnTrack>[
      _track(1, trackNo: 1, year: 2001,
          artists: <FnArtist>[_artist('艺人1'), _artist('艺人2')]),
      _track(2, trackNo: 2, year: 2001),
    ]);

    expect(find.text('专辑A'), findsWidgets);
    expect(find.text('艺人1 等'), findsOneWidget);
    expect(find.text('2首 · 2001'), findsOneWidget);
    expect(find.text('歌1'), findsOneWidget);
    expect(find.text('歌2'), findsOneWidget);
  });

  testWidgets('点按曲目以整表为队列播放', (WidgetTester tester) async {
    await pumpDetail(tester, tracks: <FnTrack>[
      _track(1, trackNo: 1),
      _track(2, trackNo: 2),
    ]);

    await tester.tap(find.text('歌2'));
    await tester.pumpAndSettle();

    expect(fakeMain.playCalls, greaterThanOrEqualTo(1));
    expect(AppPlayerState.instance.currentIndex.value, 1);
    expect(AppPlayerState.instance.queue.value.length, 2);
    expect(AppPlayerState.instance.currentSong.value?.title, '歌2');
  });

  testWidgets('随机播放按钮填充队列并播放', (WidgetTester tester) async {
    await pumpDetail(tester, tracks: <FnTrack>[
      _track(1, trackNo: 1),
      _track(2, trackNo: 2),
    ]);

    await tester.tap(find.byIcon(Icons.shuffle));
    await tester.pumpAndSettle();

    expect(fakeMain.playCalls, greaterThanOrEqualTo(1));
    expect(AppPlayerState.instance.queue.value.length, 2);
    expect(
      AppPlayerState.instance.currentSong.value?.title,
      isIn(<String>['歌1', '歌2']),
    );
  });

  testWidgets('顺序播放按钮按专辑顺序播放', (WidgetTester tester) async {
    await pumpDetail(tester, tracks: <FnTrack>[
      _track(1, trackNo: 1),
      _track(2, trackNo: 2),
    ]);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    expect(fakeMain.playCalls, greaterThanOrEqualTo(1));
    expect(AppPlayerState.instance.currentIndex.value, 0);
    expect(AppPlayerState.instance.currentSong.value?.title, '歌1');
  });

  testWidgets('排序面板按歌曲名称排序并切换封面/序号', (WidgetTester tester) async {
    await pumpDetail(tester, tracks: <FnTrack>[
      _track(1, trackNo: 1), // 歌1
      _track(2, trackNo: 2), // 歌2
    ]);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    // 排序方式默认轨道号，先选「歌曲名称」→ 歌1 在歌2 上方（轨道号 1<2 已同序）。
    await tester.tap(find.text('歌曲名称'));
    await tester.pumpAndSettle();
    final double y1 = tester.getTopLeft(find.text('歌1')).dy;
    final double y2 = tester.getTopLeft(find.text('歌2')).dy;
    expect(y1, lessThan(y2));

    // 切换为降序 → 歌2 在上。
    await tester.tap(find.text('降序'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('歌2')).dy,
      lessThan(tester.getTopLeft(find.text('歌1')).dy),
    );

    // 关闭封面显示 → 出现曲目序号。
    await tester.tap(find.text('显示专辑封面'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('服务端返回 100002 显示友好错误并可重试', (WidgetTester tester) async {
    // 第一次请求返回 100002（无 message），重试后成功。
    int calls = 0;
    FnAlbumService.fetchAlbumTracksOverride = (String albumGuid) async {
      calls++;
      if (calls == 1) throw ApiException(100002, '');
      return <FnTrack>[_track(1, trackNo: 1)];
    };

    await tester.pumpWidget(
      const MaterialApp(
        home: AlbumDetailPage(albumGuid: 'al', albumName: '专辑A'),
      ),
    );
    await tester.pumpAndSettle();

    // 友好提示 + 原始详情（含错误码）+ 重试按钮。
    expect(find.text('内容不存在或已被删除，请返回刷新后重试'), findsOneWidget);
    expect(find.text('ApiException(100002): '), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    // 点重试 → 第二次成功 → 渲染曲目。
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('歌1'), findsOneWidget);
    expect(find.text('内容不存在或已被删除，请返回刷新后重试'), findsNothing);
  });

  testWidgets('空专辑 guid 本地拦截并给出明确提示', (WidgetTester tester) async {
    FnAlbumService.fetchAlbumTracksOverride = null;
    await tester.pumpWidget(
      const MaterialApp(home: AlbumDetailPage(albumGuid: '')),
    );
    await tester.pumpAndSettle();

    expect(find.text('专辑标识缺失，请返回刷新后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('网络异常显示通用文案', (WidgetTester tester) async {
    FnAlbumService.fetchAlbumTracksOverride =
        (String albumGuid) async => throw Exception('boom');
    await tester.pumpWidget(
      const MaterialApp(
        home: AlbumDetailPage(albumGuid: 'al', albumName: '专辑A'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('加载失败，请检查网络后重试'), findsOneWidget);
    expect(find.text('Exception: boom'), findsOneWidget);
  });

  testWidgets('参与创作的歌手去重渲染并可进入歌手详情', (WidgetTester tester) async {
    FnAlbumService.fetchAlbumTracksOverride = (String albumGuid) async =>
        <FnTrack>[
          _track(1, trackNo: 1,
              artists: <FnArtist>[_artist('艺人A'), _artist('艺人B')]),
          _track(2, trackNo: 2,
              artists: <FnArtist>[_artist('艺人B'), _artist('艺人C')]),
        ];
    FnArtistService.fetchArtistTracksOverride =
        (String artistGuid) async => <FnTrack>[];

    await tester.pumpWidget(
      const MaterialApp(
        home: AlbumDetailPage(albumGuid: 'al', albumName: '专辑A'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('参与创作的歌手'), findsOneWidget);
    expect(find.text('艺人A'), findsOneWidget);
    expect(find.text('艺人B'), findsOneWidget);
    expect(find.text('艺人C'), findsOneWidget);

    // 点歌手进入歌手详情页。
    await tester.tap(find.text('艺人A'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtistDetailPage), findsOneWidget);
  });
}
