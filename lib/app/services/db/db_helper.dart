import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'db_constants.dart';

/// SQLite 访问单例。
///
/// FnMusic 仅面向 Android（minSdk 35），使用宿主 sqflite（无需
/// sqflite_common_ffi 的桌面回退）。[resetForTest] 允许测试注入独立
/// 数据库路径；宿主单元测试不触碰真实 SQLite（无 ffi），纯逻辑由
/// `ListeningAccumulator` 承担，DB 层只做简单读写。
class DbHelper {
  DbHelper._internal();

  static final DbHelper instance = DbHelper._internal();

  Database? _db;
  String? _pathOverride;

  /// 关闭并重置句柄。`[overridePath]` 供测试指向临时/内存库。
  void resetForTest({String? overridePath}) {
    _db?.close();
    _db = null;
    _pathOverride = overridePath;
  }

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final db = await _open();
    _db = db;
    return db;
  }

  Future<Database> _open() async {
    final override = _pathOverride;
    final String path;
    if (override != null) {
      path = override;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = p.join(dir.path, DbConstants.dbName);
    }
    return openDatabase(
      path,
      version: DbConstants.dbVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createListeningDays(db);
    await _createSongStats(db);
    await _createAlbumStats(db);
    await _createPlaylistStats(db);
    await _createReportEvents(db);
  }

  Future<void> _createListeningDays(Database db) async {
    await db.execute('''
      CREATE TABLE ${DbConstants.tableListeningDays} (
        day_key TEXT PRIMARY KEY,
        listen_ms INTEGER NOT NULL DEFAULT 0,
        play_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createSongStats(Database db) async {
    await db.execute('''
      CREATE TABLE ${DbConstants.tableSongStats} (
        song_id TEXT PRIMARY KEY,
        song_title TEXT NOT NULL DEFAULT '',
        artist TEXT NOT NULL DEFAULT '',
        cover_id TEXT NOT NULL DEFAULT '',
        listen_ms INTEGER NOT NULL DEFAULT 0,
        play_count INTEGER NOT NULL DEFAULT 0,
        last_played_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_song_stats_play_count ON '
      '${DbConstants.tableSongStats}(play_count DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_song_stats_last_played ON '
      '${DbConstants.tableSongStats}(last_played_at DESC)',
    );
  }

  Future<void> _createAlbumStats(Database db) async {
    await db.execute('''
      CREATE TABLE ${DbConstants.tableAlbumStats} (
        album_id TEXT PRIMARY KEY,
        album_title TEXT NOT NULL DEFAULT '',
        artist TEXT NOT NULL DEFAULT '',
        cover_id TEXT NOT NULL DEFAULT '',
        play_count INTEGER NOT NULL DEFAULT 0,
        last_played_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_album_stats_last_played ON '
      '${DbConstants.tableAlbumStats}(last_played_at DESC)',
    );
  }

  Future<void> _createPlaylistStats(Database db) async {
    await db.execute('''
      CREATE TABLE ${DbConstants.tablePlaylistStats} (
        playlist_id TEXT PRIMARY KEY,
        playlist_title TEXT NOT NULL DEFAULT '',
        play_count INTEGER NOT NULL DEFAULT 0,
        last_played_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_playlist_stats_last_played ON '
      '${DbConstants.tablePlaylistStats}(last_played_at DESC)',
    );
  }

  Future<void> _createReportEvents(Database db) async {
    await db.execute('''
      CREATE TABLE ${DbConstants.tableReportEvents} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day_key TEXT NOT NULL,
        hour INTEGER NOT NULL,
        song_id TEXT NOT NULL,
        song_title TEXT NOT NULL DEFAULT '',
        artist TEXT NOT NULL DEFAULT '',
        album TEXT NOT NULL DEFAULT '',
        cover_id TEXT NOT NULL DEFAULT '',
        duration_ms INTEGER NOT NULL DEFAULT 0,
        play_ms INTEGER NOT NULL DEFAULT 0,
        completed INTEGER NOT NULL DEFAULT 0,
        session_start_ms INTEGER NOT NULL DEFAULT 0,
        session_end_ms INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_report_events_day ON '
      '${DbConstants.tableReportEvents}(day_key)',
    );
  }
}
