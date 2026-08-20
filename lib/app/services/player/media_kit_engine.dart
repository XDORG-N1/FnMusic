import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'player_engine.dart';

/// [PlayerEngine] 的 media_kit（libmpv + FFmpeg）实现。
///
/// 负责 ExoPlayer 受限的格式（FLAC 32KB 帧缓冲上限、DSF/DSD/APE/WMA 等）。
/// FFmpeg 解码不受 32KB 限制；服务器转码的 FLAC HLS（m3u8）经
/// `Media.httpHeaders`（写入 mpv `http-header-fields`）携带 Cookie，
/// m3u8 及其分段都继承认证头。
///
/// media_kit 自身不申请 Android 音频焦点（无 AudioManager 逻辑），
/// 焦点完全由 App 的 audio_session 掌管，因此与 just_audio 不会双焦点冲突。
class MediaKitEngine implements PlayerEngine {
  mk.Player? _player;
  bool _disposed = false;

  // 归一化流：用 Subject 桥接 media_kit 原生流，让 PlayerService 只订阅一次。
  final StreamController<Duration> _positionCtl =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationCtl =
      StreamController<Duration?>.broadcast();
  final StreamController<Duration> _bufferedCtl =
      StreamController<Duration>.broadcast();
  final StreamController<EnginePlaybackState> _playbackStateCtl =
      StreamController<EnginePlaybackState>.broadcast();
  final StreamController<EngineError> _errorCtl =
      StreamController<EngineError>.broadcast();
  final StreamController<int?> _indexCtl = StreamController<int?>.broadcast();

  @override
  EngineKind get kind => EngineKind.mediaKit;

  /// 懒创建原生 [mk.Player]：首个 media_kit `loadQueue` 时才初始化，
  /// 避免 App 启动即多占一个 native handle（libmpv 加载 + 事件循环）。
  /// 初始化失败（原生库缺失/损坏）抛异常，由调用方（FnPlayerService）降级
  /// 回 just_audio，避免闪退。
  @override
  Future<void> init() async {
    if (_player != null || _disposed) return;
    final mk.Player player = mk.Player(
      configuration: const mk.PlayerConfiguration(
        logLevel: mk.MPVLogLevel.error,
      ),
    );
    _player = player;
    player.stream.log.listen((log) {
      if (kDebugMode) {
        debugPrint('[mpv:${log.prefix}] ${log.text}');
      }
    });
    _wire(player);
  }

  void _wire(mk.Player player) {
    player.stream.position.listen((v) {
      if (!_positionCtl.isClosed) _positionCtl.add(v);
    });
    player.stream.duration.listen((v) {
      if (!_durationCtl.isClosed) _durationCtl.add(v);
    });
    player.stream.buffer.listen((v) {
      if (!_bufferedCtl.isClosed) _bufferedCtl.add(v);
    });
    player.stream.playing.listen((bool playing) {
      if (!_playbackStateCtl.isClosed) {
        _playbackStateCtl.add(EnginePlaybackState(
          playing: playing,
          processingState: _stateOf(player),
        ));
      }
    });
    player.stream.buffering.listen((bool buffering) {
      if (!_playbackStateCtl.isClosed) {
        _playbackStateCtl.add(EnginePlaybackState(
          playing: player.state.playing,
          processingState: buffering
              ? EngineProcessingState.buffering
              : EngineProcessingState.ready,
        ));
      }
    });
    player.stream.completed.listen((bool completed) {
      if (kDebugMode && completed) {
        // 诊断：media_kit 可能在加载失败时也置 completed（mpv 端无法播放），
        // 导致 PlayerService 把它当"播完"前进而不是走 error 恢复。
        debugPrint(
            '[MediaKitEngine] completed=true index=${player.state.playlist.index}');
      }
      if (!_playbackStateCtl.isClosed) {
        _playbackStateCtl.add(EnginePlaybackState(
          playing: player.state.playing,
          processingState: completed
              ? EngineProcessingState.completed
              : EngineProcessingState.ready,
        ));
      }
    });
    player.stream.playlist.listen((playlist) {
      if (!_indexCtl.isClosed) _indexCtl.add(playlist.index);
    });
    player.stream.error.listen((String msg) {
      if (kDebugMode) {
        debugPrint(
            '[MediaKitEngine] error="$msg" index=${player.state.playlist.index}');
      }
      if (_errorCtl.isClosed) return;
      final int idx = player.state.playlist.index;
      _errorCtl.add(EngineError(
        message: msg,
        index: idx >= 0 && idx < player.state.playlist.medias.length ? idx : null,
      ));
    });
  }

