/// 本地 SQLite 常量。
///
/// FnMusic 仅依赖 5 张统计/报告表：歌曲元数据来自服务端 API，
/// 故不建 songs 全量表（参考项目在此建了整张 songs 表，其 [SongEntity]
/// 带 toMap 且歌曲可离线编辑；我们只记录统计所需显示列）。
class DbConstants {
  DbConstants._();

  static const String dbName = 'fnmusic.db';
  static const int dbVersion = 1;

  /// 按日累计收听时长/次数（统计页总览）。
  static const String tableListeningDays = 'listening_days';

  /// 单曲累计收听（听歌统计 / 最近播放）。
  static const String tableSongStats = 'song_stats';

  /// 专辑播放记录（最近播放专辑 / 专辑热度）。
  static const String tableAlbumStats = 'album_stats';

  /// 歌单播放记录（最近播放歌单）。
  static const String tablePlaylistStats = 'playlist_stats';

  /// 听歌行为流水（report_events，供导出/报告，90 天窗口）。
  static const String tableReportEvents = 'report_events';

  /// 听歌报告保留窗口（天）。
  static const int reportEventRetentionDays = 90;
}
