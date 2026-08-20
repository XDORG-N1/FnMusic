import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:shared_preferences/shared_preferences.dart';

import 'feiniu/api_client.dart';
import 'feiniu/api_models.dart';
import 'feiniu/cue_service.dart';
import 'feiniu/transcode_service.dart';
import 'player/just_audio_engine.dart';
import 'player/media_kit_engine.dart';
import 'player/playback_queue.dart';
import 'player/playback_router.dart';
import 'player/player_engine.dart';
import 'player/stream_cache_service.dart';
import 'listening_recorder_service.dart';
import '../state/player_state.dart';
import '../state/song_state.dart';

/// 播放编排核心（单例）。
///
/// 持有唯一逻辑队列 [PlaybackQueue]，把队列按引擎路由后交给对应引擎播放；
/// 引擎切换只在歌曲边界发生。
///
/// - 队列语义：setQueue / playSong / insertNext / addToQueue / removeAt /
///   move / clear / replaceQueue / next / previous
/// - 播放模式：[PlaybackMode]（顺序 / 列表循环 / 单曲循环 / 随机），随机用
///   确定性种子 Fisher-Yates 洗牌（[PlaybackQueue]），种子持久化可复现。
/// - 引擎管理：按格式/codec 路由（[routeForFormat]），错误时回退另一引擎。
/// - 流缓存：整首下载到本地 [StreamCacheService]，二次播放零流量。
/// - 音频焦点：[audio_session] 中断/duck、becoming-noisy 自动暂停。
/// - 状态持久化：队列 / 索引 / 模式 / 种子 / 位置 / 是否播放 → SharedPreferences，
///   启动时 [restore] 续播。
class FnPlayerService {
  FnPlayerService._();

  static final FnPlayerService instance = FnPlayerService._();

  // ---------- 引擎 ----------

  final JustAudioEngine _justAudio = JustAudioEngine();
  final MediaKitEngine _mediaKit = MediaKitEngine();
  late PlayerEngine _active = _justAudio; // init() 后通常为 _justAudio

  // ---------- 逻辑状态 ----------

  /// 唯一逻辑队列（模式 / 洗牌 / 导航单一真源，见 [PlaybackQueue]）。
  PlaybackQueue _q = PlaybackQueue();
  bool _playing = false;
  bool _interrupted = false;

  /// 当前歌曲是否已尝试过另一引擎回退（避免同一首歌无限切引擎）。
  bool _fallbackTried = false;

  /// 服务端转码会话的曲目 guid（非空表示当前正走转码播放）。
  String? _transcodeGuid;

  /// 睡眠定时器。
  Timer? _sleepTimer;
  DateTime? _sleepEndsAt;

  /// 漫游随机播放。
  String? _roamDeviceId;
  bool _roaming = false;

  // 持久化键。
  static const String _prefQueue = 'playback_state.queueJson';
  static const String _prefPositionMs = 'playback_state.positionMs';
  static const String _prefWasPlaying = 'playback_state.wasPlaying';

  AppPlayerState get _state => AppPlayerState.instance;

  // ---------- 对外 API ----------

  /// 初始化：引擎、焦点、订阅、恢复上次播放状态。幂等。
  Future<void> init() async {
    // media_kit 全局初始化（原生库加载）。幂等。
    mk.MediaKit.ensureInitialized();
    await _justAudio.init();
    _active = _justAudio;
    // 让队列模式与 UI 默认一致（PlaybackQueue 构造默认 loop 是测试契约）。
    _q.mode = _state.playbackMode.value;
    _wireEngine(_justAudio);
    _wireEngine(_mediaKit);
    await _activateAudioSession();
    await restore();
  }

  /// 设置队列并播放 [index] 对应的歌曲。
  Future<void> setQueue(List<SongEntity> songs, {int index = 0}) async {
    if (songs.isEmpty) {
      await clear();
      return;
    }
    _q.replace(songs, startIndex: index);
    await _activateIndex(_q.currentIndex, autoplay: true);
    _persist();
  }

