import '../stats_service.dart';
import 'report_snapshot.dart';

/// 把 [ReportSnapshot] 渲染为自包含 HTML（内联 CSS，深色主题）。
///
/// 纯函数、无 IO，供听歌报告 WebView 加载与单元测试。
class ReportHtmlBuilder {
  ReportHtmlBuilder._();

  static const String appName = 'FnMusic';

  static String build(ReportSnapshot snapshot) {
    final buf = StringBuffer()
      ..writeln('<!DOCTYPE html>')
      ..writeln('<html lang="zh-CN">')
      ..writeln('<head>')
      ..writeln('<meta charset="utf-8">')
      ..writeln(
          '<meta name="viewport" content="width=device-width, initial-scale=1">')
      ..writeln('<title>听歌报告 · $appName</title>')
      ..writeln('<style>')
      ..writeAll(_css(), '\n')
      ..writeln('')
      ..writeln('</style>')
      ..writeln('</head>')
      ..writeln('<body>')
      ..write(_hero(snapshot))
      ..write(_monthlySection(snapshot))
      ..write(_topSongsSection(snapshot))
      ..write(_recentSection(snapshot))
      ..write(_footer(snapshot))
      ..writeln('</body>')
      ..writeln('</html>');
    return buf.toString();
  }

  // ---- 区块 ----

  static String _hero(ReportSnapshot s) {
    final totals = s.totals;
    return _block(<String>[
      '<div class="hero">',
      '<div class="hero-title">听歌报告</div>',
      '<div class="hero-sub">$appName · ${_fmtDate(s.generatedAt)}</div>',
      '<div class="stats">',
      _statCard('累计收听', _fmtDuration(totals.totalListenMs)),
      _statCard('播放次数', '${totals.totalPlayCount}'),
      _statCard('收听天数', '${totals.totalDays}'),
      _statCard('听过的歌', '${totals.totalSongs}'),
      '</div>',
      '</div>',
    ]);
  }

  static String _monthlySection(ReportSnapshot s) {
    final months = s.monthly;
    final maxMs = months.fold<int>(0, (m, d) => d.listenMs > m ? d.listenMs : m);
    final lines = <String>[
      '<div class="section">',
      '<div class="section-title">近 12 个月收听趋势</div>',
      '<div class="bars">',
    ];
    for (final d in months) {
      final pct = maxMs == 0 ? 0 : (d.listenMs * 100 / maxMs).clamp(1, 100);
      final label = d.dayKey.length >= 7 ? d.dayKey.substring(5) : d.dayKey;
      final tooltip = '${d.dayKey} · ${_fmtDuration(d.listenMs)} · ${d.playCount} 次';
      lines.add('<div class="bar-col">');
      lines.add('  <div class="bar" style="height:${pct.toStringAsFixed(1)}%" '
          'title="$tooltip"></div>');
      lines.add('  <div class="bar-label">$label</div>');
      lines.add('</div>');
    }
    lines.addAll(const <String>['</div>', '</div>']);
    return _block(lines);
  }

  static String _topSongsSection(ReportSnapshot s) {
    final lines = <String>[
      '<div class="section">',
      '<div class="section-title">最常播放</div>',
    ];
    if (s.topSongs.isEmpty) {
      lines.add('<div class="empty">还没有播放记录，去听首歌吧</div>');
    } else {
      for (var i = 0; i < s.topSongs.length; i++) {
        lines.add(_songRow(i + 1, s.topSongs[i]));
      }
    }
    lines.add('</div>');
    return _block(lines);
  }

  static String _recentSection(ReportSnapshot s) {
    final lines = <String>[
      '<div class="section">',
      '<div class="section-title">最近播放</div>',
      '<div class="two-col">',
      '<div class="col">',
      '<div class="col-title">歌曲</div>',
    ];
    if (s.recentSongs.isEmpty) {
      lines.add('<div class="empty">暂无</div>');
    } else {
      for (final song in s.recentSongs) {
        lines.add('<div class="mini">${_esc(song.songTitle)}'
            '<span class="muted"> · ${_esc(song.artist)}</span></div>');
      }
    }
    lines.addAll(const <String>['</div>', '<div class="col">', '<div class="col-title">专辑 / 歌单</div>']);
    if (s.recentAlbums.isEmpty && s.recentPlaylists.isEmpty) {
      lines.add('<div class="empty">暂无</div>');
    } else {
      for (final album in s.recentAlbums) {
        lines.add('<div class="mini">${_esc(album.albumTitle)}'
            '<span class="muted"> · ${_esc(album.artist)}</span></div>');
      }
      for (final pl in s.recentPlaylists) {
        lines.add('<div class="mini">${_esc(pl.playlistTitle)}'
            '<span class="muted"> · 歌单</span></div>');
      }
    }
    lines.addAll(const <String>['</div>', '</div>', '</div>']);
    return _block(lines);
  }

