import 'package:flutter/material.dart';

/// 文件夹视图（P2 占位）。
/// 完整版依赖 FnMusicEnhance companion 服务（`{baseUrl}/music-enhance/folder/list`）。
class FoldersPage extends StatelessWidget {
  const FoldersPage({super.key});

  static const String route = '/library/folders';

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('文件夹')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.folder_outlined, size: 56, color: scheme.primary),
            const SizedBox(height: 12),
            Text('文件夹视图', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '需要 FnMusicEnhance 服务端插件支持',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
