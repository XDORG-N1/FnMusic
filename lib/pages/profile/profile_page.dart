import 'package:flutter/material.dart';

import '../../app/router/app_router.dart';
import 'listening_stats_page.dart';

/// 「我的」：资料库统计快捷入口 + 设置入口。
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: <Widget>[
          _ProfileEntry(
            icon: Icons.bar_chart,
            color: scheme.primary,
            title: '听歌统计',
            subtitle: '收听时长 · 播放次数 · 热门歌曲',
            onTap: () => Navigator.of(context).pushNamed(ListeningStatsPage.route),
          ),
        ],
      ),
    );
  }
}

class _ProfileEntry extends StatelessWidget {
  const _ProfileEntry({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
