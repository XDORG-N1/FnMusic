import 'package:flutter/material.dart';

import '../common/artwork_widget.dart';

/// 通用媒体列表项：封面 + 标题 + 副标题 + 尾部。
class MediaListTile extends StatelessWidget {
  const MediaListTile({
    super.key,
    this.imageUrl,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.showPlayingIndicator = false,
    this.leadingWidget,
  });

  final String? imageUrl;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool showPlayingIndicator;
  final Widget? leadingWidget;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      leading: leadingWidget ??
          ArtworkWidget(imageUrl: imageUrl, size: 48),
      title: Text(
        title ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected ? scheme.primary : null,
          fontWeight: selected ? FontWeight.w600 : null,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
      trailing: trailing,
    );
  }
}
