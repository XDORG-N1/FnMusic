import 'package:flutter/material.dart';

import '../../../app/services/feiniu/api_client.dart';
import '../../../app/services/lyrics/lyrics_service.dart';
import '../../../app/services/player_service.dart';
import '../../../app/state/player_state.dart';
import '../../../app/state/song_state.dart';
import '../../../pages/player/player_route.dart';
import '../../../pages/player/widgets/player_bottom_panel.dart';
import '../../common/artwork_widget.dart';
import '../lyric_preview.dart';

/// 迷你播放器条：封面 + 可横滑切歌的信息区 + 播放队列 + 播放暂停。
///
/// 隐藏条件由 [AppLayoutSettings.playerRouteActive]（全屏播放器激活时）与
/// `currentSong == null`（无播放内容）控制，见主壳 [_MiniPlayerSlot]。
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key, this.player});

  /// 可注入测试替身；默认使用全局播放服务。
  final FnPlayerService? player;

  @override
  Widget build(BuildContext context) {
    final FnPlayerService service = player ?? FnPlayerService.instance;
    return ValueListenableBuilder<SongEntity?>(
      valueListenable: AppPlayerState.instance.currentSong,
      builder: (context, song, _) {
        if (song == null) return const SizedBox.shrink();
        return _MiniPlayerContent(player: service, song: song);
      },
    );
  }
}

class _MiniPlayerContent extends StatelessWidget {
  final FnPlayerService player;
  final SongEntity song;

