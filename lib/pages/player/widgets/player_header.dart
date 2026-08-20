import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../../app/state/song_state.dart';

/// 全屏播放器顶部标题栏：歌曲名 + 歌手名（拖拽下拉关闭手势挂在这层）。
class PlayerHeader extends StatelessWidget {
  final Signal<SongEntity?> songSignal;

  const PlayerHeader({super.key, required this.songSignal});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color titleColor = scheme.onSurface;
    final Color subtitleColor = scheme.onSurfaceVariant.withValues(alpha: 0.8);

    return Watch.builder(
      builder: (context) {
        final SongEntity? song = songSignal.value;
        final String title =
            song?.title.trim().isEmpty == true ? '未知歌曲' : (song?.title ?? '未知歌曲');
        final String artist = song?.artistDisplay?.trim().isEmpty == true
            ? '未知歌手'
            : (song?.artistDisplay ?? '未知歌手');
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                      style: TextStyle(color: subtitleColor, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
