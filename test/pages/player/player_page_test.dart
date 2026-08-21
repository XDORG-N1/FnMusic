import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnmusic/app/services/player/player_engine.dart';
import 'package:fnmusic/app/services/player_service.dart';
import 'package:fnmusic/app/state/player_state.dart';
import 'package:fnmusic/app/state/player_style_settings.dart';
import 'package:fnmusic/app/state/song_state.dart';
import 'package:fnmusic/pages/player/player_page.dart';

/// 测试引擎：记录传输调用，不触碰真实音频插件。
class FakePlayerEngine implements PlayerEngine {
  final StreamController<Duration> _positionCtl =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationCtl =
      StreamController<Duration?>.broadcast();
  final StreamController<Duration> _bufferedCtl =
      StreamController<Duration>.broadcast();
  final StreamController<EnginePlaybackState> _stateCtl =
      StreamController<EnginePlaybackState>.broadcast();
  final StreamController<EngineError> _errorCtl =
      StreamController<EngineError>.broadcast();
  final StreamController<int?> _indexCtl =
      StreamController<int?>.broadcast();

  int playCalls = 0;
  int pauseCalls = 0;
  double lastSpeed = 1.0;
  Duration? lastSeek;

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
  Future<void> play() async {
    playCalls += 1;
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {
    lastSeek = position;
  }

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
  Future<void> setSpeed(double speed) async {
    lastSpeed = speed;
  }

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
  Stream<Duration> get positionStream => _positionCtl.stream;

  @override
  Stream<Duration?> get durationStream => _durationCtl.stream;

  @override
  Stream<Duration> get bufferedPositionStream => _bufferedCtl.stream;

  @override
  Stream<EnginePlaybackState> get playbackStateStream => _stateCtl.stream;

  @override
  Stream<EngineError> get errorStream => _errorCtl.stream;

  @override
  Stream<int?> get currentIndexStream => _indexCtl.stream;
}

SongEntity _song(int i) {
  return SongEntity(
    guid: 'guid-$i',
    title: '测试歌曲$i',
    artistDisplay: '测试歌手$i',
    albumDisplay: '测试专辑$i',
    durationMs: 210000,
    format: 'mp3',
    codec: 'mp3',
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

/// 加载一首歌 + 两首歌的队列，处于未播放状态。
void _loadPlayingState() {
  final AppPlayerState s = AppPlayerState.instance;
  final List<SongEntity> songs = <SongEntity>[_song(1), _song(2)];
  // 同时填充服务内部逻辑队列（否则 play() 会因空队列提前返回）。
  FnPlayerService.instance.setQueueForTest(songs, index: 0);
  s.currentSong.value = songs.first;
  s.queue.value = songs;
  s.currentIndex.value = 0;
  s.duration.value = const Duration(minutes: 3, seconds: 30);
  s.position.value = const Duration(seconds: 30);
  s.bufferedPosition.value = const Duration(seconds: 45);
  s.isPlaying.value = false;
  s.isLoading.value = false;
  s.playbackMode.value = PlaybackMode.sequential;
  s.speed.value = 1.0;
}

Future<void> _pumpPlayer(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: PlayerPage()));
  await tester.pumpAndSettle();
}

void main() {
  late FakePlayerEngine fakeMain;

  setUp(() {
    // 关闭动态渐变背景：其 `..repeat()` 无限动画会让 pumpAndSettle 超时。
    // 用 mock 预置值，保证 PlayerBackgroundSettings.ensureLoaded 读到 false。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'dynamic_gradient_enabled': false,
    });
    PlayerStyleSettings.stylePreset.value = PlayerStylePreset.classic;

    fakeMain = FakePlayerEngine();
    final FakePlayerEngine fakeFallback = FakePlayerEngine();
    final FnPlayerService player = FnPlayerService.instance;
    _resetPlayerState();
    player.resetForTest();
    player.overrideEnginesForTest(fakeMain, fakeFallback);
  });

  testWidgets('播放器页渲染当前歌曲信息', (WidgetTester tester) async {
    _loadPlayingState();
    await _pumpPlayer(tester);

    expect(find.text('测试歌曲1'), findsOneWidget);
    expect(find.text('测试歌手1'), findsOneWidget);
    // 未播放时显示播放按钮。
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
  });

  testWidgets('播放/暂停按钮切换播放状态并驱动引擎', (WidgetTester tester) async {
    _loadPlayingState();
    await _pumpPlayer(tester);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(AppPlayerState.instance.isPlaying.value, isTrue);
    expect(fakeMain.playCalls, 1);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(AppPlayerState.instance.isPlaying.value, isFalse);
    expect(fakeMain.pauseCalls, 1);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('进度条拖动触发 seek 并更新进度', (WidgetTester tester) async {
    _loadPlayingState();
    await _pumpPlayer(tester);

    final Finder slider = find.byType(Slider);
    expect(slider, findsOneWidget);

    await tester.drag(slider, const Offset(80, 0));
    await tester.pump();

    expect(fakeMain.lastSeek, isNotNull);
    expect(
      AppPlayerState.instance.position.value,
      greaterThan(Duration.zero),
    );
  });

  testWidgets('播放模式按钮循环切换模式', (WidgetTester tester) async {
    _loadPlayingState();
    await _pumpPlayer(tester);

    // 顺序 → 列表循环。
    expect(AppPlayerState.instance.playbackMode.value, PlaybackMode.sequential);
    await tester.tap(find.byIcon(Icons.playlist_play_rounded));
    await tester.pump();
    expect(AppPlayerState.instance.playbackMode.value, PlaybackMode.loop);
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);

    // 列表循环 → 单曲循环。
    await tester.tap(find.byIcon(Icons.repeat_rounded));
    await tester.pump();
    expect(AppPlayerState.instance.playbackMode.value, PlaybackMode.single);
    expect(find.byIcon(Icons.repeat_one_rounded), findsOneWidget);
  });

  testWidgets('倍速菜单选择倍速', (WidgetTester tester) async {
    _loadPlayingState();
    await _pumpPlayer(tester);

    // 初始显示 1×。
    expect(find.text('1×'), findsOneWidget);

    // 打开倍速菜单。
    await tester.tap(find.text('1×'));
    await tester.pumpAndSettle();
    expect(find.text('1.5×'), findsOneWidget);

    // 选择 1.5×：状态更新 + 引擎 setSpeed + 按钮文本更新。
    await tester.tap(find.text('1.5×'));
    await tester.pumpAndSettle();

    expect(AppPlayerState.instance.speed.value, 1.5);
    expect(fakeMain.lastSpeed, 1.5);
    expect(find.text('1.5×'), findsOneWidget);
  });

  testWidgets('队列按钮打开播放队列面板', (WidgetTester tester) async {
    _loadPlayingState();
    await _pumpPlayer(tester);

    await tester.tap(find.byIcon(Icons.format_list_bulleted));
    await tester.pumpAndSettle();

    // 队列面板展示全部歌曲（第 2 首只出现在面板内，可作判别）。
    expect(find.text('测试歌曲2'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsOneWidget);
  });

  testWidgets('睡眠定时按钮打开定时面板', (WidgetTester tester) async {
    _loadPlayingState();
    await _pumpPlayer(tester);

    await tester.tap(find.byIcon(Icons.alarm));
    await tester.pumpAndSettle();

    expect(find.text('开始定时'), findsOneWidget);
    expect(find.byType(Slider), findsWidgets);
  });
}
