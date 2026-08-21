import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/services/feiniu/api_client.dart';

/// 封面图组件：支持网络图 + 加载占位 / 失败占位。
///
/// 自动携带当前账号鉴权头（真实 FNOS 的 `/static/cover` 需要 Cookie
/// `music-token`，未登录时为空头，mock/公开封面不受影响）。
class ArtworkWidget extends StatelessWidget {
  const ArtworkWidget({
    super.key,
    this.imageUrl,
    this.size,
    this.borderRadius,
    this.placeholderIcon = Icons.music_note,
    this.placeholderText,
  });

  final String? imageUrl;
  final double? size;
  final BorderRadius? borderRadius;
  final IconData placeholderIcon;

  /// 占位/失败时显示的首字母（无封面图时展示，如专辑名/歌手名首字母）。
  /// 为空则退回 [placeholderIcon] 图标。
  final String? placeholderText;

  @override
  Widget build(BuildContext context) {
    final double edge = size ?? 48;
    final BorderRadius radius =
        borderRadius ?? BorderRadius.circular(edge * 0.22);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    if (imageUrl == null || imageUrl!.isEmpty) {
      return _placeholder(context, edge, radius, scheme);
    }

    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        httpHeaders: ApiClient.imageAuthHeaders(),
        width: edge,
        height: edge,
        fit: BoxFit.cover,
        placeholder: (context, url) =>
            _placeholder(context, edge, radius, scheme),
        errorWidget: (context, url, error) =>
            _placeholder(context, edge, radius, scheme),
      ),
    );
  }

  Widget _placeholder(
    BuildContext context,
    double edge,
    BorderRadius radius,
    ColorScheme scheme,
  ) {
    final String? text = placeholderText?.trim();
    return Container(
      width: edge,
      height: edge,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            scheme.primary.withValues(alpha: 0.18),
            scheme.tertiary.withValues(alpha: 0.12),
          ],
        ),
      ),
      child: (text != null && text.isNotEmpty)
          ? Center(
              child: Text(
                text.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  fontSize: edge * 0.4,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary.withValues(alpha: 0.6),
                ),
              ),
            )
          : Icon(placeholderIcon, size: edge * 0.42, color: scheme.primary.withValues(alpha: 0.5)),
    );
  }
}
