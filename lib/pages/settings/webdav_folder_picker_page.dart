import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/services/backup/backup_service.dart';
import '../../components/common/setting_widgets.dart';

/// WebDAV 文件夹选择器：浏览服务器目录，选择当前所在位置作为备份目录。
///
/// 保存时 `Navigator.pop(context, String)` 返回选中的目录路径；取消返回 null。
class WebDavFolderPickerPage extends StatefulWidget {
  final BackupTarget target;
  final String initialPath;

  const WebDavFolderPickerPage({
    super.key,
    required this.target,
    required this.initialPath,
  });

  @override
  State<WebDavFolderPickerPage> createState() => _WebDavFolderPickerPageState();
}

class _WebDavFolderPickerPageState extends State<WebDavFolderPickerPage> {
  final BackupService _backup = BackupService.instance;

  late String _path;
  bool _loading = true;
  String? _error;
  List<WebDavFolder> _folders = const [];

  @override
  void initState() {
    super.initState();
    _path = BackupService.normalizeDir(widget.initialPath);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final folders = await _backup.listDirectories(widget.target, _path);
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _enter(WebDavFolder folder) {
    setState(() {
      _path = BackupService.normalizeDir(folder.path);
    });
    _load();
  }

  void _goUp() {
    final parent = p.url.dirname(_path);
    if (parent == _path) return;
    setState(() {
      _path = BackupService.normalizeDir(parent);
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final canGoUp = _path != '/';

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择备份目录'),
        actions: <Widget>[
          TextButton(
            onPressed: _loading
                ? null
                : () => Navigator.pop(context, _path),
            child: const Text('选择此处'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: <Widget>[
          AppSettingSection(
            title: '当前位置',
            children: <Widget>[
              AppSettingTile(
                title: _path,
                subtitle: '点「选择此处」备份到这个目录',
                leading: const Icon(Icons.location_on_outlined),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            AppSettingSection(
              title: '加载失败',
              children: <Widget>[
                AppSettingTile(
                  title: '点击重试',
                  subtitle: _error,
                  leading: const Icon(Icons.error_outline),
                  onTap: _load,
                ),
              ],
            )
          else
            AppSettingSection(
              title: '子文件夹',
              children: <Widget>[
                if (canGoUp)
                  AppSettingTile(
                    title: '..',
                    leading: const Icon(Icons.drive_folder_upload_outlined),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _goUp,
                  ),
                if (_folders.isEmpty)
                  const AppSettingTile(
                    title: '（空，可在当前位置创建备份）',
                    leading: Icon(Icons.folder_off_outlined),
                  )
                else
                  ..._folders.map(
                    (f) => AppSettingTile(
                      title: f.name,
                      subtitle: f.path,
                      leading: const Icon(Icons.folder_outlined),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _enter(f),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
