import '../stats_service.dart';

/// 听歌报告的数据快照（纯数据，供 HTML 构建器消费）。
class ReportSnapshot {
  final StatsTotals totals;
  final List<DayListeningStat> monthly;
  final List<SongListeningStat> topSongs;
  final List<SongListeningStat> recentSongs;
  final List<AlbumPlaybackStat> recentAlbums;
  final List<PlaylistPlaybackStat> recentPlaylists;
  final DateTime generatedAt;

  const ReportSnapshot({
    required this.totals,
    required this.monthly,
    required this.topSongs,
    required this.recentSongs,
    required this.recentAlbums,
    required this.recentPlaylists,
    required this.generatedAt,
  });
}

/// 从 [StatsService] 聚合听歌报告数据。
class ReportSnapshotBuilder {
  final StatsService _stats;

  ReportSnapshotBuilder({StatsService? stats})
      : _stats = stats ?? StatsService.instance;

  /// 聚合最近 12 个月逐月收听 + TOP/最近播放，可能耗时（多次 DB 查询）。
  Future<ReportSnapshot> build() async {
    final now = DateTime.now();
    final totals = await _stats.fetchTotalStats();

    final monthly = <DayListeningStat>[];
    for (var i = 11; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i);
      final rows = await _stats.fetchMonthStats(year: m.year, month: m.month);
      final listenMs = rows.fold<int>(0, (sum, r) => sum + r.listenMs);
      final playCount = rows.fold<int>(0, (sum, r) => sum + r.playCount);
      monthly.add(
        DayListeningStat(
          dayKey: '${m.year}-${m.month.toString().padLeft(2, '0')}',
          listenMs: listenMs,
          playCount: playCount,
        ),
      );
    }

    return ReportSnapshot(
      totals: totals,
      monthly: monthly,
      topSongs: await _stats.fetchTopSongs(limit: 20),
      recentSongs: await _stats.fetchRecentSongs(limit: 10),
      recentAlbums: await _stats.fetchRecentAlbums(limit: 6),
      recentPlaylists: await _stats.fetchRecentPlaylists(limit: 6),
      generatedAt: now,
    );
  }
}
