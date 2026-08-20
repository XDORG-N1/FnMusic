import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../../app/services/feiniu/api_client.dart';
import '../../../app/services/feiniu/favorite_service.dart';
import '../../../app/services/lyrics/lyrics_service.dart';
import '../../../app/services/player_service.dart';
import '../../../app/state/player_state.dart';
import '../../../app/state/player_style_settings.dart';
import '../../../app/state/song_state.dart';
import '../../../components/common/artwork_widget.dart';
import '../../../components/common/playing_bars.dart';
import '../../../components/feedback/app_toast.dart';
import '../../../components/player/lyric_preview.dart';
import 'player_background.dart';

/// 全屏播放器底部控制面板：迷你歌词 + 进度条 + 播放控制 + 底部操作栏。
class PlayerBottomPanel extends StatelessWidget {
  final FnPlayerService player;
  final PlayerStylePreset stylePreset;
  final VoidCallback onTapLyrics;
  final bool showMiniLyrics;

  const PlayerBottomPanel({
    super.key,
    required this.player,
    required this.stylePreset,
    required this.onTapLyrics,
    this.showMiniLyrics = true,
  });

  @override
  Widget build(BuildContext context) {
    PlayerStyleSettings.ensureLoaded();
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    final double bottomSpacing = bottomInset > 20 ? bottomInset + 16.0 : 30.0;
    return Column(
      children: <Widget>[
        if (showMiniLyrics)
          _MiniLyricsPreview(onTap: onTapLyrics, stylePreset: stylePreset),
        PlayerSeekBar(player: player),
        const SizedBox(height: 20),
        PlayerControls(player: player, stylePreset: stylePreset),
        const SizedBox(height: 30),
        BottomActions(player: player),
        SizedBox(height: bottomSpacing),
      ],
    );
  }
}

/// 底部面板的迷你歌词预览：点击跳转到歌词页。
class _MiniLyricsPreview extends StatefulWidget {
  final VoidCallback onTap;
  final PlayerStylePreset stylePreset;

  const _MiniLyricsPreview({required this.onTap, required this.stylePreset});

  @override
  State<_MiniLyricsPreview> createState() => _MiniLyricsPreviewState();
}