  /// 立即播放单曲（已在队列中则定位过去，否则新建单曲队列）。
  Future<void> playSong(SongEntity song) async {
    final int idx = _q.items.indexWhere((SongEntity s) => s.guid == song.guid);
    if (idx >= 0) {
      await _activateIndex(idx, autoplay: true);
    } else {
      await setQueue(<SongEntity>[song]);
    }
    _persist();
  }

  /// 在当前队列后追加（不改变当前播放位置）。
  void addToQueue(List<SongEntity> songs) {
    if (songs.isEmpty) return;
    _q.items.addAll(songs);
    _q.rebuildShuffleOrder();
    _persist();
  }

  /// 插入到下一首位置（当前索引后）。
  void insertNext(List<SongEntity> songs) {
    if (songs.isEmpty) return;
    final int at = (_q.currentIndex + 1).clamp(0, _q.items.length);
    _q.items.insertAll(at, songs);
    _q.rebuildShuffleOrder();
    _persist();
  }

  /// 移除 [index] 处的歌曲；若移除的是当前曲，跳到相邻曲。
  void removeAt(int index) {
    if (index < 0 || index >= _q.items.length) return;
    final bool isCurrent = index == _q.currentIndex;
    _q.items.removeAt(index);
    if (_q.items.isEmpty) {
      _resetPlayback();
      _persist();
      return;
    }
    _q.rebuildShuffleOrder();
    if (isCurrent) {
      // 移除当前曲后，index 处是原本的下一首；clamp 防末位被移除后的越界。
      final int nextIndex = _q.currentIndex.clamp(0, _q.items.length - 1);
      _activateIndex(nextIndex, autoplay: _playing);
    } else {
      if (index < _q.currentIndex) _q.currentIndex--;
      _emitSnapshot();
    }
    _persist();
  }

  /// 移动队列条目（from → to）。
  void move(int from, int to) {
    if (from < 0 || from >= _q.items.length) return;
    if (to < 0 || to >= _q.items.length) return;
    final SongEntity item = _q.items.removeAt(from);
    _q.items.insert(to, item);
    _q.currentIndex = _q.currentIndex == from ? to : _q.currentIndex;
    _q.rebuildShuffleOrder();
    _emitSnapshot();
    _persist();
  }

  /// 清空队列与播放。
  Future<void> clear() async {
    await _pauseEngine();
    await _stopEngine();
    stopRoam();
    cancelSleepTimer();
    await _stopTranscodeIfAny();
    _q = PlaybackQueue()..mode = _state.playbackMode.value;
    _playing = false;
    _emitSnapshot();
    _persist();
  }

  /// 替换队列（尽量保留当前播放曲目位置）。
  void replaceQueue(List<SongEntity> songs) {
    final String? currentGuid = _q.current?.guid;
    _q.replace(songs);
    _q.currentIndex = currentGuid == null
        ? -1
        : _q.items.indexWhere((SongEntity s) => s.guid == currentGuid);
    if (_q.currentIndex < 0 && _q.items.isNotEmpty) _q.currentIndex = 0;
    _q.rebuildShuffleOrder();
    _emitSnapshot();
    _persist();
  }

  // ---------- 传输控制 ----------

  Future<void> play() async {
    if (_q.currentIndex < 0 || _q.items.isEmpty) return;
    _playing = true;
    _interrupted = false;
    await _active.play();
    AppPlayerState.instance.isPlaying.value = true;
    _persist();
  }

  Future<void> pause() async {
    _playing = false;
    await _active.pause();
    AppPlayerState.instance.isPlaying.value = false;
    _persist();
  }

  Future<void> togglePlay() => _playing ? pause() : play();

  /// 播放 / 暂停切换（UI 语义别名）。
  Future<void> togglePlayPause() => togglePlay();

  Future<void> seek(Duration position) async {
    await _active.seek(position);
    AppPlayerState.instance.position.value = position;
  }

  Future<void> setSpeed(double speed) async {
    await _active.setSpeed(speed);
    AppPlayerState.instance.speed.value = speed;
    _persist();
  }

