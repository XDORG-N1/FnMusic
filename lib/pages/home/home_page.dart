import 'package:flutter/material.dart';

/// 首页（P0 占位版）。
/// P1-P2 填充：漫游入口、收藏、最近播放、歌单、横幅、快捷操作等。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('飞牛音乐')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.music_note, size: 64, color: scheme.primary),
            const SizedBox(height: 16),
            Text('连接你的飞牛 NAS', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '首页内容将在后续阶段填充',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