  static String _footer(ReportSnapshot s) {
    return '<div class="footer">$appName · 生成于 '
        '${_fmtDate(s.generatedAt)} ${_fmtTime(s.generatedAt)}</div>';
  }

  static String _songRow(int rank, SongListeningStat song) {
    return '<div class="row">'
        '<div class="rank">$rank</div>'
        '<div class="row-main">'
        '<div class="row-title">${_esc(song.songTitle)}</div>'
        '<div class="row-sub">${_esc(song.artist)}</div>'
        '</div>'
        '<div class="row-stat">${_fmtDuration(song.listenMs)}<br>'
        '<span class="muted">${song.playCount} 次</span></div>'
        '</div>';
  }

  static String _statCard(String label, String value) {
    return '<div class="stat"><div class="stat-value">$value</div>'
        '<div class="stat-label">$label</div></div>';
  }

  // ---- 工具 ----

  static String _block(List<String> lines) => lines.join('\n');

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  static String _fmtDuration(int ms) {
    final seconds = (ms / 1000).round();
    if (seconds < 60) return '$seconds 秒';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes 分钟';
    final hours = minutes ~/ 60;
    final rem = minutes % 60;
    return rem == 0 ? '$hours 小时' : '$hours 小时 $rem 分钟';
  }

  static String _fmtDate(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }

  static String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  static List<String> _css() => <String>[
        '* { margin: 0; padding: 0; box-sizing: border-box; }',
        'body { background: #121212; color: #e6e6e6; font-family: '
            '-apple-system, "PingFang SC", "Noto Sans CJK SC", '
            '"Microsoft YaHei", sans-serif; padding: 20px 16px 40px; '
            'max-width: 720px; margin: 0 auto; }',
        '.hero { background: linear-gradient(160deg, #1e1e2e, #2a2a3e); '
            'border-radius: 20px; padding: 28px 22px; margin-bottom: 24px; }',
        '.hero-title { font-size: 26px; font-weight: 800; '
            'letter-spacing: 1px; }',
        '.hero-sub { margin-top: 6px; font-size: 13px; color: #9a9ab0; }',
        '.stats { display: flex; flex-wrap: wrap; gap: 12px; '
            'margin-top: 20px; }',
        '.stat { flex: 1 1 40%; background: rgba(255,255,255,0.06); '
            'border-radius: 14px; padding: 14px 12px; text-align: center; }',
        '.stat-value { font-size: 22px; font-weight: 700; '
            'color: #ffb454; }',
        '.stat-label { margin-top: 4px; font-size: 12px; color: #9a9ab0; }',
        '.section { background: #1c1c1c; border-radius: 16px; padding: 18px; '
            'margin-bottom: 16px; }',
        '.section-title { font-size: 15px; font-weight: 700; '
            'margin-bottom: 16px; color: #cfcfcf; }',
        '.bars { display: flex; align-items: flex-end; gap: 6px; '
            'height: 140px; }',
        '.bar-col { flex: 1; display: flex; flex-direction: column; '
            'align-items: center; height: 100%; }',
        '.bar { width: 100%; max-width: 26px; background: linear-gradient(180deg, '
            '#ffb454, #e07a3f); border-radius: 6px 6px 2px 2px; '
            'min-height: 4px; margin-top: auto; }',
        '.bar-label { margin-top: 6px; font-size: 10px; color: #7a7a8a; }',
        '.row { display: flex; align-items: center; gap: 12px; '
            'padding: 10px 0; border-bottom: 1px solid rgba(255,255,255,0.05); }',
        '.rank { width: 22px; font-size: 15px; font-weight: 700; '
            'color: #ffb454; text-align: center; }',
        '.row-main { flex: 1; min-width: 0; }',
        '.row-title { font-size: 14px; white-space: nowrap; overflow: hidden; '
            'text-overflow: ellipsis; }',
        '.row-sub { margin-top: 2px; font-size: 12px; color: #8a8a9a; }',
        '.row-stat { text-align: right; font-size: 13px; color: #b8b8c8; }',
        '.muted { color: #8a8a9a; font-size: 12px; }',
        '.two-col { display: flex; gap: 24px; }',
        '.col { flex: 1; min-width: 0; }',
        '.col-title { font-size: 12px; color: #9a9ab0; margin-bottom: 10px; }',
        '.mini { font-size: 13px; margin-bottom: 8px; white-space: nowrap; '
            'overflow: hidden; text-overflow: ellipsis; }',
        '.empty { color: #6a6a7a; font-size: 13px; padding: 8px 0; }',
        '.footer { text-align: center; color: #5a5a6a; font-size: 11px; '
            'margin-top: 8px; }',
      ];
}
