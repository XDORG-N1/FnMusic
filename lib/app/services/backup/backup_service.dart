import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart' as dio;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../../utils/app_info.dart';
import '../db/db_constants.dart';
import '../db/db_helper.dart';
import '../feiniu/account_entry.dart';
import '../feiniu/account_store.dart';
import '../stats_service.dart';

/// 备份包含的数据分块。持久化，用户配置一次即可。
///
/// - [accounts]：已保存的飞牛账号（含 token，请妥善保管备份文件）
/// - [stats]：听歌统计 + report_events 原始事件（可完整还原听歌报告）
/// - [settings]：应用偏好（SharedPreferences 通用键）
class BackupSections {
  final bool accounts;
  final bool stats;
  final bool settings;

  const BackupSections({
    this.accounts = true,
    this.stats = true,
    this.settings = true,
  });

  BackupSections copyWith({
    bool? accounts,
    bool? stats,
    bool? settings,
  }) => BackupSections(
    accounts: accounts ?? this.accounts,
    stats: stats ?? this.stats,
    settings: settings ?? this.settings,
  );

  bool get any => accounts || stats || settings;
}

/// 本地备份目录下的一份备份文件。
class LocalBackupEntry {
  final String name;
  final String path;
  final int sizeBytes;
  final DateTime? modified;

  const LocalBackupEntry({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modified,
  });
}

/// 备份目标：一个 WebDAV 服务器的端点 + 账号 + 服务器上的目录。
class BackupTarget {
  final String id;
  final String name;
  final String endpoint;
  final String username;
  final String password;
  final String path;

  const BackupTarget({
    required this.id,
    this.name = '',
    required this.endpoint,
    this.username = '',
    this.password = '',
    this.path = BackupService.defaultBasePath,
  });

  BackupTarget copyWith({
    String? id,
    String? name,
    String? endpoint,
    String? username,
    String? password,
    String? path,
  }) => BackupTarget(
    id: id ?? this.id,
    name: name ?? this.name,
    endpoint: endpoint ?? this.endpoint,
    username: username ?? this.username,
    password: password ?? this.password,
    path: path ?? this.path,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'endpoint': endpoint,
        'username': username,
        'password': password,
        'path': path,
      };

  factory BackupTarget.fromJson(Map<String, dynamic> json) => BackupTarget(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        endpoint: (json['endpoint'] ?? '').toString(),
        username: (json['username'] ?? '').toString(),
        password: (json['password'] ?? '').toString(),
        path: (json['path'] ?? BackupService.defaultBasePath).toString(),
      );
}

class BackupUploadResult {
  final BackupTarget target;
  final bool ok;
  final String? message;

  const BackupUploadResult({
    required this.target,
    required this.ok,
    this.message,
  });
}

/// 携带用户可见信息（含真实 HTTP 状态码）的备份失败异常。
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);

  @override
  String toString() => message;
}

class WebDavBackupEntry {
  final String name;
  final String path;
  final int sizeBytes;
  final DateTime? modified;
  final String? deviceId;
  final bool isCurrentDevice;

  const WebDavBackupEntry({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modified,
    required this.deviceId,
    required this.isCurrentDevice,
  });
}

/// WebDAV 服务器上的一个文件夹（供备份目录选择器浏览）。
class WebDavFolder {
  final String name;
  final String path;

  const WebDavFolder({required this.name, required this.path});
}

