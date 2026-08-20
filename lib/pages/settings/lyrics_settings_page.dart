import 'package:flutter/material.dart';

import '../../app/services/lyrics/lyrics_service.dart';

/// 歌词设置：强制逐字卡拉OK + 自定义歌词配色。
class LyricsSettingsPage extends StatefulWidget {
  const LyricsSettingsPage({super.key});

  static const String route = '/settings/lyrics';

  @override
  State<LyricsSettingsPage> createState() => _LyricsSettingsPageState();
}

class _LyricsSettingsPageState extends State<LyricsSettingsPage> {
  bool _forceKaraoke = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await LyricsService.instance.refreshSettings();
    if (!mounted) return;
    setState(() => _forceKaraoke = LyricsService.instance.forceKaraoke);
  }

  Future<void> _pickColor({
    required String title,
    required ValueNotifier<int?> notifier,
  }) async {
    final int? picked = await showDialog<int?>(
      context: context,
      builder: (BuildContext context) => _ColorPickerDialog(
        title: title,
        initial: notifier.value,
      ),
    );
    if (picked == null) return;
    if (picked == _ColorPickerDialog.kFollowTheme) {
      await LyricsService.instance.clearViewColors();
    } else {
      if (identical(notifier, LyricsService.instance.viewInactiveColor)) {
        await LyricsService.instance.setViewColors(inactive: picked);
      } else if (identical(
          notifier, LyricsService.instance.viewActiveColor)) {
        await LyricsService.instance.setViewColors(active: picked);
      } else {
        await LyricsService.instance.setViewColors(highlight: picked);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('歌词设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: <Widget>[
          _SectionHeader('歌词样式'),
          SwitchListTile(
            secondary: const Icon(Icons.format_quote_outlined),
            title: const Text('强制逐字卡拉OK'),
            subtitle: const Text('当前行按字高亮，逐字填充动画'),
            value: _forceKaraoke,
            onChanged: (bool value) async {
              setState(() => _forceKaraoke = value);
              await LyricsService.instance.setForceKaraoke(value);
            },
          ),
          _SectionHeader('歌词配色'),
          ValueListenableBuilder<int?>(
            valueListenable: LyricsService.instance.viewInactiveColor,
            builder: (BuildContext context, int? color, _) {
              return _ColorTile(
                title: '未高亮歌词',
                subtitle: '未播放到行的默认颜色',
                color: color,
                onTap: () => _pickColor(
                  title: '未高亮歌词',
                  notifier: LyricsService.instance.viewInactiveColor,
                ),
              );
            },
          ),
          ValueListenableBuilder<int?>(
            valueListenable: LyricsService.instance.viewActiveColor,
            builder: (BuildContext context, int? color, _) {
              return _ColorTile(
                title: '当前行歌词',
                subtitle: '当前播放行的主色',
                color: color,
                onTap: () => _pickColor(
                  title: '当前行歌词',
                  notifier: LyricsService.instance.viewActiveColor,
                ),
              );
            },
          ),
          ValueListenableBuilder<int?>(
            valueListenable: LyricsService.instance.viewHighlightColor,
            builder: (BuildContext context, int? color, _) {
              return _ColorTile(
                title: '逐字高亮',
                subtitle: '逐字卡拉OK填充色（开启强制逐字时生效）',
                color: color,
                onTap: () => _pickColor(
                  title: '逐字高亮',
                  notifier: LyricsService.instance.viewHighlightColor,
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Text(
              '配色为空时跟随主题色。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _ColorTile extends StatelessWidget {
  const _ColorTile({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final int? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color == null ? null : Color(color!),
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: color == null
            ? Icon(Icons.auto_awesome,
                size: 16, color: Theme.of(context).colorScheme.outline)
            : null,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// 歌词配色选择对话框。返回 null = 取消；[kFollowTheme] = 恢复跟随主题。
class _ColorPickerDialog extends StatelessWidget {
  const _ColorPickerDialog({required this.title, required this.initial});

  static const int kFollowTheme = -1;

  final String title;
  final int? initial;

  static const List<int> _presets = <int>[
    0xFFFFFFFF, // 白
    0xFF000000, // 黑
    0xFFFF5252, // 红
    0xFFFF7043, // 橙
    0xFFFFC107, // 琥珀
    0xFFCDDC39, // 黄绿
    0xFF66BB6A, // 绿
    0xFF26A69A, // 青
    0xFF29B6F6, // 浅蓝
    0xFF5C6BC0, // 靛蓝
    0xFFAB47BC, // 紫
    0xFFEC407A, // 粉
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _presets.map((int c) {
              return InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => Navigator.of(context).pop(c),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: initial == c
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: 3,
                    ),
                  ),
                  child: initial == c
                      ? const Icon(Icons.check, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.auto_awesome),
              label: const Text('跟随主题'),
              onPressed: () => Navigator.of(context).pop(kFollowTheme),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
