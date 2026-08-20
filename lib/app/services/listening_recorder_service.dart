import 'package:sqflite/sqflite.dart';

import '../state/player_state.dart';
import '../state/song_state.dart';
import 'db/db_constants.dart';
import 'db/db_helper.dart';

/// 听歌行为记录器：把每次单曲播放会话写入 report_events 流水表，
/// 供听歌报告 / 导出使用。累计规则与 [StatsService] 一致（封顶间隔）。
///
/// 与参考项目的差异：歌曲标识用 `song.guid`，显示列内联
/// （song_title / artist / album / cover_id），不依赖 songs 表。
class ListeningRecorderService {
  ListeningRecorderService._internal();

  static final ListeningRecorderService instance =
      ListeningRecorderService._internal();

  /// 两次快照最大间隔（毫秒），超过视为中断，本次间隔封顶。
  static const int maxTickGapMs = 10000;

  _Session? _session;
  final List<_Session> _pending = <_Session>[];
  DateTime _lastPruneAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _flushing = false;

  /// 订阅一条播放快照。
  void onSnapshot(PlayerSnapshot snap) {
    final song = snap.song;
    if (!snap.isPlaying || song == null) {
      _finalizeCurrent(completed: false);
      return;
    }
    final session = _session;
    if (session == null || session.song.guid != song.guid) {
      _finalizeCurrent(completed: false);
      _session = _Session(song, DateTime.now());
      return;
    }
    final DateTime now = DateTime.now();
    final DateTime last = session.lastTickAt;
    session.lastTickAt = now;
    var deltaMs = now.difference(last).inMilliseconds;
    if (deltaMs <= 0) return;
    if (deltaMs > maxTickGapMs) deltaMs = maxTickGapMs;
    session.playMs += deltaMs;
  }

  /// 标记当前会话「播完」——在播放器完成事件（_onCompleted）中调用。
  void markCompleted() {
    final session = _session;
    if (session == null) return;
    session.isCompleted = true;
  }

  /// 立即把待落库会话写入数据库并清理（退后台/生命周期暂停时调用）。
  Future<void> flush() async {
    _finalizeCurrent(completed: false);
    if (_pending.isEmpty) return;
    if (_flushing) return;
    _flushing = true;
    try {
      final db = await DbHelper.instance.database;
      await db.transaction((txn) async {
        for (final _Session s in _pending) {
          await txn.insert(DbConstants.tableReportEvents, s.toRow(),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        _pending.clear();
      });
      await _pruneIfNeeded(db);
    } finally {
      _flushing = false;
    }
  }

  /// 应用进入后台时兜底落库。
  Future<void> onLifecyclePause() => flush();

  void _finalizeCurrent({required bool completed}) {
    final session = _session;
    if (session == null) return;
    if (session.playMs <= 0) {
      _session = null;
      return;
    }
    if (completed) session.isCompleted = true;
    session.endMs = DateTime.now().millisecondsSinceEpoch;
    _pending.add(session);
    _session = null;
  }

  Future<void> _pruneIfNeeded(Database db) async {
    final now = DateTime.now();
    if (now.difference(_lastPruneAt).inHours < 24) return;
    _lastPruneAt = now;
    final cutoff =
        now.subtract(const Duration(days: DbConstants.reportEventRetentionDays));
    await db.delete(
      DbConstants.tableReportEvents,
      where: 'session_end_ms < ?',
      whereArgs: <Object?>[cutoff.millisecondsSinceEpoch],
    );
  }
}

/// 单曲播放会话。
class _Session {
  _Session(this.song, DateTime startAt)
      : startMs = startAt.millisecondsSinceEpoch,
        lastTickAt = startAt;

  final SongEntity song;
  final int startMs;
  int playMs = 0;
  int endMs = 0;
  bool isCompleted = false;

  /// 上一拍时间，初始为会话开始时刻（首拍即从开始累计）。
  DateTime lastTickAt;

  Map<String, Object?> toRow() {
    final DateTime start =
        DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: false);
    final String dayKey = '${start.year.toString().padLeft(4, '0')}-'
        '${start.month.toString().padLeft(2, '0')}-'
        '${start.day.toString().padLeft(2, '0')}';
    return <String, Object?>{
      'day_key': dayKey,
      'hour': start.hour,
      'song_id': song.guid,
      'song_title': song.title,
      'artist': song.artistDisplay ?? '',
      'album': song.albumDisplay ?? '',
      'cover_id': song.coverId ?? '',
      'duration_ms': song.durationMs ?? 0,
      'play_ms': playMs,
      'completed': isCompleted ? 1 : 0,
      'session_start_ms': startMs,
      'session_end_ms': endMs > 0 ? endMs : startMs,
    };
  }
}
