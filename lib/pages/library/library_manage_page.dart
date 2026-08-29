import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/services/feiniu/feiniu_services.dart';

/// 音乐库管理页（网页版 /music/settings?key=library 的音乐库管理功能）。
///
/// 展示共享音乐库列表，支持新建 / 编辑 / 删除 / 扫描 / 扫描全部 / 重建索引，
/// 轮询 `/task/list` 展示扫描状态。
class LibraryManagePage extends StatefulWidget {
  const LibraryManagePage({super.key});

  static const String route = '/library/library-manage';

  @override
  State<LibraryManagePage> createState() => _LibraryManagePageState();
}

class _LibraryManagePageState extends State<LibraryManagePage> {
  List<FnLibrary> _libraries = <FnLibrary>[];
  Set<String> _scanningGuids = <String>{};
  bool _loading = true;
  String? _error;
  String? _errorDetail;

  /// 正在执行的按钮动作键（如 `scan:lib_001`），用于按钮 loading。
  String? _busyKey;

  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<FnLibrary> libraries =
          await FnLibraryService.instance.fetchLibraries();
      final Set<String> scanning =
          await FnLibraryService.instance.activeScanLibraryGuids();
      if (!mounted) return;
      setState(() {
        _libraries = libraries;
        _scanningGuids = scanning;
        _error = null;
        _errorDetail = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.friendlyMessage
            : '加载失败，请检查网络后重试';
        _errorDetail = '$e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 轮询扫描任务，更新「扫描中」状态；全部完成后停止轮询。
  void _scheduleScanPoll() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshScanGuids(),
    );
  }

  Future<void> _refreshScanGuids() async {
    try {
      final Set<String> scanning =
          await FnLibraryService.instance.activeScanLibraryGuids();
      if (!mounted) return;
      setState(() => _scanningGuids = scanning);
      if (scanning.isEmpty) {
        _scanTimer?.cancel();
        _scanTimer = null;
      }
    } catch (_) {}
  }

  Future<void> _runBusy(String key, Future<void> Function() action) async {
    if (_busyKey != null) return;
    setState(() => _busyKey = key);
    try {
      await action();
      if (!mounted) return;
      final List<FnLibrary> libraries =
          await FnLibraryService.instance.fetchLibraries();
      final Set<String> scanning =
          await FnLibraryService.instance.activeScanLibraryGuids();
      if (!mounted) return;
      setState(() {
        _libraries = libraries;
        _scanningGuids = scanning;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_friendly(e))));
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  String _friendly(Object e) =>
      e is ApiException ? e.friendlyMessage : '操作失败，请稍后重试';

  Future<void> _openAddDialog() async {
    final _LibraryFormResult? result = await showDialog<_LibraryFormResult>(
      context: context,
      builder: (_) => _LibraryEditDialog(
        disabledPaths: _libraries.map((FnLibrary l) => l.path).toList(),
      ),
    );
    if (result == null || !mounted) return;
    await _runBusy(
      'create',
      () => FnLibraryService.instance.createLibrary(
        path: result.path,
        metadataPreference: result.metadataPreference,
        autoDownloadLyric: result.autoDownloadLyric,
      ),
    );
  }

  Future<void> _openEditDialog(FnLibrary library) async {
    final _LibraryFormResult? result =
        await showDialog<_LibraryFormResult>(
      context: context,
      builder: (_) => _LibraryEditDialog(
        initial: library,
        disabledPaths: _libraries.map((FnLibrary l) => l.path).toList(),
      ),
    );
    if (result == null || !mounted) return;
    await _runBusy(
      'edit:${library.guid}',
      () => FnLibraryService.instance.updateLibrary(
        guid: library.guid,
        path: result.path,
        metadataPreference: result.metadataPreference,
        autoDownloadLyric: result.autoDownloadLyric,
      ),
    );
  }

  Future<void> _confirmDelete(FnLibrary library) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除音乐库'),
        content: Text('确定删除「${library.displayName}」吗？\n${library.path}'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runBusy(
      'delete:${library.guid}',
      () => FnLibraryService.instance.deleteLibrary(library.guid),
    );
  }

  void _scanLibrary(FnLibrary library) {
    _runBusy(
      'scan:${library.guid}',
      () => FnLibraryService.instance.scanLibrary(library.guid),
    );
    _scheduleScanPoll();
  }

  void _scanAll() {
    if (_libraries.isEmpty) return;
    _runBusy('scan-all', FnLibraryService.instance.scanAllLibraries);
    _scheduleScanPoll();
  }

  void _rebuildIndex() {
    _runBusy('rebuild', FnLibraryService.instance.rebuildSearchIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('音乐库管理'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.play_circle_outline),
            tooltip: '扫描全部',
            onPressed: _busyKey == null && _libraries.isNotEmpty ? _scanAll : null,
          ),
          IconButton(
            icon: const Icon(Icons.manage_search),
            tooltip: '重建搜索索引',
            onPressed: _busyKey == null ? _rebuildIndex : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(context)
              : _buildList(context),
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _busyKey == null ? _openAddDialog : null,
              icon: const Icon(Icons.add),
              label: const Text('添加音乐库'),
            ),
    );
  }

