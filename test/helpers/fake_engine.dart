import 'package:fnmusic/app/services/player/player_engine.dart';
import 'package:fnmusic/app/services/player_service.dart';
import 'package:fnmusic/app/state/player_state.dart';
import 'package:fnmusic/app/state/song_state.dart';

/// 最小测试引擎：只记录 play 调用，不触碰真实音频插件。
class FakeEngine implements PlayerEngine {
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

/// 重置全局播放 UI 状态，供 widget 测试用例间隔离。
void resetPlayerState() {
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

/// 配置测试基线：内存 prefs、服务器地址、关闭缓存、替换引擎。
void setupPlayerForTest(FakeEngine fakeMain) {
  final FnPlayerService player = FnPlayerService.instance;
  resetPlayerState();
  player.resetForTest();
  player.overrideEnginesForTest(fakeMain, FakeEngine());
}
