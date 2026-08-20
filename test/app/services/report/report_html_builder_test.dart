import 'package:flutter_test/flutter_test.dart';
import 'package:fnmusic/app/services/report/report_html_builder.dart';
import 'package:fnmusic/app/services/report/report_snapshot.dart';
import 'package:fnmusic/app/services/stats_service.dart';

void main() {
  group('ReportHtmlBuilder', () {
    test('空数据：包含标题与空态提示', () {
      final html = ReportHtmlBuilder.build(_emptySnapshot());

      expect(html, contains('听歌报告'));
      expect(html, contains('近 12 个月收听趋势'));
      expect(html, contains('还没有播放记录，去听首歌吧'));
      expect(html, contains('累计收听'));
      expect(html, contains('0 秒'));
    });

    test('含数据：渲染统计值、月度与歌曲', () {
      final html = ReportHtmlBuilder.build(_sampleSnapshot());

      expect(html, contains('3 小时'));
      expect(html, contains('128'));
      expect(html, contains('>歌名</div>'));
      expect(html, contains('>歌手</div>'));
      // 月份标签（MM 形式）
      expect(html, contains('>06</div>'));
      expect(html, contains('>01</div>'));
    });

    test('HTML 转义：标题中的特殊字符不破坏文档', () {
      final html = ReportHtmlBuilder.build(_sampleSnapshot(
        title: '<script>alert(1)</script> & " 单\'引',
      ));

      expect(html, contains('&lt;script&gt;'));
      expect(html, isNot(contains('<script>alert')));
      expect(html, contains('&amp;'));
      expect(html, contains('&quot;'));
    });

    test('时长格式化：秒/分钟/小时', () {
      expect(ReportHtmlBuilder.build(_emptySnapshot(
        totals: const StatsTotals(
          totalListenMs: 30 * 1000,
          totalPlayCount: 0,
          totalDays: 0,
          totalSongs: 0,
        ),
      )), contains('30 秒'));

      expect(ReportHtmlBuilder.build(_emptySnapshot(
        totals: const StatsTotals(
          totalListenMs: 45 * 60 * 1000,
          totalPlayCount: 0,
          totalDays: 0,
          totalSongs: 0,
        ),
      )), contains('45 分钟'));

      expect(ReportHtmlBuilder.build(_emptySnapshot(
        totals: const StatsTotals(
          totalListenMs: (2 * 3600 + 5 * 60) * 1000,
          totalPlayCount: 0,
          totalDays: 0,
          totalSongs: 0,
        ),
      )), contains('2 小时 5 分钟'));
    });
  });
}

ReportSnapshot _emptySnapshot({StatsTotals? totals}) {
  return ReportSnapshot(
    totals: totals ??
        const StatsTotals(
          totalListenMs: 0,
          totalPlayCount: 0,
          totalDays: 0,
          totalSongs: 0,
        ),
    monthly: _months(0),
    topSongs: const [],
    recentSongs: const [],
    recentAlbums: const [],
    recentPlaylists: const [],
    generatedAt: DateTime(2026, 8, 20, 15, 30),
  );
}

ReportSnapshot _sampleSnapshot({String title = '歌名', String artist = '歌手'}) {
  return ReportSnapshot(
    totals: const StatsTotals(
      totalListenMs: (3 * 3600) * 1000,
      totalPlayCount: 128,
      totalDays: 40,
      totalSongs: 15,
    ),
    monthly: _months(60),
    topSongs: <SongListeningStat>[
      SongListeningStat(
        songId: 's1',
        songTitle: title,
        artist: artist,
        coverId: '',
        listenMs: 180 * 1000,
        playCount: 12,
        lastPlayedAt: 0,
      ),
    ],
    recentSongs: <SongListeningStat>[
      SongListeningStat(
        songId: 's1',
        songTitle: title,
        artist: artist,
        coverId: '',
        listenMs: 0,
        playCount: 1,
        lastPlayedAt: 0,
      ),
    ],
    recentAlbums: const <AlbumPlaybackStat>[
      AlbumPlaybackStat(
        albumId: 'a1',
        albumTitle: '专辑A',
        artist: '歌手',
        coverId: '',
        playCount: 3,
        lastPlayedAt: 0,
      ),
    ],
    recentPlaylists: const <PlaylistPlaybackStat>[
      PlaylistPlaybackStat(
        playlistId: 'p1',
        playlistTitle: '歌单B',
        playCount: 2,
        lastPlayedAt: 0,
      ),
    ],
    generatedAt: DateTime(2026, 8, 20, 15, 30),
  );
}

/// 生成最近 12 个月的日统计（从当前月倒推）。
List<DayListeningStat> _months(int listenMs) {
  final now = DateTime(2026, 8, 20);
  final result = <DayListeningStat>[];
  for (var i = 11; i >= 0; i--) {
    final m = DateTime(now.year, now.month - i);
    result.add(
      DayListeningStat(
        dayKey: '${m.year}-${m.month.toString().padLeft(2, '0')}',
        listenMs: listenMs,
        playCount: listenMs ~/ 1000,
      ),
    );
  }
  return result;
}