  Widget _buildList(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (_libraries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.folder_off_outlined,
                size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('暂无音乐库', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '点击右下角「添加音乐库」创建',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      itemCount: _libraries.length,
      itemBuilder: (context, index) =>
          _buildCard(context, _libraries[index]),
    );
  }

  Widget _buildCard(BuildContext context, FnLibrary library) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool scanning = _scanningGuids.contains(library.guid);
    final String? busy = _busyKey;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: scanning
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: scheme.primary),
                    )
                  : Icon(Icons.folder_outlined, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          library.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (scanning) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '扫描中',
                            style: TextStyle(
                                fontSize: 11, color: scheme.primary),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    library.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  if (library.lastChangedAt != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      '更新于 ${_formatChanged(library.lastChangedAt!)}',
                      style: TextStyle(
                          fontSize: 11, color: scheme.outline),
                    ),
                  ],
                ],
              ),
            ),
            _ActionButton(
              icon: Icons.edit_outlined,
              tooltip: '编辑',
              enabled: busy == null,
              busy: busy == 'edit:${library.guid}',
              onTap: () => _openEditDialog(library),
            ),
            _ActionButton(
              icon: Icons.play_arrow_rounded,
              tooltip: '扫描',
              enabled: busy == null && !scanning,
              busy: busy == 'scan:${library.guid}',
              onTap: () => _scanLibrary(library),
            ),
            _ActionButton(
              icon: Icons.delete_outline,
              tooltip: '删除',
              enabled: busy == null,
              busy: busy == 'delete:${library.guid}',
              onTap: () => _confirmDelete(library),
            ),
          ],
        ),
      ),
    );
  }

  String _formatChanged(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  /// 错误态：友好提示 + 原始详情 + 重试。
  Widget _buildError(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.folder_off_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (_errorDetail != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _errorDetail!,
                style: TextStyle(fontSize: 12, color: scheme.outline),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡片右侧动作按钮：编辑 / 扫描 / 删除。
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      tooltip: tooltip,
      onPressed: enabled ? onTap : null,
    );
  }
}

/// 新建 / 编辑音乐库的表单对话框。
///
/// 「音乐库路径」参考网页版 `/music/settings?key=library` 的音乐文件夹编辑：
/// 点击路径字段打开文件夹选择器，展示 fnOS 语义化路径（存储空间 / 外接存储…），
/// 禁止选择已添加为音乐库的文件夹。
class _LibraryEditDialog extends StatefulWidget {
  const _LibraryEditDialog({
    this.initial,
    this.disabledPaths = const <String>[],
  });

  final FnLibrary? initial;

  /// 已添加为音乐库的路径（选择器中禁用 / 标记「已添加」）。
  final List<String> disabledPaths;

  @override
  State<_LibraryEditDialog> createState() => _LibraryEditDialogState();
}

