import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/api_models.dart';
import 'package:fnmusic/app/services/feiniu/genre_service.dart';
import 'package:fnmusic/app/services/player/stream_cache_service.dart';
import 'package:fnmusic/app/state/player_state.dart';
import 'package:fnmusic/pages/library/genres_page.dart';

import '../../helpers/fake_engine.dart';

FnGenre _genre(String name, {int trackCount = 3, String? coverId}) {
  return FnGenre.fromJson(<String, Object?>{
    'guid': 'gen-$name',
    'name': name,
    'trackCount': trackCount,
    'coverId': ?coverId,
  });
}

FnTrack _track(int i, {int duration = 210000, String? artist}) {
  return FnTrack.fromJson(<String, Object?>{
    'guid': 'track-$i',
    'title': '歌$i',
    'trackNo': i,
    'year': 2020,
    'duration': duration,
    'artists': <Map<String, Object?>>[
      <String, Object?>{'guid': 'art-$i', 'name': artist ?? '艺人$i'},
    ],
    'album': <String, Object?>{'guid': 'album-A', 'name': '专辑A'},
  });
}

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
    FnGenreService.fetchGenresOverride = null;
    FnGenreService.fetchGenreTracksOverride = null;
  });

  tearDown(() {
    FnGenreService.fetchGenresOverride = null;
    FnGenreService.fetchGenreTracksOverride = null;
  });

  Future<void> pumpList(
    WidgetTester tester, {
    List<FnGenre> genres = const <FnGenre>[],
  }) async {
    FnGenreService.fetchGenresOverride = () async => genres;
    await tester.pumpWidget(const MaterialApp(home: GenresPage()));
    await tester.pumpAndSettle();
  }

  Future<void> pumpDetail(
    WidgetTester tester, {
    List<FnTrack> tracks = const <FnTrack>[],
    int? trackCount,
  }) async {
    FnGenreService.fetchGenreTracksOverride = (String genreGuid) async => tracks;
    await tester.pumpWidget(
      MaterialApp(
        home: GenreDetailPage(
          genreGuid: 'gen-流行',
          genreName: '流行',
          trackCount: trackCount,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('风格列表渲染渐变卡片：名称 + 共 N 首', (WidgetTester tester) async {
    await pumpList(tester, genres: <FnGenre>[
      _genre('流行', trackCount: 5),
      _genre('民谣', trackCount: 2),
    ]);

    expect(find.text('流行'), findsOneWidget);
    expect(find.text('民谣'), findsOneWidget);
    expect(find.text('共 5 首'), findsOneWidget);
    expect(find.text('共 2 首'), findsOneWidget);
  });

  testWidgets('点风格卡片进入详情页并带入曲目数', (WidgetTester tester) async {
    FnGenreService.fetchGenreTracksOverride =
        (String genreGuid) async => <FnTrack>[_track(1)];
    await pumpList(tester, genres: <FnGenre>[
      _genre('流行', trackCount: 5),
    ]);

    await tester.tap(find.text('流行'));
    await tester.pumpAndSettle();

    expect(find.byType(GenreDetailPage), findsOneWidget);
    // 详情头部沿用列表带入的曲目数。
    expect(find.text('共 5 首'), findsOneWidget);
    expect(find.text('歌1'), findsOneWidget);
  });

  testWidgets('列表加载失败显示友好错误并可重试', (WidgetTester tester) async {
    int calls = 0;
    FnGenreService.fetchGenresOverride = () async {
      calls++;
      if (calls == 1) throw ApiException(100002, '');
      return <FnGenre>[_genre('流行', trackCount: 1)];
    };

    await tester.pumpWidget(const MaterialApp(home: GenresPage()));
    await tester.pumpAndSettle();

    expect(find.text('参数不完整或格式不正确'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('流行'), findsOneWidget);
  });

  testWidgets('风格详情头部渲染 Hero：名称 + 共 N 首 + 播放全部', (WidgetTester tester) async {
    await pumpDetail(tester, tracks: <FnTrack>[
      _track(1),
      _track(2),
    ], trackCount: 12);

    // AppBar 标题 + Hero 各有一处名称。
    expect(find.text('流行'), findsWidgets);
    // 优先列表带入的 trackCount（12）而非已加载曲目数。
    expect(find.text('共 12 首'), findsOneWidget);
    expect(find.text('播放全部'), findsOneWidget);
    expect(find.text('歌1'), findsOneWidget);
    expect(find.text('歌2'), findsOneWidget);
  });

  testWidgets('未传 trackCount 时曲目数回退已加载数量', (WidgetTester tester) async {
    await pumpDetail(tester, tracks: <FnTrack>[
      _track(1),
      _track(2),
    ]);

    expect(find.text('共 2 首'), findsOneWidget);
  });

  testWidgets('播放全部按钮按列表顺序播放', (WidgetTester tester) async {
    await pumpDetail(tester, tracks: <FnTrack>[
      _track(1),
      _track(2),
    ]);

    await tester.tap(find.text('播放全部'));
    await tester.pumpAndSettle();

    expect(fakeMain.playCalls, greaterThanOrEqualTo(1));
    expect(AppPlayerState.instance.queue.value.length, 2);
    expect(AppPlayerState.instance.currentIndex.value, 0);
    expect(AppPlayerState.instance.currentSong.value?.title, '歌1');
  });

  testWidgets('点按曲目以整表为队列播放', (WidgetTester tester) async {
    await pumpDetail(tester, tracks: <FnTrack>[
      _track(1),
      _track(2),
    ]);

    await tester.tap(find.text('歌2'));
    await tester.pumpAndSettle();

    expect(fakeMain.playCalls, greaterThanOrEqualTo(1));
    expect(AppPlayerState.instance.queue.value.length, 2);
    expect(AppPlayerState.instance.currentIndex.value, 1);
    expect(AppPlayerState.instance.currentSong.value?.title, '歌2');
  });

  testWidgets('排序面板：歌曲名称/歌手名称/时长 + 升降序', (WidgetTester tester) async {
    await pumpDetail(tester, tracks: <FnTrack>[
      _track(1, artist: '阿甲', duration: 300000), // 歌1 阿甲 5:00
      _track(2, artist: '郑乙', duration: 100000), // 歌2 郑乙 1:40
    ]);

    // 默认歌曲名称升序：歌1 在 歌2 上方。
    expect(
      tester.getTopLeft(find.text('歌1')).dy,
      lessThan(tester.getTopLeft(find.text('歌2')).dy),
    );

    // 打开排序面板，切降序 → 歌2 在上（面板保持打开，逐个 chip 操作）。
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('降序'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('歌2')).dy,
      lessThan(tester.getTopLeft(find.text('歌1')).dy),
    );

    // 切回升序 + 歌手名称：阿甲(阿) 在 郑乙(郑) 前。
    await tester.tap(find.text('升序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('歌手名称'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('歌1')).dy,
      lessThan(tester.getTopLeft(find.text('歌2')).dy),
    );

    // 再切歌曲时长（仍升序）：歌2(1:40) 在 歌1(5:00) 前。
    await tester.tap(find.text('歌曲时长'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('歌2')).dy,
      lessThan(tester.getTopLeft(find.text('歌1')).dy),
    );
  });

  testWidgets('服务端返回 100002 显示友好错误并可重试', (WidgetTester tester) async {
    int calls = 0;
    FnGenreService.fetchGenreTracksOverride = (String genreGuid) async {
      calls++;
      if (calls == 1) throw ApiException(100002, '');
      return <FnTrack>[_track(1)];
    };

    await tester.pumpWidget(
      const MaterialApp(
        home: GenreDetailPage(genreGuid: 'gen-x', genreName: '流行'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('参数不完整或格式不正确'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('歌1'), findsOneWidget);
  });

  testWidgets('空风格 guid 本地拦截并给出明确提示', (WidgetTester tester) async {
    FnGenreService.fetchGenreTracksOverride = null;
    await tester.pumpWidget(
      const MaterialApp(home: GenreDetailPage(genreGuid: '', genreName: '')),
    );
    await tester.pumpAndSettle();

    expect(find.text('风格标识缺失，请返回刷新后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('网络异常显示通用文案', (WidgetTester tester) async {
    FnGenreService.fetchGenreTracksOverride =
        (String genreGuid) async => throw Exception('boom');
    await tester.pumpWidget(
      const MaterialApp(home: GenreDetailPage(genreGuid: 'gen-x', genreName: 'x')),
    );
    await tester.pumpAndSettle();

    expect(find.text('加载失败，请检查网络后重试'), findsOneWidget);
    expect(find.text('Exception: boom'), findsOneWidget);
  });
}
