import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/api_models.dart';
import 'package:fnmusic/app/services/feiniu/track_service.dart';
import 'package:fnmusic/app/services/player/player_engine.dart';
import 'package:fnmusic/app/services/player/stream_cache_service.dart';
import 'package:fnmusic/app/services/player_service.dart';
import 'package:fnmusic/app/state/player_state.dart';
import 'package:fnmusic/app/state/song_state.dart';
import 'package:fnmusic/pages/songs/songs_page.dart';

/// 最小测试引擎：只记录 play 调用，不触碰真实音频插件。
class _FakeEngine implements PlayerEngine {
  int playCalls = 0;

  @override
  EngineKind get kind => EngineKind.justAudio;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> loadQueue({
    required List<EngineItem> items,
    required int index,
    Duration? initialPosition,
    bool preload = false,
  }) async {}

  @override
  Future<void> play() async => playCalls += 1;

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> seekToNext() async {}

  @override
  Future<void> seekToPrevious() async {}

  @override
  Future<void> skipToIndex(int index) async {}

  @override
  Future<void> setLoopMode(EngineLoopMode mode) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> insertItem(int index, EngineItem item) async {}

  @override
  Future<void> insertItems(int index, List<EngineItem> items) async {}

  @override
  Future<void> moveItem(int from, int to) async {}

  @override
  Duration get position => Duration.zero;

  @override
  int? get currentIndex => null;

  @override
  int get sequenceLength => 0;

  @override
  bool get hasLoadedSource => false;

  @override
  bool get playing => false;

  @override
  EngineProcessingState get processingState => EngineProcessingState.idle;

  @override
  EngineLoopMode get loopMode => EngineLoopMode.none;

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<Duration?> get durationStream => const Stream<Duration?>.empty();

  @override
  Stream<Duration> get bufferedPositionStream =>
      const Stream<Duration>.empty();

  @override
  Stream<EnginePlaybackState> get playbackStateStream =>
      const Stream<EnginePlaybackState>.empty();

  @override
  Stream<EngineError> get errorStream => const Stream<EngineError>.empty();

  @override
  Stream<int?> get currentIndexStream => const Stream<int?>.empty();
}

FnTrack _track(int i) {
  return FnTrack.fromJson(<String, Object?>{
    'guid': 'guid-$i',
    'title': '歌曲$i',
    'duration': 210000,
    'artists': <Object?>[
      <String, Object?>{'guid': 'artist-$i', 'name': '歌手$i'},
    ],
    'album': <String, Object?>{'guid': 'album-$i', 'name': '专辑$i'},
  });
}

ApiPage<FnTrack> _page(List<FnTrack> tracks) {
  return ApiPage<FnTrack>(
    list: tracks,
    total: tracks.length,
    page: 1,
    pageSize: 100,
  );
}

void _resetPlayerState() {
  final AppPlayerState s = AppPlayerState.instance;
  s.currentSong.value = null;
  s.queue.value = <SongEntity>[];
  s.currentIndex.value = -1;
  s.duration.value = null;
  s.position.value = Duration.zero;
  s.bufferedPosition.value = Duration.zero;
  s.isPlaying.value = false;
  s.isLoading.value = false;
  s.playbackMode.value = PlaybackMode.sequential;
  s.speed.value = 1.0;
  s.sleepTimer.value = null;
  s.snapshot.value = PlayerSnapshot.initial();
}

void main() {
  late _FakeEngine fakeMain;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 让播放编排能构建出播放源（baseUrl 为空时 setQueue 会提前抛异常）。
    ApiClient.instance.setServerUrl('http://test');
    StreamCacheService.instance.enabled = false;
    fakeMain = _FakeEngine();
    final FnPlayerService player = FnPlayerService.instance;
    _resetPlayerState();
    player.resetForTest();
    player.overrideEnginesForTest(fakeMain, _FakeEngine());
    FnTrackService.fetchOverride = null;
  });

  tearDown(() {
    FnTrackService.fetchOverride = null;
  });

  testWidgets('全部歌曲渲染曲目列表', (WidgetTester tester) async {
    FnTrackService.fetchOverride =
        (int page) async => _page(<FnTrack>[_track(1), _track(2)]);

    await tester.pumpWidget(const MaterialApp(home: SongsPage()));
    await tester.pumpAndSettle();

    expect(find.text('歌曲1'), findsOneWidget);
    expect(find.text('歌手1'), findsOneWidget);
    expect(find.text('歌曲2'), findsOneWidget);
  });

  testWidgets('点按歌曲：以整表为队列从该曲开始播放', (WidgetTester tester) async {
    FnTrackService.fetchOverride =
        (int page) async => _page(<FnTrack>[_track(1), _track(2)]);

    await tester.pumpWidget(const MaterialApp(home: SongsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('歌曲2'));
    await tester.pumpAndSettle();

    // 引擎收到 play（setQueue 自动播放 + 页面显式 play，可能多次），
    // 队列以整表为范围、索引指向被点歌曲。
    expect(fakeMain.playCalls, greaterThanOrEqualTo(1));
    expect(AppPlayerState.instance.currentIndex.value, 1);
    expect(AppPlayerState.instance.queue.value.length, 2);
    expect(AppPlayerState.instance.currentSong.value?.title, '歌曲2');
  });

  testWidgets('点按歌曲：引擎收到 play 且当前歌曲正确', (WidgetTester tester) async {
    FnTrackService.fetchOverride =
        (int page) async => _page(<FnTrack>[_track(1), _track(2)]);

    await tester.pumpWidget(const MaterialApp(home: SongsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('歌曲1'));
    await tester.pumpAndSettle();

    expect(fakeMain.playCalls, greaterThanOrEqualTo(1));
    expect(AppPlayerState.instance.currentSong.value?.title, '歌曲1');
  });
}
