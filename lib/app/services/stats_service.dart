import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../state/player_state.dart';
import 'db/db_constants.dart';
import 'db/db_helper.dart';
import 'listening_accumulator.dart';

/// 按日收听统计。
class DayListeningStat {
  const DayListeningStat({
    required this.dayKey,
    required this.listenMs,
    required this.playCount,
  });

  final String dayKey;
  final int listenMs;
  final int playCount;
}

/// 单曲收听统计。
class SongListeningStat {
  const SongListeningStat({
    required this.songId,
    required this.songTitle,
    required this.artist,
    required this.coverId,
    required this.listenMs,
    required this.playCount,
    required this.lastPlayedAt,
  });

  final String songId;
  final String songTitle;
  final String artist;
  final String coverId;
  final int listenMs;
  final int playCount;
  final int lastPlayedAt;
}

/// 专辑播放统计。
class AlbumPlaybackStat {
  const AlbumPlaybackStat({
    required this.albumId,
    required this.albumTitle,
    required this.artist,
    required this.coverId,
    required this.playCount,
    required this.lastPlayedAt,
  });

  final String albumId;
  final String albumTitle;
  final String artist;
  final String coverId;
  final int playCount;
  final int lastPlayedAt;
}

/// 歌单播放统计。
class PlaylistPlaybackStat {
  const PlaylistPlaybackStat({
    required this.playlistId,
    required this.playlistTitle,
    required this.playCount,
    required this.lastPlayedAt,
  });

  final String playlistId;
  final String playlistTitle;
  final int playCount;
  final int lastPlayedAt;
}

/// 统计总览。
class StatsTotals {
  const StatsTotals({
    required this.totalListenMs,
    required this.totalPlayCount,
    required this.totalDays,
    required this.totalSongs,
  });

  final int totalListenMs;
  final int totalPlayCount;
  final int totalDays;
  final int totalSongs;
}

/// 听歌统计服务：订阅播放快照 → 纯累计器 → 落 SQLite。
///
/// 与原设计的差异：不建 songs 全量表，song_stats 内联显示列
/// （song_title/artist/cover_id），歌曲元数据仍以服务端 API 为准。
class StatsService {
  StatsService._internal();

  static final StatsService instance = StatsService._internal();

  final ListeningAccumulator _accumulator = ListeningAccumulator();
  final DateFormat _dayFormat = DateFormat('yyyy-MM-dd');

  /// 订阅一条播放快照。
  void onSnapshot(PlayerSnapshot snap) {
    final delta = _accumulator.onSnapshot(snap, DateTime.now());
    if (delta != null) unawaited(_applyDelta(delta, DateTime.now()));
  }

  /// 取走并落库未累计的增量（生命周期暂停/退到后台时调用）。
  Future<void> flush() async {
    final delta = _accumulator.takeAll();
    if (delta != null) {
      await _applyDelta(delta, DateTime.now());
    }
  }

  Future<void> _applyDelta(StatsDelta delta, DateTime now) async {
    final db = await DbHelper.instance.database;
    final dayKey = _dayFormat.format(now);
    final song = delta.song;
    await db.transaction((txn) async {
      await _upsertDay(txn, dayKey, delta.dayListenMs, delta.dayPlayCount);
      await _upsertSong(
        txn,
        songId: delta.songId,
        songTitle: song?.title ?? '',
        artist: song?.artistDisplay ?? '',
        coverId: song?.coverId ?? '',
        listenMs: delta.songListenMs,
        playCount: delta.songPlayCount,
        nowMs: now.millisecondsSinceEpoch,
      );
    });
  }

  Future<void> _upsertDay(
    DatabaseExecutor txn,
    String dayKey,
    int listenMs,
    int playCount,
  ) async {
    await txn.rawInsert(
      'INSERT OR IGNORE INTO ${DbConstants.tableListeningDays} '
      '(day_key, listen_ms, play_count) VALUES (?, ?, ?)',
      <Object?>[dayKey, 0, 0],
    );
    await txn.rawUpdate(
      'UPDATE ${DbConstants.tableListeningDays} SET '
      'listen_ms = listen_ms + ?, play_count = play_count + ? '
      'WHERE day_key = ?',
      <Object?>[listenMs, playCount, dayKey],
    );
  }