  Future<void> setVolume(double volume) => _active.setVolume(volume);

  /// 下一首：漫游中走服务端漫游续播；否则按播放模式决定目标索引。
  Future<void> next() {
    if (_roaming) return _roamNext();
    return _advance(forward: true);
  }

  /// 上一首：位置超过 3 秒则回到曲首，否则上一首。
  Future<void> previous() async {
    if (_active.position > const Duration(seconds: 3)) {
      await _active.seek(Duration.zero);
      return;
    }
    await _advance(forward: false);
  }

  /// 跳到队列 [index]。
  Future<void> skipTo(int index) async {
    if (index < 0 || index >= _q.items.length) return;
    await _activateIndex(index, autoplay: _playing);
    _persist();
  }

  // ---------- 睡眠定时器 ----------

  /// 启动睡眠定时器：倒计时结束自动暂停播放。duration <= 0 视为取消。
  void startSleepTimer(Duration duration) {
    cancelSleepTimer();
    if (duration <= Duration.zero) return;
    _sleepEndsAt = DateTime.now().add(duration);
    _state.sleepTimer.value = duration;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickSleepTimer());
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepEndsAt = null;
    _state.sleepTimer.value = null;
  }

  /// 睡眠定时剩余时间；null 表示未开启。
  Duration? get remainingSleepTime {
    final DateTime? end = _sleepEndsAt;
    if (end == null) return null;
    final Duration remaining = end.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void _tickSleepTimer() {
    final Duration? remaining = remainingSleepTime;
    if (remaining == null) {
      cancelSleepTimer();
      return;
    }
    if (remaining <= Duration.zero) {
      cancelSleepTimer();
      pause();
      return;
    }
    _state.sleepTimer.value = remaining;
  }

  // ---------- 漫游随机播放 ----------

  /// 漫游随机播放：服务端随机推流，播完自动续下一首。
  Future<void> startRoam() async {
    final String deviceId = _roamDeviceId ??= _newRoamDeviceId();
    final FnTrack track = await ApiClient.instance.roamStart(deviceId);
    _roaming = true;
    await setQueue(<SongEntity>[SongEntity.fromTrack(track)]);
  }

  void stopRoam() => _roaming = false;

  bool get isRoaming => _roaming;

  String _newRoamDeviceId() {
    final math.Random rng = math.Random();
    return 'fnmusic_${rng.nextInt(1 << 31).toRadixString(16)}';
  }

  /// 漫游续播：服务端再随机给一首并替换队列。
  Future<void> _roamNext() async {
    final String? deviceId = _roamDeviceId;
    if (deviceId == null) return;
    try {
      final FnTrack track = await ApiClient.instance.roamNext(deviceId);
      _q.items
        ..clear()
        ..add(SongEntity.fromTrack(track));
      _q.currentIndex = 0;
      _q.rebuildShuffleOrder();
      await _activateIndex(0, autoplay: true);
    } catch (_) {
      _roaming = false;
    }
  }

  /// 循环切换播放模式：顺序 → 列表循环 → 单曲循环 → 随机 → 顺序。
  void cyclePlayMode() => setPlayMode(_state.playbackMode.value.next);

  void setPlayMode(PlaybackMode mode) {
    if (_q.mode == mode) return;
    _q.mode = mode;
    if (mode == PlaybackMode.shuffle) {
      // 切到随机时生成新种子，顺序确定且可持久化复现。
      _q.shuffleSeed = PlaybackQueue.newSeed();
    }
    _q.rebuildShuffleOrder();
    _state.playbackMode.value = mode;
    _applyEngineLoopMode();
    _persist();
  }

  // ---------- 查询 ----------

  int get queueLength => _q.items.length;
  int? get currentIndex => _q.currentIndex;
  List<SongEntity> get queue => List<SongEntity>.unmodifiable(_q.items);
  SongEntity? get currentSong => _q.current;
  bool get isPlaying => _playing;
  Duration get position => _active.position;

  // ---------- 恢复 ----------

  /// 从 SharedPreferences 恢复上次播放状态并续播。
  @visibleForTesting
  Future<void> restore() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? rawQueue = prefs.getString(_prefQueue);
    if (rawQueue == null || rawQueue.isEmpty) return;

    final PlaybackQueue? restored = _decodeQueue(rawQueue);
    if (restored == null || restored.items.isEmpty) return;

    _q = restored;
    _state.playbackMode.value = restored.mode;
    final int positionMs = prefs.getInt(_prefPositionMs) ?? 0;
    final bool wasPlaying = prefs.getBool(_prefWasPlaying) ?? false;

    await _activateIndex(
      _q.currentIndex,
      initialPosition: Duration(milliseconds: positionMs),
    );
    if (wasPlaying) {
      _playing = true;
      await _active.play();
      AppPlayerState.instance.isPlaying.value = true;
    }
  }

  /// 主动清除持久化的播放状态（退出登录等场景调用）。
  Future<void> clearPersistedState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefQueue);
    await prefs.remove(_prefPositionMs);
    await prefs.remove(_prefWasPlaying);
  }

  // ---------- 内部 ----------

  Future<void> _activateIndex(
    int index, {
    Duration? initialPosition,
    bool autoplay = false,
  }) async {
    if (index < 0 || index >= _q.items.length) return;
    _q.currentIndex = index;
    // 新歌曲：重置引擎回退标记，退出旧的转码会话。
    _fallbackTried = false;
    await _stopTranscodeIfAny();

    final SongEntity song = _q.items[index];
    final EngineKind kind = await routeForSong(song);

    PlayerEngine engine;
    EngineItem item;
    if (kind == EngineKind.mediaKit) {
      engine = _mediaKit;
      item = MediaKitItem(await _buildMediaKitMedia(song));
    } else {
      engine = _justAudio;
      item = JustAudioItem(await _buildAudioSource(song));
    }

    final bool sameEngine = identical(engine, _active);
    if (!sameEngine) {
      await _pauseEngine();
      _active = engine;
    }

    await engine.loadQueue(
      items: <EngineItem>[item],
      index: 0,
      initialPosition: initialPosition,
    );
    AppPlayerState.instance.decoderEngine.value = kind;

    if (autoplay) {
      _playing = true;
      await engine.play();
    }

    // CUE 整轨：seek 到物理文件内偏移（仅 just_audio 需要；media_kit 用
    // Media.start/end 已处理）。
    if (kind == EngineKind.justAudio && song.isCue) {
      final int? cueOffset = song.cueOffsetMs ??
          await FnCueService.instance.offsetMsFor(song);
      if (cueOffset != null && cueOffset > 0) {
        await engine.seek(Duration(milliseconds: cueOffset));
      }
    }

    // 后台预缓存（CUE 整轨跳过：各曲共享同一物理文件，整轨缓存无意义）。
    if (!song.isCue) {
      unawaited(StreamCacheService.instance.cacheSong(song));
    }

    _emitSnapshot();
  }

  /// 构造 just_audio 播放源：命中流缓存 → 本地文件，否则在线流 + 鉴权头。
  Future<AudioSource> _buildAudioSource(SongEntity song) async {
    final PlayerSource? src = await StreamCacheService.instance.sourceFor(song);
    if (src == null) throw StateError('未配置服务器地址，无法播放');
    return AudioSource.uri(Uri.parse(src.uri), headers: src.headers);
  }

  /// 构造 media_kit 播放源（CUE 整轨用 Media.start/end 定位）。
  Future<mk.Media> _buildMediaKitMedia(SongEntity song) async {
    final PlayerSource? src = await StreamCacheService.instance.sourceFor(song);
    if (src == null) throw StateError('未配置服务器地址，无法播放');
    final int? cueOffset = song.cueOffsetMs;
    if (song.isCue && cueOffset != null) {
      return mk.Media(
        src.uri,
        start: Duration(milliseconds: cueOffset),
        end: Duration(milliseconds: cueOffset + (song.durationMs ?? 0)),
        httpHeaders: src.headers,
      );
    }
    return mk.Media(src.uri, httpHeaders: src.headers);
  }

  Future<void> _advance({required bool forward}) async {
    if (_q.items.isEmpty) return;
    int? target = forward ? _q.nextIndex() : _q.previousIndex();
    if (target == null) {
      if (forward && _q.mode == PlaybackMode.shuffle) {
        // 随机顺序耗尽：换新种子重新洗牌并继续。
        target = _q.reshuffleAndContinue();
        if (target == null) return;
      } else {
        // 顺序到队尾 / 队首：停止。
        _playing = false;
        AppPlayerState.instance.isPlaying.value = false;
        await _pauseEngine();
        _emitSnapshot();
        _persist();
        return;
      }
    }
    await _activateIndex(target, autoplay: true);
    _persist();
  }

  /// 非随机模式的推进逻辑（纯函数，可单测）。返回目标索引；-1 表示队尾停止。
  static int advanceSequentialIndex(
    int current,
    int length,
    PlaybackMode mode,
    bool forward,
  ) {
    if (length <= 0 || current < 0 || current >= length) return current;
    if (mode == PlaybackMode.single) return current;
    final int step = forward ? 1 : -1;
    if (mode == PlaybackMode.loop) {
      return (current + step + length) % length;
    }
    final int n = current + step;
    if (n < 0 || n >= length) return -1;
    return n;
  }

  void _applyEngineLoopMode() {
    final EngineLoopMode loop = _state.playbackMode.value == PlaybackMode.single
        ? EngineLoopMode.single
        : EngineLoopMode.none;
    _justAudio.setLoopMode(loop);
    _mediaKit.setLoopMode(loop);
  }

  void _wireEngine(PlayerEngine engine) {
    engine.positionStream.listen((Duration position) {
      if (!identical(engine, _active)) return;
      AppPlayerState.instance.position.value = position;
      _emitSnapshot();
    });
    engine.durationStream.listen((Duration? d) {
      if (!identical(engine, _active)) return;
      AppPlayerState.instance.duration.value = d;
      _emitSnapshot();
    });
    engine.playbackStateStream.listen((EnginePlaybackState s) {
      if (!identical(engine, _active)) return;
      AppPlayerState.instance.isLoading.value =
          s.processingState == EngineProcessingState.loading ||
              s.processingState == EngineProcessingState.buffering;
      if (s.processingState == EngineProcessingState.completed) {
        _onCompleted();
      }
    });
    engine.errorStream.listen(_onEngineError);
  }

  Future<void> _onCompleted() async {
    // 自然播完：给听歌记录器标记当前会话完成。
    ListeningRecorderService.instance.markCompleted();
    if (_playing) {
      if (_roaming) {
        await _roamNext();
      } else {
        await next();
      }
    } else {
      _emitSnapshot();
    }
  }

  Future<void> _onEngineError(EngineError err) async {
    if (kDebugMode) {
      debugPrint('[FnPlayerService] engine error: ${err.message}');
    }
    final SongEntity? song = currentSong;
    if (song == null) return;
    if (_fallbackTried) {
      // 已切到另一引擎仍失败 → 服务端 HLS 转码（回退链最后一环）。
      await _tryTranscode(song);
      return;
    }
    _fallbackTried = true;
    final EngineKind fallback = _active.kind == EngineKind.justAudio
        ? EngineKind.mediaKit
        : EngineKind.justAudio;
    await _fallbackTo(fallback);
  }

  /// 服务端转码兜底：请求 NAS 转码为 HLS，用 just_audio（ExoPlayer）播放。
  Future<void> _tryTranscode(SongEntity song) async {
    final String? hls = await FnTranscodeService.instance.requestTranscode(song);
    if (hls == null) {
      if (kDebugMode) {
        debugPrint('[FnPlayerService] 转码失败，放弃当前歌曲');
      }
      _emitSnapshot();
      return;
    }
    await _pauseEngine();
    _active = _justAudio;
    _transcodeGuid = song.guid;
    _state.transcoding.value = true;
    await _justAudio.loadQueue(
      items: <EngineItem>[
        JustAudioItem(
          AudioSource.uri(
            Uri.parse(hls),
            headers: ApiClient.instance.authHeaders(),
          ),
        ),
      ],
      index: 0,
    );
    _state.decoderEngine.value = EngineKind.justAudio;
    if (_playing) {
      await _active.play();
    }
    _emitSnapshot();
  }

  /// 停止当前服务端转码会话（切歌/停止时调用，幂等）。
  Future<void> _stopTranscodeIfAny() async {
    final String? guid = _transcodeGuid;
    if (guid == null) return;
    _transcodeGuid = null;
    _state.transcoding.value = false;
    await FnTranscodeService.instance.quitTranscode(guid);
  }

  Future<void> _fallbackTo(EngineKind kind) async {
    if (_q.currentIndex < 0 || _q.currentIndex >= _q.items.length) return;
    final SongEntity song = _q.items[_q.currentIndex];
    await _pauseEngine();
    if (kind == EngineKind.mediaKit) {
      _active = _mediaKit;
      await _mediaKit.loadQueue(
        items: <EngineItem>[MediaKitItem(await _buildMediaKitMedia(song))],
        index: 0,
      );
    } else {
      _active = _justAudio;
      await _justAudio.loadQueue(
        items: <EngineItem>[JustAudioItem(await _buildAudioSource(song))],
        index: 0,
      );
    }
    AppPlayerState.instance.decoderEngine.value = kind;
    if (_playing) {
      await _active.play();
    }
    _emitSnapshot();
  }

  Future<void> _pauseEngine() async {
    try {
      await _active.pause();
    } catch (_) {}
  }

  Future<void> _stopEngine() async {
    try {
      await _active.stop();
    } catch (_) {}
  }

  Future<void> _activateAudioSession() async {
    final AudioSession session = await AudioSession.instance;
    const AudioSessionConfiguration config = AudioSessionConfiguration.music();
    await session.configure(config);
    session.interruptionEventStream.listen((AudioInterruptionEvent event) {
      if (event.begin) {
        if (event.type == AudioInterruptionType.duck) {
          _active.setVolume(0.3);
        } else {
          _interrupted = _playing;
          pause();
        }
      } else {
        _active.setVolume(1.0);
        if (_interrupted) {
          _interrupted = false;
          play();
        }
      }
    });
    session.becomingNoisyEventStream.listen((_) {
      if (_playing) pause();
    });
  }

  // ---------- 持久化 ----------

  void _persist() {
    if (_q.items.isEmpty) {
      clearPersistedState();
      return;
    }
    // 异步落盘，不阻塞 UI。
    _persistAsync();
  }

  Future<void> _persistAsync() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefQueue, jsonEncode(_q.toJson()));
    await prefs.setInt(_prefPositionMs, _active.position.inMilliseconds);
    await prefs.setBool(_prefWasPlaying, _playing);
  }

  static PlaybackQueue? _decodeQueue(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<Object?, Object?>) {
        return PlaybackQueue.fromJson(decoded.cast<String, Object?>());
      }
      // 兼容旧格式（JSON 数组，恢复为顺序队列）。
      if (decoded is List<Object?>) {
        final List<SongEntity> songs = decoded
            .whereType<Map<Object?, Object?>>()
            .map((Map<Object?, Object?> m) =>
                SongEntity.fromJson(m.cast<String, Object?>()))
            .toList();
        return songs.isEmpty ? null : PlaybackQueue(items: songs);
      }
    } catch (_) {}
    return null;
  }

  void _resetPlayback() {
    _q = PlaybackQueue()..mode = _state.playbackMode.value;
    _playing = false;
    _emitSnapshot();
  }

  void _emitSnapshot() {
    final AppPlayerState s = _state;
    s.snapshot.value = PlayerSnapshot(
      song: currentSong,
      queue: List<SongEntity>.unmodifiable(_q.items),
      index: _q.currentIndex,
      isPlaying: _playing,
      isLoading: s.isLoading.value,
      position: s.position.value,
      duration: s.duration.value,
      bufferedPosition: s.bufferedPosition.value,
    );
  }
}