/// 数据备份 / 还原服务。
///
/// 与参考项目的差异：无 file_picker（不在离线 pub cache），本地备份改为
/// 写入应用文档目录 `backups/`（应用内列出/导入/删除）；无 package_info_plus，
/// 版本号取 [AppInfo.version] 常量。WebDAV 能力完整保留。
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const int formatVersion = 1;
  static const String appName = 'fnmusic';
  static const String webDavFolder = 'FnMusicBackup';

  /// 备份目录默认基础路径：用户填写目录后会自动拼接 [webDavFolder]。
  static const String defaultBasePath = '/';

  /// 默认保留的备份份数（每设备）。
  static const int defaultKeepCount = 10;
  static const List<int> keepCountOptions = <int>[5, 10, 20, 30];

  static const String _prefsSectionsKey = 'backup_sections_v1';
  static const String _prefsDeviceId = 'backup_device_id';
  static const String _prefsTargetsKey = 'backup_targets_v1';
  static const String _prefsAutoEnabled = 'backup_auto_enabled';
  static const String _prefsAutoKeepCount = 'backup_auto_keep_count';
  static const String _prefsAutoLastMs = 'backup_auto_last_ms';

  /// 不得作为通用「应用设置」导出的键（随账号分块走或为运行时槽位）。
  static const Set<String> _settingsDenyList = <String>{
    'settings_accounts.list',
    'settings_accounts.active',
    // 运行时会话/激活槽位
    'feiniu_music_token',
    'feiniu_server_url',
    'feiniu_relay_mode',
    'feiniu_username',
    'feiniu_password',
    'fn_access_code',
    'fn_last_fnid',
    // 播放状态是运行时槽位（启动恢复用），不属于用户设置
    'playback_state.queueJson',
    'playback_state.positionMs',
    'playback_state.wasPlaying',
    // 备份自身配置
    _prefsSectionsKey,
    _prefsDeviceId,
    _prefsTargetsKey,
    _prefsAutoEnabled,
    _prefsAutoKeepCount,
    _prefsAutoLastMs,
  };

  final StatsService _stats = StatsService.instance;

  // ---------------------------------------------------------------------
  // 备份内容偏好
  // ---------------------------------------------------------------------

  Future<BackupSections> loadSections() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsSectionsKey);
    if (raw == null) return const BackupSections();
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return BackupSections(
        accounts: m['accounts'] as bool? ?? true,
        stats: m['stats'] as bool? ?? true,
        settings: m['settings'] as bool? ?? true,
      );
    } catch (_) {
      return const BackupSections();
    }
  }

  Future<void> saveSections(BackupSections s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsSectionsKey,
      jsonEncode(<String, Object?>{
        'accounts': s.accounts,
        'stats': s.stats,
        'settings': s.settings,
      }),
    );
  }

  // ---------------------------------------------------------------------
  // 构建 / 解析
  // ---------------------------------------------------------------------

  Future<String> buildBackupJson(BackupSections sections) async {
    final data = <String, dynamic>{
      'format': formatVersion,
      'app': appName,
      'dbVersion': DbConstants.dbVersion,
      'appVersion': AppInfo.version,
      'exportedAtMs': DateTime.now().millisecondsSinceEpoch,
      'sections': <String, dynamic>{
        'accounts': sections.accounts,
        'stats': sections.stats,
        'settings': sections.settings,
      },
    };

    if (sections.accounts) {
      data['accounts'] = await _exportAccounts();
      data['currentAccountId'] = await _exportCurrentAccountId();
    }
    if (sections.stats) {
      data['stats'] = await _exportStats();
    }
    if (sections.settings) {
      data['settings'] = await _exportSettings();
    }

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 导入备份（智能合并），返回简短的中文摘要。
  /// [restrict] 限制即使文件包含也仅应用其中部分分块。
  Future<String> restoreFromJson(
    String jsonStr, {
    BackupSections? restrict,
  }) async {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('备份文件格式无效');
    }
    if (data['format'] == null || data['app'] != appName) {
      throw const FormatException('不是有效的 FnMusic 备份文件');
    }

    final applied = <String>[];

    if (data['accounts'] is List && (restrict?.accounts ?? true)) {
      final n = await _importAccounts(
        (data['accounts'] as List),
        data['currentAccountId']?.toString(),
      );
      applied.add('账号 $n 个');
    }
    if (data['stats'] is Map && (restrict?.stats ?? true)) {
      await _importStats((data['stats'] as Map).cast<String, dynamic>());
      applied.add('听歌统计');
    }
    if (data['settings'] is Map && (restrict?.settings ?? true)) {
      await _importSettings((data['settings'] as Map).cast<String, dynamic>());
      applied.add('应用设置');
    }

    return applied.isEmpty ? '没有可导入的数据' : '已导入：${applied.join('、')}';
  }

  // ---- accounts ----

  Future<List<Map<String, Object?>>> _exportAccounts() async {
    final store = AccountStore.instance;
    await store.ensureLoaded();
    return store.accounts.value.map((AccountEntry e) => e.toJson()).toList();
  }

  Future<String?> _exportCurrentAccountId() async {
    final store = AccountStore.instance;
    await store.ensureLoaded();
    return store.activeAccountId.value;
  }

  Future<int> _importAccounts(List raw, String? currentAccountId) async {
    final store = AccountStore.instance;
    await store.ensureLoaded();

    var count = 0;
    // 备份内 id → 合并后的条目：同身份账号已存在时 addAccount 保留本地 id，
    // 需用备份 id 兜底找回「当时的当前账号」。
    final byBackupId = <String, AccountEntry>{};
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        final entry = AccountEntry.fromJson(item.cast<String, Object?>());
        if (entry.id.isEmpty) continue;
        final canonical = await store.addAccount(entry);
        byBackupId[entry.id] = canonical;
        count++;
      } catch (_) {}
    }
    // 还原「当前激活账号」，使备份里的登录态还原后保持。
    if (count > 0 && currentAccountId != null && currentAccountId.isNotEmpty) {
      AccountEntry? target;
      for (final AccountEntry a in store.accounts.value) {
        if (a.id == currentAccountId) {
          target = a;
          break;
        }
      }
      target ??= byBackupId[currentAccountId];
      if (target != null) {
        await store.setActiveAccount(target.id);
      }
    }
    return count;
  }

  // ---- stats ----

  Future<Map<String, dynamic>> _exportStats() async {
    final jsonStr = await _stats.exportAll();
    return (jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  Future<void> _importStats(Map<String, dynamic> data) async {
    // 1) 聚合统计：智能合并（累加计数 / 取 max 时间，按主键 replace）。
    final agg = <String, dynamic>{...data}..remove('report_events');
    if (agg.isNotEmpty) {
      await _stats.importMerge(jsonEncode(agg));
    }

    // 2) report_events：按 (songId, sessionStartMs) 去重插入；移除自增 id，
    //    避免不同设备备份的主键冲突互相覆盖。
    final events = (data['report_events'] as List?) ?? const [];
    if (events.isEmpty) return;
    final db = await DbHelper.instance.database;
    await db.transaction((txn) async {
      for (final raw in events) {
        if (raw is! Map) continue;
        final row = raw
            .map((Object? k, Object? v) => MapEntry(k.toString(), v))
          ..remove('id');
        final songId = row['song_id']?.toString() ?? '';
        final startMs = row['session_start_ms'];
        if (songId.isEmpty || startMs == null) continue;
        final existing = await txn.query(
          DbConstants.tableReportEvents,
          where: 'song_id = ? AND session_start_ms = ?',
          whereArgs: <Object?>[songId, startMs],
          limit: 1,
        );
        if (existing.isNotEmpty) continue;
        await txn.insert(
          DbConstants.tableReportEvents,
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // ---- settings（通用 prefs） ----

  Future<Map<String, dynamic>> _exportSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (_settingsDenyList.contains(key)) continue;
      final value = prefs.get(key);
      if (value is bool) {
        out[key] = <String, Object?>{'t': 'b', 'v': value};
      } else if (value is int) {
        out[key] = <String, Object?>{'t': 'i', 'v': value};
      } else if (value is double) {
        out[key] = <String, Object?>{'t': 'd', 'v': value};
      } else if (value is String) {
        out[key] = <String, Object?>{'t': 's', 'v': value};
      } else if (value is List<String>) {
        out[key] = <String, Object?>{'t': 'l', 'v': value};
      }
    }
    return out;
  }

  Future<void> _importSettings(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in data.entries) {
      if (_settingsDenyList.contains(entry.key)) continue;
      final v = entry.value;
      if (v is! Map) continue;
      final type = v['t'];
      final value = v['v'];
      try {
        switch (type) {
          case 'b':
            await prefs.setBool(entry.key, value as bool);
            break;
          case 'i':
            await prefs.setInt(entry.key, (value as num).toInt());
            break;
          case 'd':
            await prefs.setDouble(entry.key, (value as num).toDouble());
            break;
          case 's':
            await prefs.setString(entry.key, value as String);
            break;
          case 'l':
            await prefs.setStringList(
              entry.key,
              (value as List).map((Object? e) => e.toString()).toList(),
            );
            break;
        }
      } catch (_) {}
    }
  }

  // ---- 本地文件（应用文档目录 backups/，无 file_picker 依赖） ----

  Future<Directory> _localBackupDir() async {
    final doc = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(doc.path, 'backups'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 构建备份 JSON 并写入本地备份目录，返回文件路径。
  Future<String> exportToLocal(BackupSections sections) async {
    final jsonStr = await buildBackupJson(sections);
    final dir = await _localBackupDir();
    final file = File(p.join(dir.path, 'fnmusic-backup-${_tsNow()}.json'));
    await file.writeAsString(jsonStr, flush: true);
    return file.path;
  }

  /// 列出本地备份目录下的全部备份文件（按时间倒序）。
  Future<List<LocalBackupEntry>> listLocalBackups() async {
    final dir = await _localBackupDir();
    final files = await dir.list().toList();
    final entries = <LocalBackupEntry>[];
    for (final entity in files) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith('fnmusic-backup') || !name.endsWith('.json')) {
        continue;
      }
      final stat = await entity.stat();
      entries.add(
        LocalBackupEntry(
          name: name,
          path: entity.path,
          sizeBytes: stat.size,
          modified: stat.modified,
        ),
      );
    }
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    entries.sort(
      (a, b) => (b.modified ?? epoch).compareTo(a.modified ?? epoch),
    );
    return entries;
  }

  Future<String> readLocalBackup(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const BackupException('备份文件不存在');
    }
    return file.readAsString();
  }

  Future<void> deleteLocalBackup(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  // ---- WebDAV ----

  webdav.Client _client(BackupTarget target) {
    final client = webdav.newClient(
      target.endpoint.trim(),
      user: target.username,
      password: target.password,
      debug: kDebugMode,
    );
    client.setHeaders(<String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      'Accept': '*/*',
    });
    client.setConnectTimeout(15000);
    client.setSendTimeout(60000);
    client.setReceiveTimeout(60000);
    return client;
  }

  /// 归一化路径：空 → '/'；补前导斜杠；去尾部斜杠。
  static String normalizeDir(String path) {
    var base = path.trim();
    if (base.isEmpty) return '/';
    base = base.replaceAll('\\', '/');
    if (!base.startsWith('/')) base = '/$base';
    if (base.length > 1 && base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base.isEmpty ? '/' : base;
  }

  /// 实际备份目录 = 基础目录 + `/FnMusicBackup`。
  String _backupDir(String basePath) {
    final base = normalizeDir(basePath);
    if (base == '/') return '/$webDavFolder';
    return '$base/$webDavFolder';
  }

  /// 每设备稳定的短 id，用于区分不同设备上传的备份。
  Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsDeviceId);
    if (id == null || id.isEmpty) {
      final rand = Random().nextInt(0x7fffffff).toRadixString(36);
      id = (DateTime.now().microsecondsSinceEpoch.toRadixString(36) + rand)
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (id.length > 8) id = id.substring(id.length - 8);
      await prefs.setString(_prefsDeviceId, id);
    }
    return id;
  }

  String _tsNow() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }

  DateTime? _parseTs(String ts) {
    if (ts.length != 14) return null;
    try {
      return DateTime(
        int.parse(ts.substring(0, 4)),
        int.parse(ts.substring(4, 6)),
        int.parse(ts.substring(6, 8)),
        int.parse(ts.substring(8, 10)),
        int.parse(ts.substring(10, 12)),
        int.parse(ts.substring(12, 14)),
      );
    } catch (_) {
      return null;
    }
  }

  /// 向单个目标上传一份带时间戳、按设备区分的备份并清理旧份。
  /// 失败抛 [BackupException]（含真实 HTTP 状态 + 路径）。
  Future<String> uploadToTarget(
    BackupTarget target,
    BackupSections sections,
  ) async {
    final jsonStr = await buildBackupJson(sections);
    final client = _client(target);
    final dir = _backupDir(target.path);
    try {
      await client.mkdirAll(dir);
    } catch (e) {
      if (kDebugMode) debugPrint('BackupService mkdirAll($dir) failed: $e');
    }
    final dev = await deviceId();
    final path = '$dir/fnmusic_backup__${dev}__${_tsNow()}.json';
    try {
      await client.write(path, Uint8List.fromList(utf8.encode(jsonStr)));
    } on dio.DioException catch (e) {
      final code = e.response?.statusCode;
      throw BackupException(
        code != null ? '上传失败：HTTP $code $dir' : '上传失败：$dir 不可写或无法连接',
      );
    } catch (e) {
      throw BackupException('上传失败：$e');
    }
    await _pruneWebDav(
      client,
      dir,
      dev,
      keep: await loadKeepCount(),
    );
    return path;
  }

  /// 一键上传到所有目标。不抛异常，收集逐目标结果供调用方汇总。
  Future<List<BackupUploadResult>> uploadToAllTargets(
    List<BackupTarget> targets,
    BackupSections sections,
  ) async {
    final results = <BackupUploadResult>[];
    for (final t in targets) {
      try {
        await uploadToTarget(t, sections);
        results.add(BackupUploadResult(target: t, ok: true));
      } catch (e) {
        final msg = e is BackupException ? e.message : e.toString();
        results.add(BackupUploadResult(target: t, ok: false, message: msg));
      }
    }
    return results;
  }

  Future<List<WebDavBackupEntry>> listWebDavBackups(BackupTarget target) async {
    final client = _client(target);
    final dir = _backupDir(target.path);
    List<webdav.File> files;
    try {
      files = await client.readDir(dir);
    } catch (_) {
      return const [];
    }
    final me = await deviceId();
    final list = <WebDavBackupEntry>[];
    for (final f in files) {
      if (f.isDir ?? false) continue;
      final name = f.name ?? '';
      if (!name.startsWith('fnmusic_backup') || !name.endsWith('.json')) {
        continue;
      }
      String? dev;
      DateTime? ts;
      final core = name.substring(0, name.length - 5);
      final parts = core.split('__');
      if (parts.length >= 3) {
        dev = parts[1];
        ts = _parseTs(parts[2]);
      }
      list.add(
        WebDavBackupEntry(
          name: name,
          path: f.path ?? '$dir/$name',
          sizeBytes: f.size ?? 0,
          modified: f.mTime ?? ts,
          deviceId: dev,
          isCurrentDevice: dev != null && dev == me,
        ),
      );
    }
    list.sort((a, b) {
      final am = a.modified ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bm = b.modified ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bm.compareTo(am);
    });
    return list;
  }

  Future<String> downloadFromWebDavPath(
    BackupTarget target,
    String path,
  ) async {
    final client = _client(target);
    final bytes = await client.read(path);
    return utf8.decode(bytes);
  }

  /// 列出 [path] 下的子文件夹（供文件夹选择器浏览）。失败返回空列表。
  Future<List<WebDavFolder>> listDirectories(
    BackupTarget target,
    String path,
  ) async {
    final client = _client(target);
    final dir = normalizeDir(path);
    List<webdav.File> files;
    try {
      files = await client.readDir(dir);
    } catch (_) {
      return const [];
    }
    final folders = <WebDavFolder>[];
    for (final f in files) {
      if (!(f.isDir ?? false)) continue;
      final name = f.name ?? '';
      final rawPath = f.path ?? '$dir/$name';
      final normalized = normalizeDir(rawPath);
      if (normalized.isEmpty) continue;
      folders.add(WebDavFolder(name: name, path: normalized));
    }
    folders.sort((a, b) => a.name.compareTo(b.name));
    return folders;
  }

  Future<void> _pruneWebDav(
    webdav.Client client,
    String dir,
    String deviceId, {
    required int keep,
  }) async {
    try {
      final files = await client.readDir(dir);
      final mine =
          files.where((f) {
            final n = f.name ?? '';
            return !(f.isDir ?? false) &&
                n.startsWith('fnmusic_backup__${deviceId}__') &&
                n.endsWith('.json');
          }).toList()
            ..sort((a, b) {
              final am = a.mTime ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bm = b.mTime ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bm.compareTo(am);
            });
      for (var i = keep; i < mine.length; i++) {
        final path = mine[i].path;
        if (path != null) {
          try {
            await client.remove(path);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // ---- backup targets ----

  Future<List<BackupTarget>> loadTargets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsTargetsKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => BackupTarget.fromJson(e.cast<String, dynamic>()))
              .where((BackupTarget t) => t.endpoint.trim().isNotEmpty)
              .toList();
        }
      } catch (_) {}
      return const [];
    }
    return const [];
  }

  Future<void> saveTargets(List<BackupTarget> targets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsTargetsKey,
      jsonEncode(targets.map((BackupTarget e) => e.toJson()).toList()),
    );
  }

  Future<List<BackupTarget>> addTarget(BackupTarget target) async {
    final list = await loadTargets();
    final next = <BackupTarget>[
      ...list.where(
        (BackupTarget t) =>
            !(t.endpoint.trim() == target.endpoint.trim() &&
                normalizeDir(t.path) == normalizeDir(target.path)),
      ),
      target.copyWith(path: normalizeDir(target.path)),
    ];
    await saveTargets(next);
    return next;
  }

  Future<List<BackupTarget>> updateTargetAt(
    int index,
    BackupTarget target,
  ) async {
    final list = await loadTargets();
    if (index < 0 || index >= list.length) return list;
    final next = <BackupTarget>[...list];
    next[index] = target.copyWith(path: normalizeDir(target.path));
    await saveTargets(next);
    return next;
  }

  Future<List<BackupTarget>> removeTargetAt(int index) async {
    final list = await loadTargets();
    if (index < 0 || index >= list.length) return list;
    final next = <BackupTarget>[...list]..removeAt(index);
    await saveTargets(next);
    return next;
  }

  // ---- 自动备份配置 ----

  Future<bool> loadAutoEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsAutoEnabled) ?? false;
  }

  Future<void> setAutoEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAutoEnabled, v);
  }

  Future<int> loadKeepCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsAutoKeepCount) ?? defaultKeepCount;
  }

  Future<void> setKeepCount(int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsAutoKeepCount, v);
  }

  static bool _hasRunAutoBackupThisSession = false;

  /// 启动时自动备份：每天首次打开 App 时向所有已配置目标上传一次。
  ///
  /// 用「自然日」判断，一天最多一次；失败静默，但只有至少一个目标成功
  /// 才推进「上次备份日期」。
  Future<void> maybeAutoBackupOnLaunch() async {
    if (_hasRunAutoBackupThisSession) return;
    _hasRunAutoBackupThisSession = true;

    final enabled = await loadAutoEnabled();
    if (!enabled) return;
    final sections = await loadSections();
    if (!sections.any) return;
    final targets = await loadTargets();
    if (targets.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final todayKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    if (prefs.getString(_prefsAutoLastMs) == todayKey) return;

    final results = await uploadToAllTargets(targets, sections);
    if (results.any((BackupUploadResult r) => r.ok)) {
      await prefs.setString(_prefsAutoLastMs, todayKey);
    }
  }
}