  Future<void> _upsertSong(
    DatabaseExecutor txn, {
    required String songId,
    required String songTitle,
    required String artist,
    required String coverId,
    required int listenMs,
    required int playCount,
    required int nowMs,
  }) async {
    await txn.rawInsert(
      'INSERT OR IGNORE INTO ${DbConstants.tableSongStats} '
      '(song_id, song_title, artist, cover_id, listen_ms, play_count, '
      'last_played_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      <Object?>[songId, songTitle, artist, coverId, 0, 0, 0],
    );
    if (songTitle.isNotEmpty || artist.isNotEmpty || coverId.isNotEmpty) {
      await txn.rawUpdate(
        'UPDATE ${DbConstants.tableSongStats} SET song_title = ?, '
        'artist = ?, cover_id = ? WHERE song_id = ?',
        <Object?>[songTitle, artist, coverId, songId],
      );
    }
    await txn.rawUpdate(
      'UPDATE ${DbConstants.tableSongStats} SET listen_ms = listen_ms + ?, '
      'play_count = play_count + ?, last_played_at = MAX(last_played_at, ?) '
      'WHERE song_id = ?',
      <Object?>[listenMs, playCount, nowMs, songId],
    );
  }

  // ---------------------------------------------------------------------
  // 查询
  // ---------------------------------------------------------------------

