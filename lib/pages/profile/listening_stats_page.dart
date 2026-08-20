import 'package:flutter/material.dart';

import '../../app/services/feiniu/api_client.dart';
import '../../app/services/feiniu/api_models.dart';
import '../../app/services/feiniu/track_service.dart';
import '../../app/services/player_service.dart';
import '../../app/services/stats_service.dart';
import '../../app/state/song_state.dart';
import '../../components/list/media_list_tile.dart';

/// 听歌统计：总览 + 按月视图 + 热门歌曲 + 最近播放。
class ListeningStatsPage extends StatefulWidget {
  const ListeningStatsPage({super.key});

  static const String route = '/profile/listening-stats';

  @override
  State<ListeningStatsPage> createState() => _ListeningStatsPageState();
}

class _ListeningStatsPageState extends State<ListeningStatsPage> {
  late int _year;
  late int _month;
  bool _refreshing = false;
  _StatsData? _data;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _load();
  }

  Future<void> _load() async {
    setState(() => _refreshing = true);
    try {
      final StatsTotals totals = await StatsService.instance.fetchTotalStats();
      final List<SongListeningStat> top =
          await StatsService.instance.fetchTopSongs(limit: 10);
      final List<SongListeningStat> recent =
          await StatsService.instance.fetchRecentSongs(limit: 10);
      final List<DayListeningStat> month =
          await StatsService.instance.fetchMonthStats(year: _year, month: _month);
      if (!mounted) return;
      setState(() {
        _data = _StatsData(totals: totals, top: top, recent: recent, month: month);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('统计加载失败：$e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _changeMonth(int delta) {
    int year = _year;
    int month = _month + delta;
    if (month < 1) {
      month = 12;
      year -= 1;
    } else if (month > 12) {
      month = 1;
      year += 1;
    }
    setState(() {
      _year = year;
      _month = month;
    });
    _load();
  }

  Future<void> _playSong(SongListeningStat stat) async {
    try {
      final FnTrack track =
          await FnTrackService.instance.fetchTrackDetail(stat.songId);
      await FnPlayerService.instance.playSong(SongEntity.fromTrack(track));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('播放失败：$e'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('听歌统计'),
        actions: <Widget>[
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: _load,
            ),
        ],
      ),
      body: _data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: <Widget>[
                _TotalsSection(data: _data!),
                _MonthSection(
                  year: _year,
                  month: _month,
                  days: _data!.month,
                  onPrev: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                ),
                _SongSection(
                  title: '热门歌曲',
                  icon: Icons.trending_up,
                  songs: _data!.top,
                  onTap: _playSong,
                ),
                _SongSection(
                  title: '最近播放',
                  icon: Icons.history,
                  songs: _data!.recent,
                  onTap: _playSong,
                ),
              ],
            ),
    );
  }
}

class _StatsData {
  const _StatsData({
    required this.totals,
    required this.top,
    required this.recent,
    required this.month,
  });

  final StatsTotals totals;
  final List<SongListeningStat> top;
  final List<SongListeningStat> recent;
  final List<DayListeningStat> month;
}

/// 时长展示：>=1 小时显示「x 小时 y 分钟」，否则「x 分钟」。
String formatDurationMs(int ms) {
  final int totalMinutes = (ms / 60000).round();
  if (totalMinutes >= 60) {
    return '${totalMinutes ~/ 60} 小时 ${totalMinutes % 60} 分钟';
  }
  return '$totalMinutes 分钟';
}

class _TotalsSection extends StatelessWidget {
  const _TotalsSection({required this.data});

  final _StatsData data;

  @override
  Widget build(BuildContext context) {
    final StatsTotals t = data.totals;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: <Widget>[
          _MetricCard(label: '累计收听', value: formatDurationMs(t.totalListenMs)),
          _MetricCard(label: '播放次数', value: '${t.totalPlayCount}'),
          _MetricCard(label: '收听天数', value: '${t.totalDays}'),
          _MetricCard(label: '听歌数', value: '${t.totalSongs}'),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            children: <Widget>[
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthSection extends StatelessWidget {
  const _MonthSection({
    required this.year,
    required this.month,
    required this.days,
    required this.onPrev,
    required this.onNext,
  });

  final int year;
  final int month;
  final List<DayListeningStat> days;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    int monthListenMs = 0;
    int monthPlayCount = 0;
    for (final DayListeningStat d in days) {
      monthListenMs += d.listenMs;
      monthPlayCount += d.playCount;
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: onPrev,
                  tooltip: '上一月',
                ),
                Expanded(
                  child: Text(
                    '$year-${month.toString().padLeft(2, '0')}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: onNext,
                  tooltip: '下一月',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                _MonthMetric('收听', formatDurationMs(monthListenMs)),
                _MonthMetric('次数', '$monthPlayCount'),
                _MonthMetric('活跃天数', '${days.length}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthMetric extends StatelessWidget {
  const _MonthMetric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: scheme.primary),
        ),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _SongSection extends StatelessWidget {
  const _SongSection({
    required this.title,
    required this.icon,
    required this.songs,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final List<SongListeningStat> songs;
  final void Function(SongListeningStat) onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (songs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
        for (final SongListeningStat s in songs)
          MediaListTile(
            imageUrl: ApiClient.instance.coverUrl(s.coverId),
            title: s.songTitle,
            subtitle: s.artist,
            onTap: () => onTap(s),
            trailing: Text(
              '${s.playCount} 次',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
