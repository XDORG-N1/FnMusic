import 'package:flutter/material.dart';

/// 歌词/设置面板的等价组件（Material 实现）。
///
/// 原设计用 AppSheetPanel/AppSettingSection/LabeledSlider/AppSettingSwitchTile
/// 构建各设置弹层；FnMusic 目前仅在歌词设置中用到，故只实现最小等价物。

/// 带标题与拖动把手的底部面板外壳。
class AppSheetPanel extends StatelessWidget {
  final String? title;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool expand;

  const AppSheetPanel({
    super.key,
    this.title,
    required this.child,
    this.padding,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.cardTheme.color ?? theme.cardColor;
    final isDark = theme.brightness == Brightness.dark;
    final secondaryTextColor = isDark
        ? Colors.white70
        : const Color.fromARGB(255, 100, 100, 100);

    return Material(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: secondaryTextColor.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Text(
                  title!,
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (expand)
              Expanded(
                child: Padding(
                  padding: padding ?? EdgeInsets.zero,
                  child: child,
                ),
              )
            else
              Padding(
                padding: padding ?? EdgeInsets.zero,
                child: child,
              ),
          ],
        ),
      ),
    );
  }
}

/// 设置分组：标题 + 子项列表（可选分隔线）。
class AppSettingSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final bool showDividers;

  const AppSettingSection({
    super.key,
    this.title,
    required this.children,
    this.margin,
    this.padding,
    this.showDividers = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0 && showDividers) {
        content.add(const Divider(height: 1));
      }
      content.add(children[i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 0, 8),
            child: Text(
              title!,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        Material(
          color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: margin ?? EdgeInsets.zero,
            child: Padding(
              padding: padding ?? EdgeInsets.zero,
              child: Column(children: content),
            ),
          ),
        ),
      ],
    );
  }
}

/// 开关设置项。
class AppSettingSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AppSettingSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 0,
        ),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: Switch.adaptive(value: value, onChanged: onChanged),
        onTap: onChanged == null ? null : () => onChanged!(!value),
      ),
    );
  }
}

/// 可点按设置项（标题 + 副标题 + 前导/尾部图标）。
class AppSettingTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  const AppSettingTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: leading,
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: trailing ?? const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// 带标题、数值与滑块的一行设置项。
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.divisions,
    this.label,
    this.valueText,
    this.description,
    this.titleFontSize = 15,
    this.padding,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final String? valueText;
  final String? description;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double titleFontSize;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final displayValue = (valueText ?? '').trim().isEmpty ? null : valueText;
    final detail = (description ?? '').trim().isEmpty ? null : description;
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: titleFontSize),
                ),
              ),
              if (displayValue != null) ...[
                const SizedBox(width: 8),
                Text(
                  displayValue,
                  style: TextStyle(
                    fontSize: titleFontSize,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail,
              style: TextStyle(
                fontSize: 13,
                color: colors.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