  /// 总览：总收听时长/次数/天数/歌曲数。
  Future<StatsTotals> fetchTotalStats() async {
    final db = await DbHelper.instance.database;
    final dayRow = await db.rawQuery(
      'SELECT COALESCE(SUM(listen_ms), 0) AS listen_ms, '
      'COALESCE(SUM(play_count), 0) AS play_count, '
      'COUNT(*) AS days FROM ${DbConstants.tableListeningDays}',
    );
    final songRow = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM ${DbConstants.tableSongStats}',
    );
    final d = dayRow.isNotEmpty ? dayRow.first : <String, Object?>{};
    final s = songRow.isNotEmpty ? songRow.first : <String, Object?>{};
    return StatsTotals(
      totalListenMs: (d['listen_ms'] as num?)?.toInt() ?? 0,
      totalPlayCount: (d['play_count'] as num?)?.toInt() ?? 0,
      totalDays: (d['days'] as num?)?.toInt() ?? 0,
      totalSongs: (s['cnt'] as num?)?.toInt() ?? 0,
    );
  }

  /// 按月聚合收听（统计页按月视图）。
  Future<List<DayListeningStat>> fetchMonthStats({
    required int year,
    required int month,
  }) async {
    final db = await DbHelper.instance.database;
    final prefix = '$year-${month.toString().padLeft(2, '0')}';
    final rows = await db.query(
      DbConstants.tableListeningDays,
      where: 'day_key LIKE ?',
      whereArgs: <Object?>['$prefix%'],
      orderBy: 'day_key ASC',
    );
    return rows
        .map((Map<String, Object?> r) => DayListeningStat(
              dayKey: r['day_key'] as String,
              listenMs: (r['listen_ms'] as num?)?.toInt() ?? 0,
              playCount: (r['play_count'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  /// 热门歌曲。
  Future<List<SongListeningStat>> fetchTopSongs({int limit = 20}) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      DbConstants.tableSongStats,
      orderBy: 'play_count DESC, listen_ms DESC',
      limit: limit,
    );
    return rows.map(_songStatFromRow).toList();
  }

  /// 最近播放歌曲。
  Future<List<SongListeningStat>> fetchRecentSongs({int limit = 20}) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      DbConstants.tableSongStats,
      orderBy: 'last_played_at DESC',
      limit: limit,
    );
    return rows.map(_songStatFromRow).toList();
  }

  SongListeningStat _songStatFromRow(Map<String, Object?> r) {
    return SongListeningStat(
      songId: r['song_id'] as String,
      songTitle: r['song_title'] as String? ?? '',
      artist: r['artist'] as String? ?? '',
      coverId: r['cover_id'] as String? ?? '',
      listenMs: (r['listen_ms'] as num?)?.toInt() ?? 0,
      playCount: (r['play_count'] as num?)?.toInt() ?? 0,
      lastPlayedAt: (r['last_played_at'] as num?)?.toInt() ?? 0,
    );
  }

  /// 最近播放专辑。
  Future<List<AlbumPlaybackStat>> fetchRecentAlbums({int limit = 20}) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      DbConstants.tableAlbumStats,
      orderBy: 'last_played_at DESC',
      limit: limit,
    );
    return rows
        .map((Map<String, Object?> r) => AlbumPlaybackStat(
              albumId: r['album_id'] as String,
              albumTitle: r['album_title'] as String? ?? '',
              artist: r['artist'] as String? ?? '',
              coverId: r['cover_id'] as String? ?? '',
              playCount: (r['play_count'] as num?)?.toInt() ?? 0,
              lastPlayedAt: (r['last_played_at'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  /// 最近播放歌单。
  Future<List<PlaylistPlaybackStat>> fetchRecentPlaylists({int limit = 20}) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      DbConstants.tablePlaylistStats,
      orderBy: 'last_played_at DESC',
      limit: limit,
    );
    return rows
        .map((Map<String, Object?> r) => PlaylistPlaybackStat(
              playlistId: r['playlist_id'] as String,
              playlistTitle: r['playlist_title'] as String? ?? '',
              playCount: (r['play_count'] as num?)?.toInt() ?? 0,
              lastPlayedAt: (r['last_played_at'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  /// 各曲播放次数（批量展示用）。
  Future<Map<String, int>> fetchPlayCounts() async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(DbConstants.tableSongStats,
        columns: <String>['song_id', 'play_count']);
    return <String, int>{
      for (final Map<String, Object?> r in rows)
        r['song_id'] as String: (r['play_count'] as num?)?.toInt() ?? 0,
    };
  }

  /// 各曲最后播放时间戳。
  Future<Map<String, int>> fetchLastPlayedTimestamps() async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(DbConstants.tableSongStats,
        columns: <String>['song_id', 'last_played_at']);
    return <String, int>{
      for (final Map<String, Object?> r in rows)
        r['song_id'] as String: (r['last_played_at'] as num?)?.toInt() ?? 0,
    };
  }

  /// 记录一次专辑播放。
  Future<void> recordAlbumPlay({
    required String albumId,
    required String albumTitle,
    required String artist,
    required String coverId,
  }) async {
    final db = await DbHelper.instance.database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.rawInsert(
        'INSERT OR IGNORE INTO ${DbConstants.tableAlbumStats} '
        '(album_id, album_title, artist, cover_id, play_count, '
        'last_played_at) VALUES (?, ?, ?, ?, ?, ?)',
        <Object?>[albumId, albumTitle, artist, coverId, 0, nowMs],
      );
      await txn.rawUpdate(
        'UPDATE ${DbConstants.tableAlbumStats} SET album_title = ?, '
        'artist = ?, cover_id = ?, play_count = play_count + 1, '
        'last_played_at = ? WHERE album_id = ?',
        <Object?>[albumTitle, artist, coverId, nowMs, albumId],
      );
    });
  }

  /// 测试钩子：注入后取代 SQLite 落库（widget 测试无 ffi 数据库）。
  @visibleForTesting
  static Future<void> Function(String playlistId, String playlistTitle)?
      recordPlaylistPlayOverride;

  /// 记录一次歌单播放。
  Future<void> recordPlaylistPlay({
    required String playlistId,
    required String playlistTitle,
  }) async {
    final Future<void> Function(String, String)? override =
        recordPlaylistPlayOverride;
    if (override != null) return override(playlistId, playlistTitle);
    final db = await DbHelper.instance.database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.rawInsert(
        'INSERT OR IGNORE INTO ${DbConstants.tablePlaylistStats} '
        '(playlist_id, playlist_title, play_count, last_played_at) '
        'VALUES (?, ?, ?, ?)',
        <Object?>[playlistId, playlistTitle, 0, nowMs],
      );
      await txn.rawUpdate(
        'UPDATE ${DbConstants.tablePlaylistStats} SET playlist_title = ?, '
        'play_count = play_count + 1, last_played_at = ? '
        'WHERE playlist_id = ?',
        <Object?>[playlistTitle, nowMs, playlistId],
      );
    });
  }

  // ---------------------------------------------------------------------
  // 导出 / 合并
  // ---------------------------------------------------------------------

  /// 导出全部统计为 JSON（备份恢复用）。
  Future<String> exportAll() async {
    final db = await DbHelper.instance.database;
    final listeningDays = await db.query(DbConstants.tableListeningDays);
    final songStats = await db.query(DbConstants.tableSongStats);
    final albumStats = await db.query(DbConstants.tableAlbumStats);
    final playlistStats = await db.query(DbConstants.tablePlaylistStats);
    final reportEvents = await db.query(DbConstants.tableReportEvents);
    return jsonEncode(<String, Object?>{
      'version': DbConstants.dbVersion,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'listening_days': listeningDays,
      'song_stats': songStats,
      'album_stats': albumStats,
      'playlist_stats': playlistStats,
      'report_events': reportEvents,
    });
  }

  /// 合并一份导出的 JSON（备份恢复用），按主键覆盖。
  Future<int> importMerge(String json) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return 0;
    }
    if (decoded is! Map<Object?, Object?>) return 0;
    final Map<String, Object?> data =
        decoded.map((Object? k, Object? v) => MapEntry(k.toString(), v));
    final db = await DbHelper.instance.database;
    var count = 0;
    await db.transaction((txn) async {
      for (final String table in <String>[
        DbConstants.tableListeningDays,
        DbConstants.tableSongStats,
        DbConstants.tableAlbumStats,
        DbConstants.tablePlaylistStats,
        DbConstants.tableReportEvents,
      ]) {
        final raw = data[table];
        if (raw is! List) continue;
        for (final Object? row in raw) {
          if (row is! Map) continue;
          count += await txn.insert(
            table,
            row.map((Object? k, Object? v) => MapEntry(k.toString(), v)),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
    return count;
  }
}