class _LibraryEditDialogState extends State<_LibraryEditDialog> {
  late String _selectedPath;
  late String _metadataPreference;
  late bool _autoDownloadLyric;
  String? _pathError;

  @override
  void initState() {
    super.initState();
    _selectedPath = widget.initial?.path ?? '';
    _metadataPreference = widget.initial?.metadataPreference ??
        FnMetadataPreference.cloudPreferred;
    _autoDownloadLyric = widget.initial?.autoDownloadLyric ?? false;
  }

  void _submit() {
    final String path = _selectedPath.trim();
    if (path.isEmpty) {
      setState(() => _pathError = '请选择文件夹路径');
      return;
    }
    Navigator.of(context).pop(_LibraryFormResult(
      path: path,
      metadataPreference: _metadataPreference,
      autoDownloadLyric: _autoDownloadLyric,
    ));
  }

  Future<void> _openPicker() async {
    final String? picked = await showDialog<String>(
      context: context,
      builder: (_) => _FolderPickerDialog(
        disabledPaths: widget.disabledPaths,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedPath = picked;
      _pathError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.initial == null ? '添加音乐库' : '编辑音乐库'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('音乐库路径',
                style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            _FolderPathField(
              selectedPath: _selectedPath,
              onTap: _openPicker,
              errorText: _pathError,
            ),
            const SizedBox(height: 16),
            Text('元数据偏好',
                style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            RadioGroup<String>(
              groupValue: _metadataPreference,
              onChanged: (String? value) {
                if (value == null) return;
                setState(() => _metadataPreference = value);
              },
              child: Column(
                children: const <Widget>[
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('云端优先'),
                    subtitle: Text('优先使用云端元数据（封面/歌词等）'),
                    value: FnMetadataPreference.cloudPreferred,
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('仅本地'),
                    subtitle: Text('只使用本地已有元数据'),
                    value: FnMetadataPreference.localOnly,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自动下载歌词'),
              subtitle: const Text('扫描时自动为歌曲匹配歌词'),
              value: _autoDownloadLyric,
              onChanged: (bool value) =>
                  setState(() => _autoDownloadLyric = value),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

/// 音乐库路径字段：可点击的文件夹选择控件（参考网页版「音乐文件夹」编辑）。
///
/// 显示语义化路径（`存储空间 1/media/Music`），未选择时显示占位符；
/// 点击打开 `_FolderPickerDialog` 浏览并选择文件夹。
class _FolderPathField extends StatelessWidget {
  const _FolderPathField({
    required this.selectedPath,
    required this.onTap,
    this.errorText,
  });

  final String selectedPath;
  final VoidCallback onTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool hasPath = selectedPath.trim().isNotEmpty;
    final bool hasError = errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasError ? scheme.error : scheme.outlineVariant,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.folder_outlined,
                      size: 20,
                      color: hasError ? scheme.error : scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasPath ? semanticPathOf(selectedPath) : '请选择文件夹',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: hasError
                            ? scheme.error
                            : (hasPath
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant),
                        fontWeight: hasPath ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 20, color: scheme.outline),
                ],
              ),
            ),
          ),
        ),
        if (hasError) ...<Widget>[
          const SizedBox(height: 6),
          Text(errorText!, style: TextStyle(fontSize: 12, color: scheme.error)),
        ],
      ],
    );
  }
}

/// 文件夹选择器对话框（对应网页版「音乐文件夹」编辑的目录浏览）。
///
/// 顶层列出授权目录（`GET /app-center/authed-dir/list`），点击进入子目录
/// （`GET /app-center/authed-dir/sub/list?parent=`），面包屑可逐级返回；
/// 「选择此文件夹」确认当前目录。已添加为音乐库的路径标记「已添加」且不可选中。
class _FolderPickerDialog extends StatefulWidget {
  const _FolderPickerDialog({required this.disabledPaths});

  final List<String> disabledPaths;