  const _MiniPlayerContent({required this.player, required this.song});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      child: Material(
        color: scheme.surfaceContainer,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.28),
        child: InkWell(
          onTap: () => openPlayerPage(context),
          child: SizedBox(
            height: 62,
            child: Row(
              children: <Widget>[
                MiniPlayerArtwork(song: song),
                Expanded(child: _SwipeableInfo(player: player, song: song)),
                MiniPlayerQueueButton(player: player),
                MiniPlayerPlayButton(player: player),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 迷你播放器封面。
class MiniPlayerArtwork extends StatelessWidget {
  final SongEntity song;

  const MiniPlayerArtwork({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      child: ArtworkWidget(
        imageUrl: ApiClient.instance.coverUrl(song.coverId),
        size: 48,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

/// 迷你播放器歌曲信息（副标题为当前行歌词，无歌词时回退歌手）。
class MiniPlayerInfo extends StatelessWidget {
  final String title;
  final String subtitle;

  const MiniPlayerInfo({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        // 单行逐字歌词：与播放页/歌词页共用同一渲染管线。
        _MiniPlayerSubtitle(fallback: subtitle),
      ],
    );
  }
}

/// 迷你播放器副标题：优先显示当前行歌词（逐字高亮），无歌词时回退 [fallback]。
class _MiniPlayerSubtitle extends StatelessWidget {
  final String fallback;

  const _MiniPlayerSubtitle({required this.fallback});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: LyricsService.instance.currentLineText,
      builder: (context, currentLyric, _) {
        final String lyric = currentLyric?.trim() ?? '';
        final String text = lyric.isNotEmpty ? lyric : fallback;
        return _MiniPlayerSubtitleText(
          text: text,
          karaoke: lyric.isNotEmpty,
        );
      },
    );
  }
}

/// 单行歌词文本：可逐字高亮（卡拉OK），超长自动缩字重/省略号。
class _MiniPlayerSubtitleText extends StatelessWidget {
  final String text;
  final bool karaoke;

  const _MiniPlayerSubtitleText({
    required this.text,
    required this.karaoke,
  });

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    if (!karaoke || text.trim().isEmpty) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    // 与播放页/歌词页完全相同的逐字渲染管线（LyricView + 高亮 mixin）。
    // activeLineOnly 只绘制当前播放行，单行高度即成为迷你单行逐字歌词。
    final LyricsService lyrics = LyricsService.instance;
    final model = lyrics.controller.lyricNotifier.value;
    final index = lyrics.controller.activeIndexNotifiter.value;
    if (model == null || index < 0 || index >= model.lines.length) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final line = model.lines[index];
    if (line.text.trim().isEmpty) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final double baseFontSize = style.fontSize ?? 11.5;
    return LayoutBuilder(
      builder: (context, constraints) {
        final double available = constraints.maxWidth;
        // 超长歌词：LyricView 的行 TextPainter 无 maxLines:1，会在容器宽度内
        // 自动换行成两行，而这里裁剪到单行高度会把第二行中间截断。检测到
        // 超宽时按比例缩小字号，保证歌词单行放下，保留逐字动画与完整内容。
        // 若缩小到下限仍放不下（极端超长），回退单行省略号避免"两行裁中间"。
        final (fontSize, fits) = _measureFit(
          text: text,
          baseFontSize: baseFontSize,
          maxWidth: available,
          style: style,
        );
        if (!fits) {
          return Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }
        return LyricPreview(
          height: fontSize * 1.3,
          textAlign: TextAlign.start,
          contentAlignment: CrossAxisAlignment.start,
          showTranslation: false,
          fontSize: fontSize,
          activeFontSize: fontSize,
          contentPadding: EdgeInsets.zero,
          activeLineOnly: true,
        );
      },
    );
  }

  /// 测量歌词单行宽度，超出 [maxWidth] 时按比例缩小字号。
  /// 返回 (目标字号, 是否单行放得下)。
  ///
  /// 注意必须用「加粗字重」测量：LyricPreview 的当前播放行以
  /// FontWeight.w700 渲染（见 lyric_preview.dart 的 activeStyle），加粗字比
  /// 常规字更宽。若用常规字重测量，会误判「刚好放得下」而实际渲染溢出，
  /// 触发 LyricLayout.compute 折行成两行，被单行窗口裁到两行中间（半截字）。
  /// 额外留 2% 安全边距兜底字距/绘制舍入等微小偏差。
  (double, bool) _measureFit({
    required String text,
    required double baseFontSize,
    required double maxWidth,
    required TextStyle style,
  }) {
    double widthAt(double size) {
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(fontSize: size, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      return painter.width;
    }

    final double fitWidth = maxWidth * 0.98;
    if (widthAt(baseFontSize) <= fitWidth || maxWidth <= 0) {
      return (baseFontSize, true);
    }
    final double ratio = fitWidth / widthAt(baseFontSize);
    final double shrunk =
        (baseFontSize * ratio).clamp(baseFontSize * 0.6, baseFontSize);
    // 缩小到下限后仍超宽 → 放不下，回退省略号
    if (widthAt(shrunk) > fitWidth) {
      return (baseFontSize, false);
    }
    return (shrunk, true);
  }
}

/// 信息区横滑切歌：拖拽显示"上一曲 / 下一曲"提示，超过阈值松手执行。
class _SwipeableInfo extends StatefulWidget {
  final FnPlayerService player;
  final SongEntity song;

  const _SwipeableInfo({required this.player, required this.song});

  @override
  State<_SwipeableInfo> createState() => _SwipeableInfoState();
}

class _SwipeableInfoState extends State<_SwipeableInfo> {
  double _dx = 0;

  String get _title {
    final String title = widget.song.title.trim();
    return title.isEmpty ? '未知歌曲' : title;
  }

  String get _subtitle {
    final String? artist = widget.song.artistDisplay?.trim();
    return artist == null || artist.isEmpty ? '未知歌手' : artist;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() => _dx = (_dx + details.delta.dx).clamp(-80.0, 80.0));
  }

  Future<void> _handleHorizontalDragEnd(DragEndDetails details) async {
    final bool changed = _dx.abs() > 60;
    if (changed) {
      if (_dx > 0) {
        await widget.player.previous();
      } else {
        await widget.player.next();
      }
    }
    setState(() => _dx = 0);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool goingPrev = _dx > 0;
    final bool showHint = _dx.abs() > 12;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _handleHorizontalDragUpdate,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      onHorizontalDragCancel: () => setState(() => _dx = 0),
      child: ClipRect(
        child: Stack(
          alignment: Alignment.centerLeft,
          children: <Widget>[
            // 切歌提示胶囊。
            AnimatedOpacity(
              opacity: showHint ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    goingPrev ? '上一曲' : '下一曲',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
            ),
            // 随拖拽平移并淡出的信息区。
            Transform.translate(
              offset: Offset(_dx * 0.6, 0),
              child: Opacity(
                opacity: showHint ? 0.15 : 1.0,
                child: MiniPlayerInfo(title: _title, subtitle: _subtitle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 迷你播放器播放 / 暂停按钮：外圈进度环 + 中间图标。
class MiniPlayerPlayButton extends StatelessWidget {
  final FnPlayerService player;

  const MiniPlayerPlayButton({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<PlayerSnapshot>(
      valueListenable: AppPlayerState.instance.snapshot,
      builder: (context, snapshot, _) {
        final bool playing = snapshot.isPlaying;
        final Duration? duration = snapshot.duration;
        final double progress =
            (duration != null && duration.inMilliseconds > 0)
                ? (snapshot.position.inMilliseconds /
                        duration.inMilliseconds)
                    .clamp(0.0, 1.0)
                : 0.0;
        return SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2.5,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: scheme.primary,
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                iconSize: 24,
                color: scheme.onSurface,
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                onPressed: player.togglePlayPause,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 迷你播放器播放队列入口。
class MiniPlayerQueueButton extends StatelessWidget {
  final FnPlayerService player;

  const MiniPlayerQueueButton({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        Icons.format_list_bulleted_rounded,
        color: scheme.onSurfaceVariant,
      ),
      onPressed: () => showPlayerPlaylistSheet(context, player),
    );
  }
}
