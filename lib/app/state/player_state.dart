import 'package:flutter/foundation.dart';
import 'package:signals/signals.dart';

import '../services/player/player_engine.dart';
import 'song_state.dart';

/// 播放模式。
enum PlaybackMode {
  /// 顺序播放（默认）。
  sequential,

  /// 列表循环。
  loop,

  /// 单曲循环。
  single,

  /// 随机播放（Fisher-Yates 洗牌，可恢复原序）。
  shuffle,
}

/// 播放器状态快照（UI 用 [ValueListenableBuilder] / signals 订阅）。
class PlayerSnapshot {
  final SongEntity? song;
  final List<SongEntity> queue;
  final int index;
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration? duration;
  final Duration bufferedPosition;

  const PlayerSnapshot({
    required this.song,
    required this.queue,
    required this.index,
    required this.isPlaying,
    this.isLoading = false,
    required this.position,
    required this.duration,
    required this.bufferedPosition,
  });

  factory PlayerSnapshot.initial() {
    return const PlayerSnapshot(
      song: null,
      queue: <SongEntity>[],
      index: -1,
      isPlaying: false,
      isLoading: false,
      position: Duration.zero,
      duration: null,
      bufferedPosition: Duration.zero,
    );
  }

  PlayerSnapshot copyWith({
    SongEntity? song,
    bool clearSong = false,
    List<SongEntity>? queue,
    int? index,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    bool clearDuration = false,
    Duration? bufferedPosition,
  }) {
    return PlayerSnapshot(
      song: clearSong ? null : (song ?? this.song),
      queue: queue ?? this.queue,
      index: index ?? this.index,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      position: position ?? this.position,
      duration: clearDuration ? null : (duration ?? this.duration),
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
    );
  }
}

/// [PlaybackMode] 的循环顺序（供"下一个模式"按钮）。
extension PlaybackModeCycle on PlaybackMode {
  PlaybackMode get next => switch (this) {
        PlaybackMode.sequential => PlaybackMode.loop,
        PlaybackMode.loop => PlaybackMode.single,
        PlaybackMode.single => PlaybackMode.shuffle,
        PlaybackMode.shuffle => PlaybackMode.sequential,
      };
}

/// 播放器全局状态单例。
///
/// 粗粒度 UI 用 [ValueNotifier] + [ValueListenableBuilder]；细粒度逻辑用
/// signals。二者互相同步（[AppPlayerState] 监听 notifier 写入 signal）。
class AppPlayerState {
  static final AppPlayerState instance = AppPlayerState._internal();

  AppPlayerState._internal() {
    _initListeners();
  }

  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration?> duration = ValueNotifier(null);
  final ValueNotifier<Duration> bufferedPosition = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);
  final ValueNotifier<bool> isLoading = ValueNotifier(false);
  final ValueNotifier<List<SongEntity>> queue = ValueNotifier(const <SongEntity>[]);
  final ValueNotifier<int> currentIndex = ValueNotifier(-1);
  final ValueNotifier<SongEntity?> currentSong = ValueNotifier(null);
  final ValueNotifier<PlayerSnapshot> snapshot =
      ValueNotifier<PlayerSnapshot>(PlayerSnapshot.initial());
  final ValueNotifier<PlaybackMode> playbackMode =
      ValueNotifier<PlaybackMode>(PlaybackMode.sequential);

  /// 当前歌曲使用的解码引擎（just_audio / media_kit）。
  /// UI 在"更多面板"展示当前解码方式。
  final ValueNotifier<EngineKind> decoderEngine =
      ValueNotifier<EngineKind>(EngineKind.justAudio);

  /// 当前是否走服务端 HLS 转码播放（引擎兜底链最后一环）。
  final ValueNotifier<bool> transcoding = ValueNotifier<bool>(false);

  /// 睡眠定时器剩余时间；null 表示未开启。
  final ValueNotifier<Duration?> sleepTimer = ValueNotifier<Duration?>(null);

  /// 播放倍速。系统媒体会话（通知栏/Android Auto）按 speed 外推剩余时间，
  /// 倍速播放时须同步真实倍率，否则进度条以 1× 估算并随倍速漂移。
  final ValueNotifier<double> speed = ValueNotifier<double>(1.0);

  // Signals（响应式细粒度状态）。
  final Signal<Duration> positionSignal = signal(Duration.zero);
  final Signal<Duration?> durationSignal = signal<Duration?>(null);
  final Signal<Duration> bufferedPositionSignal = signal(Duration.zero);
  final Signal<bool> isPlayingSignal = signal(false);
  final Signal<bool> isLoadingSignal = signal(false);
  final Signal<List<SongEntity>> queueSignal = signal<List<SongEntity>>(<SongEntity>[]);
  final Signal<int> currentIndexSignal = signal(-1);
  final Signal<SongEntity?> currentSongSignal = signal<SongEntity?>(null);
  final Signal<PlayerSnapshot> snapshotSignal =
      signal(PlayerSnapshot.initial());
  final Signal<PlaybackMode> playbackModeSignal =
      signal(PlaybackMode.sequential);
  final Signal<EngineKind> decoderEngineSignal =
      signal(EngineKind.justAudio);
  final Signal<bool> transcodingSignal = signal(false);
  final Signal<Duration?> sleepTimerSignal = signal<Duration?>(null);
  final Signal<double> speedSignal = signal(1.0);

  void _initListeners() {
    position.addListener(() => positionSignal.value = position.value);
    duration.addListener(() => durationSignal.value = duration.value);
    bufferedPosition.addListener(
        () => bufferedPositionSignal.value = bufferedPosition.value);
    isPlaying.addListener(() => isPlayingSignal.value = isPlaying.value);
    isLoading.addListener(() => isLoadingSignal.value = isLoading.value);
    queue.addListener(() => queueSignal.value = queue.value);
    currentIndex.addListener(() => currentIndexSignal.value = currentIndex.value);
    currentSong.addListener(() => currentSongSignal.value = currentSong.value);
    snapshot.addListener(() => snapshotSignal.value = snapshot.value);
    playbackMode.addListener(() => playbackModeSignal.value = playbackMode.value);
    decoderEngine.addListener(() => decoderEngineSignal.value = decoderEngine.value);
    transcoding.addListener(() => transcodingSignal.value = transcoding.value);
    sleepTimer.addListener(() => sleepTimerSignal.value = sleepTimer.value);
    speed.addListener(() => speedSignal.value = speed.value);
  }

  void dispose() {
    position.dispose();
    duration.dispose();
    bufferedPosition.dispose();
    isPlaying.dispose();
    isLoading.dispose();
    queue.dispose();
    currentIndex.dispose();
    currentSong.dispose();
    snapshot.dispose();
    playbackMode.dispose();
    decoderEngine.dispose();
    transcoding.dispose();
    sleepTimer.dispose();
    speed.dispose();
  }
}
