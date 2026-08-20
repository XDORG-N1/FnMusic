import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../state/song_state.dart';
import '../feiniu/api_client.dart';
import 'player_engine.dart';

/// 缓存条目（纯数据）：供 LRU 淘汰决策使用。
class CacheEntry {
  final int sizeBytes;
  final int lastAccessedMs;

  const CacheEntry({required this.sizeBytes, required this.lastAccessedMs});
}

/// 流缓存服务（单例）：把整首曲目下载到本地，二次播放零流量。
///
/// - 目录：`<appSupport>/stream_cache/`，文件名 `<songId>.<format>`；
/// - **LRU 淘汰**：超过 [maxCacheMb] 上限后按最后访问时间淘汰最久未用的文件，
///   决策逻辑 [selectEvictions] 为纯函数，可单测；
/// - CUE 整轨曲目跳过缓存（各曲目共享同一物理文件，缓存整轨无意义）。
class StreamCacheService {
  StreamCacheService._();

  static final StreamCacheService instance = StreamCacheService._();

  /// 缓存开关（设置页可关闭；P3 默认开）。
  bool enabled = true;

  /// 缓存上限（MB）。
  int maxCacheMb = 1024;

  Directory? _dir;

  Future<Directory> _ensureDir() async {
    final Directory? cached = _dir;
    if (cached != null) return cached;
    final Directory base = await getApplicationSupportDirectory();
    final Directory dir = Directory(p.join(base.path, 'stream_cache'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _dir = dir;
  }

  /// 缓存文件路径（`<songId>.<format>`）。
  Future<String?> filePathFor(SongEntity song) async {
    final String guid = song.guid;
    if (guid.isEmpty) return null;
    final String ext = song.format?.toLowerCase() ?? 'bin';
    return p.join((await _ensureDir()).path, '$guid.$ext');
  }

  /// 若整首已缓存且文件完整，返回其缓存键。
  Future<String?> cachedKeyFor(SongEntity song) async {
    final String? path = await filePathFor(song);
    if (path == null) return null;
    final File file = File(path);
    if (!file.existsSync() || file.lengthSync() == 0) return null;
    return file.absolute.path;
  }

  /// 为 [song] 构造播放源：命中缓存 → 本地文件；未命中 → 在线流地址。
  ///
  /// 返回 null 表示无法播放（无流地址）。
  Future<PlayerSource?> sourceFor(
    SongEntity song, {
    Duration? start,
    Duration? end,
  }) async {
    final String? cachePath = await cachedKeyFor(song);
    if (cachePath != null) {
      return PlayerSource(uri: cachePath, start: start, end: end);
    }
    final String? url = ApiClient.instance.streamUrl(song.guid);
    if (url == null) return null;
    return PlayerSource(
      uri: url,
      headers: ApiClient.instance.authHeaders(),
      start: start,
      end: end,
    );
  }

  /// 后台下载整首到缓存（fire-and-forget，失败静默忽略）。
  ///
  /// CUE 整轨曲目跳过（整轨缓存无意义）。
  Future<void> cacheSong(SongEntity song) async {
    if (!enabled) return;
    if (song.isCue) return;
    final String? path = await filePathFor(song);
    final String? url = ApiClient.instance.streamUrl(song.guid);
    if (path == null || url == null) return;
    final File file = File(path);
    if (file.existsSync() && file.lengthSync() > 0) return;

    final String tmp = '$path.downloading';
    try {
      await ApiClient.instance.downloadToFile(url, tmp);
      final File tmpFile = File(tmp);
      if (tmpFile.existsSync() && tmpFile.lengthSync() > 0) {
        tmpFile.renameSync(path);
      } else {
        _tryDelete(tmpFile);
      }
      await _evictIfNeeded();
    } catch (_) {
      _tryDelete(File(tmp));
    }
  }

  /// 静默删除（文件不存在 / 被占用时忽略）。
  static void _tryDelete(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  /// 超过上限时淘汰最久未用的缓存文件。
  Future<void> _evictIfNeeded() async {
    final Directory dir = await _ensureDir();
    final List<File> entries = dir.listSync().whereType<File>().toList();
    if (entries.isEmpty) return;

    final Map<String, CacheEntry> index = <String, CacheEntry>{};
    for (final File f in entries) {
      index[f.absolute.path] = CacheEntry(
        sizeBytes: f.lengthSync(),
        lastAccessedMs: f.lastModifiedSync().millisecondsSinceEpoch,
      );
    }

    final List<String> toEvict = selectEvictions(
      entries: index,
      maxBytes: maxCacheMb * 1024 * 1024,
    );
    for (final String path in toEvict) {
      _tryDelete(File(path));
    }
  }

  /// LRU 淘汰决策（纯函数，可单测）。
  ///
  /// 总占用超过 [maxBytes] 时，按 `lastAccessedMs` 从旧到新逐条选出待删除键，
  /// 直到总占用不超过上限（保留至少一条，避免空目录反复扫描）。
  static List<String> selectEvictions({
    required Map<String, CacheEntry> entries,
    required int maxBytes,
  }) {
    if (entries.isEmpty) return const <String>[];
    final List<MapEntry<String, CacheEntry>> sorted = entries.entries.toList()
      ..sort((a, b) => a.value.lastAccessedMs.compareTo(b.value.lastAccessedMs));
    int total = 0;
    for (final MapEntry<String, CacheEntry> e in entries.entries) {
      total += e.value.sizeBytes;
    }
    final List<String> evict = <String>[];
    for (final MapEntry<String, CacheEntry> e in sorted) {
      if (total <= maxBytes) break;
      // 保留至少一条（sorted 非空且最后一条不淘汰）。
      if (evict.length >= sorted.length - 1) break;
      evict.add(e.key);
      total -= e.value.sizeBytes;
    }
    return evict;
  }

  /// 清空全部缓存。
  Future<void> clear() async {
    final Directory dir = await _ensureDir();
    for (final FileSystemEntity e in dir.listSync()) {
      try {
        e.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// 缓存占用总字节数（缓存管理页展示）。
  Future<int> totalSize() async {
    final Directory dir = await _ensureDir();
    int total = 0;
    for (final FileSystemEntity e in dir.listSync()) {
      if (e is File) {
        try {
          total += e.lengthSync();
        } catch (_) {}
      }
    }
    return total;
  }
}
