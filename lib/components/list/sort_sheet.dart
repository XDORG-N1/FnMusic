import 'package:flutter/material.dart';

/// 排序选项（纯数据）。
class SortOption {
  const SortOption({required this.key, required this.label, required this.icon});

  final String key;
  final String label;
  final IconData icon;
}

/// 排序底部弹窗：选项 chips + 升降序切换 + 可选扩展区。
///
/// 用法：`showSortSheet(context, SortSheet(...))`。回调即点即触发，
/// 调用方负责刷新数据并持久化偏好。
class SortSheet extends StatefulWidget {
  const SortSheet({
    super.key,
    required this.options,
    required this.currentKey,
    required this.ascending,
    required this.onSelectKey,
    required this.onSelectAscending,
    this.title = '排序',
    this.extra,
  });

  final List<SortOption> options;
  final String currentKey;
  final bool ascending;
  final ValueChanged<String> onSelectKey;
  final ValueChanged<bool> onSelectAscending;
  final String title;
  final Widget? extra;

  @override
  State<SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<SortSheet> {
  late String _currentKey = widget.currentKey;
  late bool _ascending = widget.ascending;

  @override
  void didUpdateWidget(SortSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentKey != widget.currentKey) _currentKey = widget.currentKey;
    if (oldWidget.ascending != widget.ascending) _ascending = widget.ascending;
  }

  void _selectKey(String key) {
    setState(() => _currentKey = key);
    widget.onSelectKey(key);
  }

  void _selectAscending(bool ascending) {
    setState(() => _ascending = ascending);
    widget.onSelectAscending(ascending);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Text(
                widget.title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                for (final SortOption option in widget.options)
                  _ChoiceChip(
                    label: option.label,
                    icon: option.icon,
                    selected: option.key == _currentKey,
                    onTap: () => _selectKey(option.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '排序方式',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                _ChoiceChip(
                  label: '升序',
                  icon: Icons.arrow_upward,
                  selected: _ascending,
                  onTap: () => _selectAscending(true),
                ),
                const SizedBox(width: 12),
                _ChoiceChip(
                  label: '降序',
                  icon: Icons.arrow_downward,
                  selected: !_ascending,
                  onTap: () => _selectAscending(false),
                ),
              ],
            ),
            if (widget.extra != null) ...<Widget>[
              const SizedBox(height: 16),
              Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 8),
              widget.extra!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 选择型 chip：选中时 primary 底tint + 主色文字。
class _ChoiceChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 18,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// AppBar 排序按钮（标题可省略，直接排序图标）。
class SortActionButton extends StatelessWidget {
  const SortActionButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.sort),
      tooltip: '排序',
      onPressed: onTap,
    );
  }
}

/// 弹出排序面板。
Future<void> showSortSheet(BuildContext context, SortSheet sheet) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => sheet,
  );
}
