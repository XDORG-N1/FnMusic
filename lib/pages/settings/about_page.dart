import 'package:flutter/material.dart';

import '../../app/utils/app_info.dart';

/// 关于页：版本、说明与开源声明。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String route = '/settings/about';

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: <Widget>[
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(Icons.music_note,
                  size: 48, color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              AppInfo.displayName,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '版本 ${AppInfo.version}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 32),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('飞牛 NAS 音乐客户端'),
            subtitle: const Text('连接你的飞牛 NAS，在线流媒体播放'),
          ),
          const ListTile(
            leading: Icon(Icons.groups_outlined),
            title: Text('研发团队'),
            subtitle: Text('XDORG'),
          ),
          const ListTile(
            leading: Icon(Icons.code_outlined),
            title: Text('开源声明'),
            subtitle: Text('本应用由 XDORG 自主研发，基于 Apache-2.0 协议开源'),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('目标平台'),
            subtitle: const Text('Android 15+（minSdk 35）'),
          ),
        ],
      ),
    );
  }
}
