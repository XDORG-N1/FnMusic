import 'package:flutter/foundation.dart';

import '../../state/song_state.dart';
import 'album_service.dart';
import 'api_models.dart';

/// CUE 整轨曲目偏移服务（单例）。
///
/// 飞牛 NAS 对「整轨 + CUE 索引」的专辑按曲目拆分（`isCue: true`，多首曲目
/// 共享同一物理文件，`audioSpec.path` 相同），但 `/track/stream?guid=<曲目>`
/// 返回的是**整轨文件本身**，且响应里没有曲目起始偏移字段。因此客户端需在
/// **专辑上下文**内自行计算每首曲目在物理文件中的起始偏移：
///
/// 同一 `(album.guid, audioSpec.path)` 镜像内，按 `(discNo, trackNo)` 排序，
/// 起始偏移 = 前序曲目 `duration` 之和（含曲目间隙）。
///
/// - 专辑详情页已持有原始 [FnTrack]：用 [withCueOffsets] 直接 stamp，零网络。
/// - 单曲/搜索/收藏/漫游播放的 CUE 曲：用 [offsetMsFor] 按 `albumGuid` 拉一次
///   专辑曲目计算，结果缓存（TTL）并在并发调用间去重。
class FnCueService {
  FnCueService._();

  static final FnCueService instance = FnCueService._();

  static const Duration _ttl = Duration(minutes: 30);

  final Map<String, _AlbumCueCache> _cache = <String, _AlbumCueCache>{};
  final Map<String, Future<Map<String, int>>> _inflight =
      <String, Future<Map<String, int>>>{};

  /// 计算同一镜像内各 CUE 曲目的起始偏移（纯函数，可单测）。
  ///
  /// - 只处理 `isCue == true` 且 `audioSpec.path` 非空的曲目；
  /// - 按 `(album.guid, audioSpec.path)` 分组（同一物理文件 = 同一镜像）；
  /// - 组内按 `(discNo ?? 1, trackNo)` 排序，trackNo 缺失时回退到数组原始顺序
  ///   （以原始下标作最终比较键，弥补 `List.sort` 的不稳定性）；
  /// - 起始偏移 = 组内前序曲目 `duration` 之和；返回 `Map<guid, offsetMs>`。
  static Map<String, int> computeOffsets(List<FnTrack> tracks) {
    final Map<String, List<(int, FnTrack)>> groups =
        <String, List<(int, FnTrack)>>{};
    for (var i = 0; i < tracks.length; i++) {
      final FnTrack t = tracks[i];
      if (!t.isCue) continue;
      final String? path = t.audioSpec?.path;
      if (path == null || path.isEmpty) continue;
      final String key = '${t.album?.guid ?? ''}|$path';
      (groups[key] ??= <(int, FnTrack)>[]).add((i, t));
    }

    final Map<String, int> offsets = <String, int>{};
    for (final List<(int, FnTrack)> group in groups.values) {
      final List<(int, FnTrack)> sorted = List<(int, FnTrack)>.of(group)
        ..sort((a, b) {
          final FnTrack ta = a.$2;
          final FnTrack tb = b.$2;
          final int disc = (ta.discNo ?? 1).compareTo(tb.discNo ?? 1);
          if (disc != 0) return disc;
          final int trackNo = (ta.trackNo ?? 1 << 30)
              .compareTo(tb.trackNo ?? 1 << 30);
          if (trackNo != 0) return trackNo;
          return a.$1.compareTo(b.$1);
        });
      var cursor = 0;
      for (final (_, FnTrack t) in sorted) {
        offsets[t.guid] = cursor;
        cursor += t.duration ?? 0;
      }
    }
    return offsets;
  }

  /// 获取某首曲目在物理文件内的起始偏移（毫秒）。
  ///
  /// - 非 CUE 曲 → null；
  /// - 已 stamp（专辑上下文）→ 直接用；
  /// - 否则按 `albumGuid` 拉专辑曲目计算并缓存；网络失败 / 无 albumGuid →
  ///   返回 null（播放层不裁剪，保持现状容错）。
  Future<int?> offsetMsFor(SongEntity song) async {
    if (!song.isCue) return null;
    if (song.cueOffsetMs != null) return song.cueOffsetMs;

    final String? albumGuid = song.albumGuid;
    if (albumGuid == null || albumGuid.isEmpty) return null;

    final _AlbumCueCache? cached = _cache[albumGuid];
    if (cached != null && cached.isValid()) return cached.offsets[song.guid];

    // 并发调用复用同一个在途 Future。
    final Future<Map<String, int>>? inflight = _inflight[albumGuid];
    if (inflight != null) return (await inflight)[song.guid];

    final Future<Map<String, int>> future = () async {
      try {
        final List<FnTrack> tracks =
            await FnAlbumService.instance.fetchAlbumTracks(albumGuid);
        final Map<String, int> offsets = computeOffsets(tracks);
        _cache[albumGuid] =
            _AlbumCueCache(offsets, DateTime.now().add(_ttl));
        return offsets;
      } catch (_) {
        // 专辑拉取失败：无法计算偏移，按无偏移处理，不阻塞播放。
        return <String, int>{};
      }
    }();
    _inflight[albumGuid] = future;
    future.whenComplete(() => _inflight.remove(albumGuid));
    return (await future)[song.guid];
  }

  /// 用原始 [FnTrack] 列表为歌曲批量 stamp 偏移（专辑详情页零额外网络路径）。
  ///
  /// 只对命中镜像计算的 CUE 曲目改写 `isCue`/`cueOffsetMs`，其余原样返回。
  List<SongEntity> withCueOffsets(
    List<SongEntity> songs,
    List<FnTrack>? tracks,
  ) {
    if (tracks == null || tracks.isEmpty) return songs;
    final Map<String, int> offsets = computeOffsets(tracks);
    if (offsets.isEmpty) return songs;
    return songs
        .map((SongEntity s) {
          final int? off = offsets[s.guid];
          if (off == null) return s;
          return s.copyWith(isCue: true, cueOffsetMs: off);
        })
        .toList();
  }

  /// 清除某张专辑的偏移缓存（数据变化后强制刷新时调用）。
  void invalidate(String albumGuid) {
    _cache.remove(albumGuid);
    _inflight.remove(albumGuid);
  }

  @visibleForTesting
  void clearCacheForTest() {
    _cache.clear();
    _inflight.clear();
  }
}

/// 专辑 CUE 偏移缓存项：`Map<guid, offsetMs>` + 过期时间。
class _AlbumCueCache {
  final Map<String, int> offsets;
  final DateTime expiresAt;

  _AlbumCueCache(this.offsets, this.expiresAt);

  bool isValid() => DateTime.now().isBefore(expiresAt);
}