  @override
  State<_FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<_FolderPickerDialog> {
  /// 当前浏览的目录路径（`''` = 授权目录根列表）。
  String _path = '';
  List<FnDirectory> _entries = const <FnDirectory>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(_path);
  }

  Future<void> _load(String path) async {
    setState(() {
      _path = path;
      _loading = true;
      _error = null;
    });
    try {
      final List<FnDirectory> entries = path.isEmpty
          ? await FnLibraryService.instance.fetchAuthorizedDirectories()
          : await FnLibraryService.instance.fetchSubDirectories(path);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.friendlyMessage : '加载失败，请重试';
      });
    }
  }

  void _confirm() {
    if (_path.trim().isEmpty) return;
    Navigator.of(context).pop(_path);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isDisabledPath = widget.disabledPaths.contains(_path);
    return AlertDialog(
      title: const Text('选择文件夹'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildBreadcrumb(theme),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Expanded(child: _buildBody(theme, scheme)),
            const SizedBox(height: 4),
            _buildFooter(theme, scheme, isDisabledPath),
          ],
        ),
      ),
    );
  }

  /// 面包屑：`根 / 存储空间 1 / media / Music`，点击逐级返回。
  Widget _buildBreadcrumb(ThemeData theme) {
    final List<String> segs =
        _path.split('/').where((String s) => s.isNotEmpty).toList();
    final List<Widget> chips = <Widget>[
      _crumb(theme, '', '根', isLast: segs.isEmpty),
    ];
    String acc = '';
    for (int i = 0; i < segs.length; i++) {
      acc += '/${segs[i]}';
      chips.add(_crumb(
        theme,
        acc,
        i == 0 ? semanticPathOf(acc) : segs[i],
        isLast: i == segs.length - 1,
      ));
    }
    return SizedBox(
      height: 40,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: chips),
      ),
    );
  }

  Widget _crumb(ThemeData theme, String path, String label,
      {required bool isLast}) {
    final ColorScheme scheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isLast ? null : () => _load(path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isLast ? scheme.onSurface : scheme.primary,
                fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
        if (!isLast)
          Icon(Icons.chevron_right, size: 14, color: scheme.outline),
      ],
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme scheme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _load(_path),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return Center(
        child: Text('此文件夹为空',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    // 顶层行展示语义化路径（存储空间 1 / 外接存储…，与网页版一致）；
    // 子目录行展示目录名。
    final bool isRoot = _path.isEmpty;
    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final FnDirectory dir = _entries[index];
        final bool disabled = widget.disabledPaths.contains(dir.path);
        final String label = isRoot
            ? semanticPathOf(dir.path)
            : (dir.name.trim().isNotEmpty ? dir.name : semanticPathOf(dir.path));
        return ListTile(
          dense: true,
          leading: Icon(
            Icons.folder_outlined,
            color: disabled ? scheme.outline : scheme.primary,
          ),
          title: Text(
            label,
            style: TextStyle(color: disabled ? scheme.outline : null),
          ),
          trailing: disabled
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('已添加',
                      style: TextStyle(fontSize: 11, color: scheme.outline)),
                )
              : Icon(Icons.chevron_right, color: scheme.outlineVariant),
          onTap: () => _load(dir.path),
        );
      },
    );
  }

  Widget _buildFooter(
      ThemeData theme, ColorScheme scheme, bool isDisabledPath) {
    return Row(
      children: <Widget>[
        Expanded(
          child: isDisabledPath
              ? Text('该文件夹已添加为音乐库',
                  style: TextStyle(fontSize: 12, color: scheme.error))
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: 12),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: (_path.trim().isEmpty || isDisabledPath)
              ? null
              : _confirm,
          child: const Text('选择此文件夹'),
        ),
      ],
    );
  }
}

/// 表单提交结果。
class _LibraryFormResult {
  const _LibraryFormResult({
    required this.path,
    required this.metadataPreference,
    required this.autoDownloadLyric,
  });

  final String path;
  final String metadataPreference;
  final bool autoDownloadLyric;
}