class _MiniLyricsPreviewState extends State<_MiniLyricsPreview>
    with SignalsMixin {
  static const String _prefsMiniEnabled = 'mini_lyrics_enabled';
  static const String _prefsShowTranslation = 'lyrics_view_show_translation';
  static const String _prefsMiniAlignment = 'mini_lyrics_alignment';

  late final _enabled = createSignal(true);
  late final _showTranslation = createSignal(true);
  late final _alignment = createSignal('center');

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    LyricsService.instance.viewSettingsTick.addListener(_onSettingsTick);
  }

  @override
  void dispose() {
    LyricsService.instance.viewSettingsTick.removeListener(_onSettingsTick);
    super.dispose();
  }

  void _onSettingsTick() {
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _enabled.value = prefs.getBool(_prefsMiniEnabled) ?? true;
    _showTranslation.value = prefs.getBool(_prefsShowTranslation) ?? true;
    _alignment.value = prefs.getString(_prefsMiniAlignment) ?? 'center';
  }

  @override
  Widget build(BuildContext context) {
    // Theme 在 Watch.builder 外捕获：signals 的 computed 在元素卸载后仍可能因
    // 歌词/播放状态更新而重算 builder，此时 context 已 deactivated，
    // 在 builder 内调 Theme.of 会抛 "Looking up a deactivated widget's ancestor"。
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Watch.builder(
      builder: (context) {
        if (!_enabled.value) {
          return const SizedBox.shrink();
        }
        final LyricsService lyrics = LyricsService.instance;
        final LyricsSnapshot snap = lyrics.snapshotSignal.value;
        final LyricModel? model = lyrics.lyricModelSignal.value;
        final List<LyricLine> lines = model?.lines ?? const <LyricLine>[];
        final String alignment = _alignment.value;
        final double previewHeight = switch (widget.stylePreset) {
          PlayerStylePreset.poster => 118.0,
          PlayerStylePreset.classic => 110.0,
        };
        final TextAlign textAlign = alignment == 'left'
            ? TextAlign.left
            : alignment == 'right'
            ? TextAlign.right
            : TextAlign.center;
        final CrossAxisAlignment crossAlign = alignment == 'left'
            ? CrossAxisAlignment.start
            : alignment == 'right'
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.center;

        return Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: SizedBox(
                  height: previewHeight,
                  child: Center(
                    child: () {
                      // 加载新歌歌词时保持空白（不显示骨架），歌词就绪后直接
                      // 展示真实行；若已有歌词则继续显示。
                      if (snap.status == LyricsLoadStatus.loading &&
                          lines.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      if (lines.isEmpty) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '暂无歌词',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: scheme.onSurface.withValues(alpha: 0.9),
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '纯音乐或未匹配到歌词',
                              style: TextStyle(
                                fontSize: 14,
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        );
                      }

                      // 复用歌词页的 LyricView 渲染管线（AnimationController 驱动 +
                      // CustomPainter 高亮），保证与歌词页一致的流畅逐字动画。
                      return LyricPreview(
                        height: previewHeight,
                        textAlign: textAlign,
                        contentAlignment: crossAlign,
                        showTranslation: _showTranslation.value,
                        fontSize: 15,
                        activeFontSize: 18,
                        // 上下边缘渐隐，歌词行滑出边界时淡出而非硬截断
                        fadeEdges: true,
                      );
                    }(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

/// 播放进度条 + 缓冲条 + 时间标签。
class PlayerSeekBar extends StatefulWidget {
  final FnPlayerService player;

  const PlayerSeekBar({super.key, required this.player});

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> with SignalsMixin {
  late final Signal<double?> _dragValue = createSignal<double?>(null);

  String _format(Duration? duration) {
    final int total = duration?.inSeconds ?? 0;
    if (total <= 0) return '00:00';
    final int minutes = total ~/ 60;
    final int seconds = total % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Theme 在 Watch.builder 外捕获：signals 的 computed 在元素卸载后仍可能
    // 因 position/buffered 更新而重算 builder，此时 context 已 deactivated，
    // 在 builder 内调 Theme.of 会抛 "Looking up a deactivated widget's ancestor"。
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Watch.builder(
      builder: (context) {
        final AppPlayerState state = AppPlayerState.instance;
        final Duration position = state.positionSignal.value;
        final Duration? duration = state.durationSignal.value;
        final Duration buffered = state.bufferedPositionSignal.value;
        final int totalMs = duration?.inMilliseconds ?? 0;
        final double max = totalMs <= 0 ? 1.0 : totalMs.toDouble();
        final int currentMs = position.inMilliseconds
            .clamp(0, max.toInt())
            .toInt();
        final double sliderValue =
            (_dragValue.value ?? currentMs.toDouble()).clamp(0, max).toDouble();
        final double bufferedRatio = totalMs > 0
            ? (buffered.inMilliseconds / totalMs).clamp(0.0, 1.0)
            : 0.0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: <Widget>[
              SizedBox(
                height: 24,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    // 缓冲进度（轨道下层半透明条）
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10.5,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: bufferedRatio,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              scheme.onSurface.withValues(alpha: 0.18),
                            ),
                            minHeight: 3,
                          ),
                        ),
                      ),
                    ),
                    // 播放进度滑块
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                        activeTrackColor: scheme.onSurface,
                        inactiveTrackColor: scheme.onSurfaceVariant.withValues(
                          alpha: 0.25,
                        ),
                        thumbColor: scheme.onSurface,
                      ),
                      child: Slider(
                        value: sliderValue,
                        min: 0,
                        max: max,
                        onChanged: totalMs <= 0
                            ? null
                            : (double value) => _dragValue.value = value,
                        onChangeEnd: totalMs <= 0
                            ? null
                            : (double value) {
                                _dragValue.value = null;
                                widget.player.seek(
                                  Duration(milliseconds: value.round()),
                                );
                              },
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      _format(Duration(milliseconds: currentMs)),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    Text(
                      _format(duration),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
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

/// 播放控制：上一首 / 播放暂停 / 下一首。
class PlayerControls extends StatelessWidget {
  final FnPlayerService player;
  final PlayerStylePreset stylePreset;

  const PlayerControls({
    super.key,
    required this.player,
    required this.stylePreset,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color iconColor = scheme.primary.withValues(alpha: 0.86);
    final Color buttonBg = scheme.primaryContainer.withValues(alpha: 0.92);
    final double mainButtonSize = switch (stylePreset) {
      PlayerStylePreset.poster => 72.0,
      PlayerStylePreset.classic => 64.0,
    };
    return Watch.builder(
      builder: (context) {
        final bool playing = AppPlayerState.instance.isPlayingSignal.value;
        final bool loading = AppPlayerState.instance.isLoadingSignal.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            IconButton(
              iconSize: 48,
              icon: Icon(Icons.skip_previous_rounded, color: iconColor),
              onPressed: player.previous,
            ),
            const SizedBox(width: 20),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: buttonBg,
              ),
              child: IconButton(
                iconSize: mainButtonSize,
                icon: loading
                    ? SizedBox(
                        width: mainButtonSize,
                        height: mainButtonSize,
                        child: CircularProgressIndicator(
                          strokeWidth: mainButtonSize * 0.055,
                          color: scheme.onPrimaryContainer,
                        ),
                      )
                    : Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: scheme.onPrimaryContainer,
                      ),
                onPressed: player.togglePlayPause,
              ),
            ),
            const SizedBox(width: 20),
            IconButton(
              iconSize: 48,
              icon: Icon(Icons.skip_next_rounded, color: iconColor),
              onPressed: player.next,
            ),
          ],
        );
      },
    );
  }
}

/// 底部操作栏：播放模式 / 睡眠定时 / 播放队列 / 收藏。
class BottomActions extends StatelessWidget {
  final FnPlayerService player;

  const BottomActions({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color iconColor = scheme.onSurfaceVariant.withValues(alpha: 0.85);
    return Watch.builder(
      builder: (context) {
        final AppPlayerState state = AppPlayerState.instance;
        final PlaybackMode mode = state.playbackModeSignal.value;
        final Duration? sleepRemaining = state.sleepTimerSignal.value;
        final String? sleepText = _sleepTimerText(sleepRemaining);
        final IconData modeIcon = switch (mode) {
          PlaybackMode.sequential => Icons.playlist_play_rounded,
          PlaybackMode.loop => Icons.repeat_rounded,
          PlaybackMode.single => Icons.repeat_one_rounded,
          PlaybackMode.shuffle => Icons.shuffle_rounded,
        };
        final List<Widget> actions = <Widget>[
          IconButton(
            icon: Icon(modeIcon, color: iconColor),
            onPressed: player.cyclePlayMode,
          ),
          Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: <Widget>[
              IconButton(
                icon: Icon(Icons.alarm, color: iconColor),
                onPressed: () => _showSleepTimerSheet(context),
              ),
              if (sleepText != null)
                Positioned(
                  bottom: -8,
                  child: Text(
                    sleepText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: iconColor.withValues(alpha: 0.8),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.format_list_bulleted, color: iconColor),
            onPressed: () => showPlayerPlaylistSheet(context, player),
          ),
          FavoriteButton(songSignal: state.currentSongSignal),
        ];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: actions,
          ),
        );
      },
    );
  }

  void _showSleepTimerSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SleepTimerSheet(player: player),
    );
  }
}

String? _sleepTimerText(Duration? remaining) {
  if (remaining == null) return null;
  final int minutes = (remaining.inSeconds / 60).ceil();
  if (minutes <= 0) return null;
  return '$minutes分';
}

/// 收藏按钮（服务端收藏），随 [songSignal] 切换歌曲自动刷新状态。
class FavoriteButton extends StatefulWidget {
  final Signal<SongEntity?> songSignal;

  const FavoriteButton({super.key, required this.songSignal});

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  final FeiNiuFavoriteService _favoriteService = FeiNiuFavoriteService.instance;
  bool _isFavorite = false;
  bool _loading = false;
  String? _lastGuid;

  late void Function() _unsubscribeSong;

  @override
  void initState() {
    super.initState();
    _unsubscribeSong = widget.songSignal.subscribe(_onSongChanged);
    _onSongChanged(widget.songSignal.value);
  }

  @override
  void dispose() {
    _unsubscribeSong();
    super.dispose();
  }

  void _onSongChanged(SongEntity? value) {
    final String? guid = value?.guid;
    if (guid == _lastGuid) return;
    _lastGuid = guid;
    _loadFavoriteState();
  }

  Future<void> _loadFavoriteState() async {
    final String? guid = _lastGuid;
    if (guid == null) {
      if (mounted) {
        setState(() {
          _isFavorite = false;
          _loading = false;
        });
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final Set<String> ids = await _favoriteService.getFavoriteIds();
      if (!mounted || _lastGuid != guid) return;
      setState(() {
        _isFavorite = ids.contains(guid);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFavorite() async {
    final String? guid = _lastGuid;
    if (_loading || guid == null) return;
    setState(() => _loading = true);
    try {
      if (_isFavorite) {
        await _favoriteService.unfavorite(guid);
        if (!mounted) return;
        setState(() {
          _isFavorite = false;
          _loading = false;
        });
        AppToast.show(context, '已取消收藏');
      } else {
        await _favoriteService.favorite(guid);
        if (!mounted) return;
        setState(() {
          _isFavorite = true;
          _loading = false;
        });
        AppToast.show(context, '已收藏');
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: _isFavorite
            ? Colors.deepOrangeAccent
            : scheme.onSurfaceVariant.withValues(alpha: 0.85),
      ),
      onPressed: _lastGuid == null || _loading ? null : _toggleFavorite,
    );
  }
}

Color _primaryTextColor(bool useDarkText) {
  return useDarkText
      ? Colors.black.withValues(alpha: 0.88)
      : Colors.white.withValues(alpha: 0.92);
}

Color _secondaryTextColor(bool useDarkText, double alpha) {
  return useDarkText
      ? Colors.black.withValues(alpha: alpha)
      : Colors.white.withValues(alpha: alpha);
}

/// 底部弹层公共容器：播放页渐变底 + 遮罩 + 标题栏 + 内容。
class _PlayerSheetView extends StatelessWidget {
  final double height;
  final Color maskColor;
  final Color dragHandleColor;
  final Widget header;
  final Widget body;

  const _PlayerSheetView({
    required this.height,
    required this.maskColor,
    required this.dragHandleColor,
    required this.header,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Stack(
          children: <Widget>[
            RepaintBoundary(
              child: PlayerBackground(
                songSignal: AppPlayerState.instance.currentSongSignal,
              ),
            ),
            RepaintBoundary(child: Container(color: maskColor)),
            Column(
              children: <Widget>[
                Center(
                  child: Container(
                    height: 4,
                    width: 32,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: dragHandleColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                header,
                body,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final String title;
  final Color textColor;
  final Color secondaryTextColor;

  const _SheetHeader({
    required this.title,
    required this.textColor,
    required this.secondaryTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: SizedBox(
            height: 34,
            child: Center(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          color: secondaryTextColor.withValues(alpha: 0.18),
        ),
      ],
    );
  }
}

/// 睡眠定时面板：时长滑块 + 开始 / 取消。
class _SleepTimerSheet extends StatefulWidget {
  final FnPlayerService player;

  const _SleepTimerSheet({required this.player});

  @override
  State<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<_SleepTimerSheet>
    with SignalsMixin {
  late final Signal<double> _minutes = createSignal<double>(30.0);

  @override
  void initState() {
    super.initState();
    final Duration? remaining = widget.player.remainingSleepTime;
    if (remaining != null && remaining > const Duration(minutes: 1)) {
      _minutes.value = remaining.inMinutes.clamp(5, 120).toDouble();
    }
  }

  String _formatMinutes(num minutes) {
    final int totalMinutes = minutes.round();
    final int hours = totalMinutes ~/ 60;
    final int mins = totalMinutes % 60;
    return '$hours:${mins.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool useDarkText = Theme.of(context).brightness == Brightness.light;
    final Color textColor = _primaryTextColor(useDarkText);
    final Color secondaryTextColor = _secondaryTextColor(useDarkText, 0.7);
    final Color maskColor = scheme.surface;
    final double sheetHeight = MediaQuery.sizeOf(context).height * 0.4;

    return Watch.builder(
      builder: (context) {
        final double minutes = _minutes.value;
        final bool isActive =
            AppPlayerState.instance.sleepTimerSignal.value != null;
        return SafeArea(
          child: _PlayerSheetView(
            height: sheetHeight,
            maskColor: maskColor,
            dragHandleColor: secondaryTextColor.withValues(alpha: 0.2),
            header: _SheetHeader(
              title: '定时',
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
            ),
            body: Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '定时时长',
                              style: TextStyle(color: textColor),
                            ),
                          ),
                          Text(
                            _formatMinutes(minutes),
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: minutes,
                        min: 5,
                        max: 120,
                        divisions: 115,
                        label: '${minutes.round()} 分钟',
                        onChanged: (double value) => _minutes.value = value,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(context);
                            widget.player.startSleepTimer(
                              Duration(minutes: minutes.round()),
                            );
                          },
                          child: const Text('开始定时'),
                        ),
                      ),
                      if (isActive)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Center(
                            child: TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                widget.player.cancelSleepTimer();
                              },
                              child: const Text('取消定时'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 打开播放队列面板（迷你播放器与全屏播放器共用入口）。
void showPlayerPlaylistSheet(BuildContext context, FnPlayerService player) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _PlaylistSheet(player: player),
  );
}

class _PlaylistSheet extends StatefulWidget {
  final FnPlayerService player;

  const _PlaylistSheet({required this.player});

  @override
  State<_PlaylistSheet> createState() => _PlaylistSheetState();
}

class _PlaylistSheetState extends State<_PlaylistSheet> {
  static const double _itemExtent = 64;
  late final ScrollController _controller;
  int _lastIndex = -1;

  double _calcOffset(int index, int length) {
    if (index <= 0 || length <= 0) return 0;
    final int startIndex = (index - 2).clamp(0, length - 1);
    return startIndex * _itemExtent;
  }

  @override
  void initState() {
    super.initState();
    _lastIndex = AppPlayerState.instance.currentIndexSignal.value;
    _controller = ScrollController(
      initialScrollOffset: _calcOffset(
        _lastIndex,
        AppPlayerState.instance.queueSignal.value.length,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool useDarkText = Theme.of(context).brightness == Brightness.light;
    final Color textColor = _primaryTextColor(useDarkText);
    final Color secondaryTextColor = _secondaryTextColor(useDarkText, 0.7);
    final Color maskColor = scheme.surface;
    final double sheetHeight = MediaQuery.sizeOf(context).height * 0.8;

    return Watch.builder(
      builder: (context) {
        final AppPlayerState state = AppPlayerState.instance;
        final List<SongEntity> queue = state.queueSignal.value;
        final int currentIndex = state.currentIndexSignal.value;
        final PlaybackMode mode = state.playbackModeSignal.value;
        final bool playing = state.isPlayingSignal.value;
        final int total = queue.length;
        final int current = currentIndex >= 0 ? currentIndex + 1 : 0;
        if (currentIndex != _lastIndex && currentIndex >= 0) {
          _lastIndex = currentIndex;
          final double offset = _calcOffset(_lastIndex, total);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_controller.hasClients) {
              _controller.animateTo(
                offset,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
              );
            }
          });
        }

        return SafeArea(
          child: _PlayerSheetView(
            height: sheetHeight,
            maskColor: maskColor,
            dragHandleColor: secondaryTextColor.withValues(alpha: 0.2),
            header: _PlaylistHeader(
              total: total,
              current: current,
              mode: mode,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              accent: scheme.primary,
              onClear: widget.player.clear,
              onCycleMode: widget.player.cyclePlayMode,
            ),
            body: Expanded(
              child: total == 0
                  ? Center(
                      child: Text(
                        '暂无歌曲',
                        style: TextStyle(color: secondaryTextColor),
                      ),
                    )
                  : RepaintBoundary(
                      child: ReorderableListView.builder(
                        scrollController: _controller,
                        itemExtent: _itemExtent,
                        buildDefaultDragHandles: false,
                        proxyDecorator: (Widget child, int index,
                            Animation<double> animation) {
                          return AnimatedBuilder(
                            animation: animation,
                            builder: (context, Widget? child) {
                              final double animValue = Curves.easeInOut
                                  .transform(animation.value);
                              final double elevation = ui.lerpDouble(
                                0,
                                6,
                                animValue,
                              )!;
                              return Material(
                                elevation: elevation,
                                color: Colors.transparent,
                                shadowColor: Colors.black.withValues(alpha: 0.3),
                                child: child,
                              );
                            },
                            child: child,
                          );
                        },
                        onReorderItem: (int oldIndex, int newIndex) {
                          // 随机模式下队列顺序无意义，禁用拖拽排序。
                          if (mode == PlaybackMode.shuffle) return;
                          widget.player.move(oldIndex, newIndex);
                        },
                        itemCount: total,
                        itemBuilder: (context, index) {
                          if (index < 0 || index >= queue.length) {
                            return const SizedBox.shrink();
                          }
                          final SongEntity song = queue[index];
                          final bool isCurrent = index == currentIndex;
                          return RepaintBoundary(
                            key: ValueKey('${song.guid}_$index'),
                            child: _QueueItem(
                              song: song,
                              index: index,
                              isCurrent: isCurrent,
                              playing: playing,
                              accent: scheme.primary,
                              textColor: textColor,
                              secondaryTextColor: secondaryTextColor,
                              onTap: () => widget.player.skipTo(index),
                              onRemove: () => widget.player.removeAt(index),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  final int total;
  final int current;
  final PlaybackMode mode;
  final Color textColor;
  final Color secondaryTextColor;
  final Color accent;
  final VoidCallback onClear;
  final VoidCallback onCycleMode;

  const _PlaylistHeader({
    required this.total,
    required this.current,
    required this.mode,
    required this.textColor,
    required this.secondaryTextColor,
    required this.accent,
    required this.onClear,
    required this.onCycleMode,
  });

  @override
  Widget build(BuildContext context) {
    final (IconData modeIcon, String modeLabel) = switch (mode) {
      PlaybackMode.sequential => (Icons.playlist_play_rounded, '顺序播放'),
      PlaybackMode.loop => (Icons.repeat_rounded, '列表循环'),
      PlaybackMode.single => (Icons.repeat_one_rounded, '单曲循环'),
      PlaybackMode.shuffle => (Icons.shuffle_rounded, '随机播放'),
    };
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '播放队列',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    InkWell(
                      onTap: onCycleMode,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 2, right: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(modeIcon, size: 16, color: secondaryTextColor),
                            const SizedBox(width: 5),
                            Text(
                              '$modeLabel · $current/$total',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onClear,
                style: TextButton.styleFrom(
                  foregroundColor: secondaryTextColor,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  Icons.delete_sweep_rounded,
                  size: 19,
                  color: secondaryTextColor,
                ),
                label: Text(
                  '清空',
                  style: TextStyle(fontSize: 13, color: secondaryTextColor),
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          color: secondaryTextColor.withValues(alpha: 0.18),
        ),
      ],
    );
  }
}

/// 播放队列单行：封面 + 标题 / 歌手，当前曲高亮并显示动效音量条。
class _QueueItem extends StatelessWidget {
  final SongEntity song;
  final int index;
  final bool isCurrent;
  final bool playing;
  final Color accent;
  final Color textColor;
  final Color secondaryTextColor;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _QueueItem({
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.playing,
    required this.accent,
    required this.textColor,
    required this.secondaryTextColor,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final Color titleColor = isCurrent ? accent : textColor;
    final Color artistColor = isCurrent
        ? accent.withValues(alpha: 0.78)
        : secondaryTextColor.withValues(alpha: 0.82);
    final String artist = song.artistDisplay?.trim().isEmpty == true
        ? '未知歌手'
        : (song.artistDisplay ?? '未知歌手');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Material(
        color: isCurrent ? accent.withValues(alpha: 0.13) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
            child: Row(
              children: <Widget>[
                _buildCover(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        song.title.trim().isEmpty ? '未知歌曲' : song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 15,
                          fontWeight: isCurrent
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: artistColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.close_rounded,
                    color: secondaryTextColor.withValues(alpha: 0.8),
                    size: 20,
                  ),
                  onPressed: onRemove,
                ),
                ReorderableDelayedDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: secondaryTextColor.withValues(alpha: 0.55),
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover() {
    const double size = 44;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ArtworkWidget(
            imageUrl: ApiClient.instance.coverUrl(song.coverId),
            size: size,
            borderRadius: BorderRadius.circular(8),
          ),
          if (isCurrent)
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.black.withValues(alpha: 0.38),
              ),
              child: Center(
                child: PlayingBars(color: Colors.white, animating: playing),
              ),
            ),
        ],
      ),
    );
  }
}

/// 海报模式播放控制：模式 + 上一首 / 播放 / 下一首。
class PosterControls extends StatelessWidget {
  final FnPlayerService player;

  const PosterControls({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color iconColor = scheme.onSurface.withValues(alpha: 0.72);
    return Watch.builder(
      builder: (context) {
        final bool playing = AppPlayerState.instance.isPlayingSignal.value;
        final PlaybackMode mode = AppPlayerState.instance.playbackModeSignal.value;
        final IconData modeIcon = switch (mode) {
          PlaybackMode.sequential => Icons.playlist_play_rounded,
          PlaybackMode.loop => Icons.repeat_rounded,
          PlaybackMode.single => Icons.repeat_one_rounded,
          PlaybackMode.shuffle => Icons.shuffle_rounded,
        };
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            IconButton(
              iconSize: 30,
              color: iconColor,
              icon: Icon(modeIcon),
              onPressed: player.cyclePlayMode,
            ),
            IconButton(
              iconSize: 40,
              color: iconColor,
              icon: const Icon(Icons.skip_previous_rounded),
              onPressed: player.previous,
            ),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.onSurface,
              ),
              child: IconButton(
                iconSize: 36,
                color: scheme.surface,
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                onPressed: player.togglePlayPause,
              ),
            ),
            IconButton(
              iconSize: 40,
              color: iconColor,
              icon: const Icon(Icons.skip_next_rounded),
              onPressed: player.next,
            ),
          ],
        );
      },
    );
  }
}
