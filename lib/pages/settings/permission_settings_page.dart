import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// 权限设置：申请 / 查看通知与媒体音频权限状态。
class PermissionSettingsPage extends StatefulWidget {
  const PermissionSettingsPage({super.key});

  static const String route = '/settings/permissions';

  @override
  State<PermissionSettingsPage> createState() => _PermissionSettingsPageState();
}

class _PermissionSettingsPageState extends State<PermissionSettingsPage> {
  Map<Permission, PermissionStatus> _statuses = <Permission, PermissionStatus>{};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final Map<Permission, PermissionStatus> statuses =
        <Permission, PermissionStatus>{};
    for (final Permission p in const <Permission>[
      Permission.notification,
      Permission.audio,
    ]) {
      statuses[p] = await p.status;
    }
    if (!mounted) return;
    setState(() => _statuses = statuses);
  }

  Future<void> _request(Permission permission) async {
    final PermissionStatus status = await permission.request();
    if (!mounted) return;
    setState(() => _statuses[permission] = status);
    if (status.isPermanentlyDenied) {
      final bool? open = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('权限被拒绝'),
          content: const Text('该权限已被永久拒绝，请前往系统设置手动开启。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('去设置'),
            ),
          ],
        ),
      );
      if (open == true) {
        await openAppSettings();
      }
    }
  }

  String _statusLabel(PermissionStatus status) {
    if (status.isGranted) return '已授权';
    if (status.isPermanentlyDenied) return '已拒绝（前往系统设置）';
    if (status.isRestricted) return '受限';
    return '未授权';
  }

  Color _statusColor(PermissionStatus status) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (status.isGranted) return Colors.green;
    return scheme.error;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('权限')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: <Widget>[
          _PermissionTile(
            icon: Icons.notifications_outlined,
            title: '通知权限',
            subtitle: '播放通知、锁屏控制与后台播放展示',
            permission: Permission.notification,
            status: _statuses[Permission.notification],
            statusLabel: _statusLabel,
            statusColor: _statusColor,
            onTap: _request,
          ),
          _PermissionTile(
            icon: Icons.library_music_outlined,
            title: '媒体音频权限',
            subtitle: '读取设备本地音频（本应用为在线播放，一般无需）',
            permission: Permission.audio,
            status: _statuses[Permission.audio],
            statusLabel: _statusLabel,
            statusColor: _statusColor,
            onTap: _request,
          ),
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.permission,
    required this.status,
    required this.statusLabel,
    required this.statusColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Permission permission;
  final PermissionStatus? status;
  final String Function(PermissionStatus) statusLabel;
  final Color Function(PermissionStatus) statusColor;
  final void Function(Permission) onTap;

  @override
  Widget build(BuildContext context) {
    final PermissionStatus s = status ?? PermissionStatus.denied;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            statusLabel(s),
            style: TextStyle(color: statusColor(s), fontSize: 13),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => onTap(permission),
    );
  }
}
