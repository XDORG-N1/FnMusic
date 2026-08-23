import '../state/player_state.dart';
import '../state/song_state.dart';

/// 一次可落库的收听增量。
class StatsDelta {
  const StatsDelta({
    required this.songId,
    required this.song,
    required this.songListenMs,
    required this.songPlayCount,
    required this.dayListenMs,
    required this.dayPlayCount,
  });

  final String songId;

  /// 关联的歌曲（快照切换时取旧曲，保证显示列对应所累计的时长）。
  final SongEntity? song;

  final int songListenMs;
  final int songPlayCount;
  final int dayListenMs;
  final int dayPlayCount;
}

/// 纯函数式收听累计器：只根据 [PlayerSnapshot] + 时钟增量累计，
/// 不触碰 IO/数据库，可独立单元测试。
///
/// 规则（对齐原设计 StatsService）：
/// - 只在 `snap.isPlaying` 且有当前歌曲时累计；
/// - 两次快照间隔超过 [maxTickGapMs] 视为中断，本次增量封顶；
/// - 单曲累计满 [playCountThresholdMs] 计 1 次播放；
/// - 累计满 [flushThresholdMs] 主动产出增量（防止长时间播放无落库）；
/// - 暂停 / 切歌 / [takeAll] 时取走未落库增量。
class ListeningAccumulator {
  ListeningAccumulator({
    this.maxTickGapMs = 10000,
    this.playCountThresholdMs = 30000,
    this.flushThresholdMs = 15000,
  });

  final int maxTickGapMs;
  final int playCountThresholdMs;
  final int flushThresholdMs;

  SongEntity? _currentSong;
  int _currentSongPlayedMs = 0;
  bool _currentPlayCounted = false;
  DateTime? _lastTickAt;

  int _pendingSongListenMs = 0;
  int _pendingSongPlayCount = 0;
  int _pendingDayListenMs = 0;
  int _pendingDayPlayCount = 0;

  /// 累计一条快照；需要落库时返回增量，否则返回 null。
  StatsDelta? onSnapshot(PlayerSnapshot snap, DateTime now) {
    final song = snap.song;
    if (!snap.isPlaying || song == null) {
      // 暂停/停止/空曲：结束本段累计并取走待落库增量。
      _lastTickAt = null;
      return takeAll();
    }

    if (_currentSong?.guid != song.guid) {
      // 切歌：先取走上一首的累计，再切换到新曲。
      final delta = takeAll();
      _currentSong = song;
      _currentSongPlayedMs = 0;
      _currentPlayCounted = false;
      if (delta != null) return delta;
    }

    final last = _lastTickAt;
    _lastTickAt = now;
    if (last == null) return null; // 首个快照，无间隔可累计。

    var deltaMs = now.difference(last).inMilliseconds;
    if (deltaMs <= 0) return null;
    if (deltaMs > maxTickGapMs) deltaMs = maxTickGapMs;

    _currentSongPlayedMs += deltaMs;
    _pendingSongListenMs += deltaMs;
    _pendingDayListenMs += deltaMs;

    if (!_currentPlayCounted && _currentSongPlayedMs >= playCountThresholdMs) {
      _currentPlayCounted = true;
      _pendingSongPlayCount += 1;
      _pendingDayPlayCount += 1;
    }

    if (_pendingSongListenMs >= flushThresholdMs ||
        _pendingDayListenMs >= flushThresholdMs) {
      return takeAll();
    }
    return null;
  }

  /// 取走当前未落库增量（生命周期暂停 / 手动 flush 时调用）。
  StatsDelta? takeAll() {
    final song = _currentSong;
    if (song == null) return null;
    if (_pendingSongListenMs <= 0 &&
        _pendingSongPlayCount <= 0 &&
        _pendingDayListenMs <= 0 &&
        _pendingDayPlayCount <= 0) {
      return null;
    }
    final delta = StatsDelta(
      songId: song.guid,
      song: song,
      songListenMs: _pendingSongListenMs,
      songPlayCount: _pendingSongPlayCount,
      dayListenMs: _pendingDayListenMs,
      dayPlayCount: _pendingDayPlayCount,
    );
    _pendingSongListenMs = 0;
    _pendingSongPlayCount = 0;
    _pendingDayListenMs = 0;
    _pendingDayPlayCount = 0;
    return delta;
  }
}
