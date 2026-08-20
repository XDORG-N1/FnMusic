import 'package:flutter/material.dart';

import '../../app/state/settings_state.dart';
import 'about_page.dart';
import 'backup_restore_page.dart';
import 'cache_settings_page.dart';
import 'lyrics_settings_page.dart';
import 'permission_settings_page.dart';

/// 设置中心。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: <Widget>[
          _SectionHeader('外观'),
          _ThemeModeTile(),
          _DynamicColorTile(),
          _SeedColorTile(),
          _SectionHeader('通知'),
          _NotificationSwitchTile(
            title: '通知显示歌词',
            subtitle: '锁屏与通知栏展示当前歌词',
            icon: Icons.lyrics_outlined,
            valueListenable: MediaNotificationSettings.showLyrics,
            onChanged: MediaNotificationSettings.setShowLyrics,
          ),
          _NotificationSwitchTile(
            title: '歌词置顶',
            subtitle: '歌词作为通知主标题显示',
            icon: Icons.title,
            valueListenable: MediaNotificationSettings.lyricOnTop,
            onChanged: MediaNotificationSettings.setLyricOnTop,
          ),
          _NotificationSwitchTile(
            title: '显示关闭按钮',
            subtitle: '通知栏提供停止播放按钮',
            icon: Icons.stop_circle_outlined,
            valueListenable: MediaNotificationSettings.showCloseAction,
            onChanged: MediaNotificationSettings.setShowCloseAction,
          ),
          _NotificationSwitchTile(
            title: '显示收藏按钮',
            subtitle: '通知栏快速收藏 / 取消收藏',
            icon: Icons.favorite_outline,
            valueListenable: MediaNotificationSettings.showFavoriteAction,
            onChanged: MediaNotificationSettings.setShowFavoriteAction,
          ),
          _NotificationSwitchTile(
            title: '车载蓝牙歌词',
            subtitle: '通过蓝牙将歌词发送到车载系统',
            icon: Icons.directions_car_outlined,
            valueListenable: MediaNotificationSettings.carBluetoothLyrics,
            onChanged: MediaNotificationSettings.setCarBluetoothLyrics,
          ),
          _SectionHeader('歌词'),
          _NavigationTile(
            icon: Icons.lyrics_outlined,
            title: '歌词设置',
            subtitle: '强制逐字卡拉OK、歌词配色',
            route: LyricsSettingsPage.route,
          ),
          _SectionHeader('缓存'),
          _NavigationTile(
            icon: Icons.cleaning_services_outlined,
            title: '缓存管理',
            subtitle: '封面 / 歌词 / 音乐缓存占用与清理',
            route: CacheSettingsPage.route,
          ),
          _SectionHeader('权限'),
          _NavigationTile(
            icon: Icons.shield_outlined,
            title: '权限设置',
            subtitle: '通知 / 媒体音频权限申请',
            route: PermissionSettingsPage.route,
          ),
          _SectionHeader('数据'),
          _NavigationTile(
            icon: Icons.backup_outlined,
            title: '数据备份',
            subtitle: '账号 / 听歌统计 / 设置的备份与恢复（本地 + WebDAV）',
            route: BackupRestorePage.route,
          ),
          _SectionHeader('关于'),
          _NavigationTile(
            icon: Icons.info_outline,
            title: '关于',
            subtitle: '版本信息与开源声明',
            route: AboutPage.route,
          ),
        ],
      ),
    );
  }
}

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).pushNamed(route),
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

class _NotificationSwitchTile extends StatelessWidget {
  const _NotificationSwitchTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.valueListenable,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final ValueNotifier<bool> valueListenable;
  final Future<void> Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: valueListenable,
      builder: (context, value, _) {
        return SwitchListTile(
          secondary: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          value: value,
          onChanged: onChanged,
        );
      },
    );
  }
}

class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsTheme.themeMode,
      builder: (context, mode, _) {
        return ListTile(
          leading: const Icon(Icons.brightness_6_outlined),
          title: const Text('主题模式'),
          trailing: DropdownButton<ThemeMode>(
            value: mode,
            underline: const SizedBox.shrink(),
            items: const <DropdownMenuItem<ThemeMode>>[
              DropdownMenuItem(
                value: ThemeMode.system,
                child: Text('跟随系统'),
              ),
              DropdownMenuItem(
                value: ThemeMode.light,
                child: Text('浅色'),
              ),
              DropdownMenuItem(
                value: ThemeMode.dark,
                child: Text('深色'),
              ),
            ],
            onChanged: (ThemeMode? value) {
              if (value != null) SettingsTheme.setThemeMode(value);
            },
          ),
        );
      },
    );
  }
}

class _DynamicColorTile extends StatelessWidget {
  const _DynamicColorTile();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsTheme.dynamicColorEnabled,
      builder: (context, enabled, _) {
        return SwitchListTile(
          secondary: const Icon(Icons.palette_outlined),
          title: const Text('动态取色'),
          subtitle: const Text('使用系统壁纸配色（Android 12+）'),
          value: enabled,
          onChanged: SettingsTheme.setDynamicColorEnabled,
        );
      },
    );
  }
}

class _SeedColorTile extends StatelessWidget {
  const _SeedColorTile();

  static const List<Color> _presets = <Color>[
    Color(0xFFFF7A00),
    Color(0xFF6750A4),
    Color(0xFF00696D),
    Color(0xFFB3261E),
    Color(0xFF006A60),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SettingsTheme.seedColor,
      builder: (context, color, _) {
        return ListTile(
          leading: const Icon(Icons.colorize_outlined),
          title: const Text('主题色'),
          trailing: Wrap(
            spacing: 8,
            children: _presets.map((Color c) {
              final bool selected = c.toARGB32() == color.toARGB32();
              return GestureDetector(
                onTap: () => SettingsTheme.setSeedColor(c),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? Icon(Icons.check,
                          size: 16, color: Theme.of(context).colorScheme.onPrimary)
                      : null,
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