  EngineProcessingState _stateOf(mk.Player player) {
    if (player.state.buffering) return EngineProcessingState.buffering;
    if (player.state.completed) return EngineProcessingState.completed;
    if (player.state.playlist.medias.isEmpty) return EngineProcessingState.idle;
    return EngineProcessingState.ready;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _closeControllers();
    final mk.Player? p = _player;
    _player = null;
    if (p != null) {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }

  Future<void> _closeControllers() async {
    await _positionCtl.close();
    await _durationCtl.close();
    await _bufferedCtl.close();
    await _playbackStateCtl.close();
    await _errorCtl.close();
    await _indexCtl.close();
  }

  /// media_kit `Player.open` 的硬超时。mpv 对**本地文件**应在几百毫秒内完成
  /// open；超时说明 mpv 卡在协议/解码初始化（如媒体无法识别、HLS 无法解析），
  /// 继续等待只会让 PlayerService 挂起。超时抛 [TimeoutException]，
  /// FnPlayerService 捕获后降级回 just_audio 直连，不让播放器卡死。
  static const Duration openTimeout = Duration(seconds: 10);

  @override
  Future<void> loadQueue({
    required List<EngineItem> items,
    required int index,
    Duration? initialPosition,
    bool preload = false,
  }) async {
    await init();
    final mk.Player player = _player!;
    final List<mk.Media> medias = items
        .cast<MediaKitItem>()
        .map((MediaKitItem e) => e.media)
        .toList(growable: false);
    final int safeIndex = index.clamp(0, medias.length - 1);
    await player
        .open(mk.Playlist(medias, index: safeIndex), play: false)
        .timeout(openTimeout);
    if (initialPosition != null && initialPosition > Duration.zero) {
      await player.seek(initialPosition);
    }
  }

  @override
  Future<void> play() async {
    final mk.Player? p = _player;
    if (p == null) return;
    await p.play();
  }

  @override
  Future<void> pause() async {
    final mk.Player? p = _player;
    if (p == null) return;
    await p.pause();
  }

  @override
  Future<void> stop() async {
    final mk.Player? p = _player;
    if (p == null) return;
    try {
      await p.stop();
    } catch (_) {}
  }

  @override
  Future<void> seek(Duration position) async {
    final mk.Player? p = _player;
    if (p == null) return;
    await p.seek(position);
  }

  @override
  Future<void> seekToNext() async {
    final mk.Player? p = _player;
    if (p == null) return;
    await p.next();
  }

  @override
  Future<void> seekToPrevious() async {
    final mk.Player? p = _player;
    if (p == null) return;
    await p.previous();
  }

  @override
  Future<void> skipToIndex(int index) async {
    final mk.Player? p = _player;
    if (p == null) return;
    final List<mk.Media> medias = p.state.playlist.medias;
    if (index < 0 || index >= medias.length) return;
    await p.open(mk.Playlist(medias, index: index), play: p.state.playing);
  }

  @override
  Future<void> setLoopMode(EngineLoopMode mode) async {
    final mk.Player? p = _player;
    if (p == null) return;
    final mk.PlaylistMode m = switch (mode) {
      EngineLoopMode.none => mk.PlaylistMode.none,
      EngineLoopMode.single => mk.PlaylistMode.single,
      EngineLoopMode.all => mk.PlaylistMode.loop,
    };
    await p.setPlaylistMode(m);
  }

  @override
  Future<void> setVolume(double volume) async {
    final mk.Player? p = _player;
    if (p == null) return;
    // media_kit 的 volume 是 0..100 的百分比（mpv `volume` 属性，默认 100），
    // 而引擎接口约定 0..1 归一化音量，这里换算。
    await p.setVolume(volume.clamp(0.0, 1.0) * 100);
  }

  @override
  Future<void> setSpeed(double speed) async {
    final mk.Player? p = _player;
    if (p == null) return;
    try {
      await p.setRate(speed);
    } catch (_) {}
  }

  @override
  Future<void> insertItem(int index, EngineItem item) async {
    final mk.Player? p = _player;
    if (p == null) return;
    await p.add((item as MediaKitItem).media);
  }

  @override
  Future<void> insertItems(int index, List<EngineItem> items) async {
    final mk.Player? p = _player;
    if (p == null) return;
    for (final EngineItem item in items) {
      await p.add((item as MediaKitItem).media);
    }
  }

  @override
  Future<void> moveItem(int from, int to) async {
    final mk.Player? p = _player;
    if (p == null) return;
    await p.move(from, to);
  }

  @override
  Duration get position => _player?.state.position ?? Duration.zero;

  @override
  int? get currentIndex => _player?.state.playlist.index;

  @override
  int get sequenceLength => _player?.state.playlist.medias.length ?? 0;

  @override
  bool get hasLoadedSource =>
      _player != null && _player!.state.playlist.medias.isNotEmpty;

  @override
  bool get playing => _player?.state.playing ?? false;

  @override
  EngineProcessingState get processingState {
    final mk.Player? p = _player;
    if (p == null) return EngineProcessingState.idle;
    return _stateOf(p);
  }

  @override
  EngineLoopMode get loopMode {
    final mk.Player? p = _player;
    if (p == null) return EngineLoopMode.none;
    return switch (p.state.playlistMode) {
      mk.PlaylistMode.none => EngineLoopMode.none,
      mk.PlaylistMode.single => EngineLoopMode.single,
      mk.PlaylistMode.loop => EngineLoopMode.all,
    };
  }

  @override
  Stream<Duration> get positionStream => _positionCtl.stream;

  @override
  Stream<Duration?> get durationStream => _durationCtl.stream;

  @override
  Stream<Duration> get bufferedPositionStream => _bufferedCtl.stream;

  @override
  Stream<EnginePlaybackState> get playbackStateStream => _playbackStateCtl.stream;

  @override
  Stream<EngineError> get errorStream => _errorCtl.stream;

  @override
  Stream<int?> get currentIndexStream => _indexCtl.stream;
}
