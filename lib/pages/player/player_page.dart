import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_model.dart' as fl;
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/router/app_router.dart';
import '../../app/services/feiniu/api_client.dart';
import '../../app/services/lyrics/lyrics_service.dart';
import '../../app/services/player_service.dart';
import '../../app/state/layout_settings.dart';
import '../../app/state/player_state.dart';
import '../../app/state/player_style_settings.dart';
import '../../app/state/song_state.dart';
import '../../components/common/artwork_widget.dart';
import '../../components/player/lyric_preview.dart';
import 'lyrics/lyric_view.dart';
import 'widgets/player_background.dart';
import 'widgets/player_bottom_panel.dart';
import 'widgets/player_header.dart';

/// 全屏播放器页面。
///
/// 结构：拖拽下拉关闭 + 渐变背景（[PlayerBackground]）+ 主题覆盖（[PlayerTheme]）
/// + 经典 / 海报两种布局。底部面板与播放器样式设置由 [PlayerStyleSettings] 控制。
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with SingleTickerProviderStateMixin {
  final FnPlayerService _player = FnPlayerService.instance;

  /// 封面页 / 歌词页左右滑动的页码控制器。
  late final PageController _pageController = PageController();

  /// 当前下拉位移（用于 Transform.translate / Opacity / ClipRRect）。
  final ValueNotifier<double> _dismissOffset = ValueNotifier<double>(0);

  /// 无界动画控制器：驱动下拉关闭动画（unbounded 才能在任意起点收放）。
  late final AnimationController _dismissController;
  double _dragStartOffset = 0;
  Offset _dragStartPosition = Offset.zero;
  bool _closing = false;

  /// 下拉超过屏幕高度的这一比例即松手关闭。
  double get _dismissThreshold => MediaQuery.sizeOf(context).height * 0.3;

  Signal<SongEntity?> get _songSignal => AppPlayerState.instance.currentSongSignal;

  @override
  void initState() {
    super.initState();
    _dismissController = AnimationController.unbounded(vsync: this);
    PlayerStyleSettings.ensureLoaded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLayoutSettings.playerRouteActive.value = true;
    });
  }

  @override
  void dispose() {
    _dismissController.dispose();
    _pageController.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLayoutSettings.playerRouteActive.value = false;
    });
    super.dispose();
  }

  /// 切换到歌词页（第 1 页）。
  void _openLyricsPage() {
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  // ---------- 拖拽下拉关闭 ----------

  void _handleDismissDragStart(DragStartDetails details) {
    if (_closing) return;
    _dismissController.stop();
    _dragStartOffset = _dismissOffset.value;
    _dragStartPosition = details.globalPosition;
  }

  void _handleDismissDragUpdate(DragUpdateDetails details) {
    if (_closing) return;
    final double dy = details.globalPosition.dy - _dragStartPosition.dy;
    _dismissOffset.value = math.max(0, _dragStartOffset + dy);
  }

  void _handleDismissDragEnd(DragEndDetails details) {
    if (_closing) return;
    final double velocity = details.primaryVelocity ?? 0;
    if (_dismissOffset.value > _dismissThreshold || velocity > 1000) {
      _closePlayer();
    } else {
      _animateDismissOffset(0);
    }
  }

  void _handleDismissDragCancel() {
    if (_closing) return;
    _animateDismissOffset(0);
  }

  Future<void> _animateDismissOffset(double target) {
    final double begin = _dismissOffset.value;
    if (begin == target || _closing) return Future<void>.value();
    _dismissController.stop();
    _dismissController.value = 0;
    final Animation<double> animation = Tween<double>(begin: begin, end: target)
        .animate(
      CurvedAnimation(
        parent: _dismissController,
        curve: Curves.easeOutCubic,
      ),
    );
    void listener() {
      _dismissOffset.value = animation.value;
    }

    _dismissController.addListener(listener);
    return _dismissController
        .animateTo(1, duration: const Duration(milliseconds: 220))
        .whenComplete(() {
      _dismissController.removeListener(listener);
      _dismissOffset.value = target;
    });
  }

  /// 下拉关闭：先动画滑出，再 pop；根路由时退回首页。
  Future<void> _closePlayer() async {
    if (_closing) return;
    _closing = true;
    await _animateDismissOffset(MediaQuery.sizeOf(context).height);
    if (!mounted) return;
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed(AppRoutes.home);
    }
  }

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _closePlayer();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: ValueListenableBuilder<double>(
          valueListenable: _dismissOffset,
          builder: (context, offset, _) {
            final double progress =
                (offset / _dismissThreshold).clamp(0.0, 1.0);
            return Transform.translate(
              offset: Offset(0, offset),
              child: Opacity(
                opacity: 1 - progress * 0.08,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(progress * 24),
                  child: _buildMainContent(context),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: RepaintBoundary(
            child: PlayerBackground(songSignal: _songSignal),
          ),
        ),
        RepaintBoundary(
          child: PlayerTheme(
            child: ValueListenableBuilder<PlayerStylePreset>(
              valueListenable: PlayerStyleSettings.stylePreset,
              builder: (context, preset, _) {
                final bool isPoster = preset == PlayerStylePreset.poster;
                return SafeArea(
                  top: !isPoster,
                  bottom: false,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragStart: _handleDismissDragStart,
                    onVerticalDragUpdate: _handleDismissDragUpdate,
                    onVerticalDragEnd: _handleDismissDragEnd,
                    onVerticalDragCancel: _handleDismissDragCancel,
                    child: Column(
                      children: <Widget>[
                        if (isPoster)
                          const SizedBox(height: 16)
                        else
                          PlayerHeader(songSignal: _songSignal),
                        Expanded(
                          // 第 0 页封面布局，第 1 页歌词页。
                          child: PageView(
                            controller: _pageController,
                            onPageChanged: (int page) {
                              // 离开歌词页（切回封面页）时释放全局拖动选中状态：
                              // LyricController 是全局单例，歌词页拖动选中后若直接
                              // 横滑回封面页，残留状态会传染给共享 controller 的
                              // 歌词预览（底栏迷你歌词/海报预览）。
                              if (page != 1) {
                                LyricsService.instance.controller
                                    .stopSelection();
                              }
                            },
                            children: <Widget>[
                              if (isPoster)
                                _PosterPlayerLayout(
                                  player: _player,
                                  songSignal: _songSignal,
                                  onTapLyrics: _openLyricsPage,
                                )
                              else
                                _MobilePlayerLayout(
                                  player: _player,
                                  songSignal: _songSignal,
                                  stylePreset: preset,
                                  onTapLyrics: _openLyricsPage,
                                ),
                              if (isPoster)
                                // SafeArea 关闭（封面延伸到屏幕边缘），歌词页
                                // 手动补回顶部/底部 inset，防止歌词行滑入
                                // 状态栏或系统导航栏下方。
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: MediaQuery.paddingOf(context).top,
                                    bottom: MediaQuery.paddingOf(context).bottom,
                                  ),
                                  child: const PlayerLyricsView(
                                    showControls: true,
                                    fadeEdges: true,
                                  ),
                                )
                              else
                                const PlayerLyricsView(
                                  showControls: true,
                                  fadeEdges: true,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (Platform.isWindows)
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, left: 8),
                child: BackButton(onPressed: _closePlayer),
              ),
            ),
          ),
      ],
    );
  }
}

/// 经典布局：居中封面 + 底部控制面板（含迷你歌词预览）。
class _MobilePlayerLayout extends StatelessWidget {
  final FnPlayerService player;
  final Signal<SongEntity?> songSignal;
  final PlayerStylePreset stylePreset;
  final VoidCallback onTapLyrics;

  const _MobilePlayerLayout({
    required this.player,
    required this.songSignal,
    required this.stylePreset,
    required this.onTapLyrics,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: Center(child: _PlayerArtwork(songSignal: songSignal)),
        ),
        PlayerBottomPanel(
          player: player,
          stylePreset: stylePreset,
          onTapLyrics: onTapLyrics,
        ),
      ],
    );
  }
}

/// 封面区（经典布局中央）：圆形 / 圆角 + 可选旋转。
class _PlayerArtwork extends StatelessWidget {
  final Signal<SongEntity?> songSignal;

  const _PlayerArtwork({required this.songSignal});

  @override
  Widget build(BuildContext context) {
    return Watch.builder(
      builder: (context) {
        final SongEntity? song = songSignal.value;
        final bool isPlaying = AppPlayerState.instance.isPlayingSignal.value;
        return AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            PlayerBackgroundSettings.roundCover,
            PlayerBackgroundSettings.rotateCover,
          ]),
          builder: (context, _) {
            final bool roundCover = PlayerBackgroundSettings.roundCover.value;
            final bool rotateCover = PlayerBackgroundSettings.rotateCover.value;
            final Widget artwork = _buildArtwork(song, roundCover);
            if (rotateCover && roundCover && isPlaying) {
              return _RotatingArtwork(child: artwork);
            }
            return artwork;
          },
        );
      },
    );
  }

  Widget _buildArtwork(SongEntity? song, bool roundCover) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double size = constraints.biggest.shortestSide;
          return SizedBox(
            width: size,
            height: size,
            child: ArtworkWidget(
              imageUrl: ApiClient.instance.coverUrl(song?.coverId),
              size: size,
              borderRadius: roundCover
                  ? BorderRadius.circular(size / 2)
                  : BorderRadius.circular(12),
            ),
          );
        },
      ),
    );
  }
}

/// 旋转封面：20s 一圈，持续旋转。
class _RotatingArtwork extends StatefulWidget {
  final Widget child;

  const _RotatingArtwork({required this.child});

  @override
  State<_RotatingArtwork> createState() => _RotatingArtworkState();
}

class _RotatingArtworkState extends State<_RotatingArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) =>
          RotationTransition(turns: _controller, child: child),
      child: widget.child,
    );
  }
}

/// 海报布局：大封面铺顶 + 歌词预览 + 底部信息 / 进度 / 控制。
class _PosterPlayerLayout extends StatelessWidget {
  final FnPlayerService player;
  final Signal<SongEntity?> songSignal;
  final VoidCallback onTapLyrics;

  const _PosterPlayerLayout({
    required this.player,
    required this.songSignal,
    required this.onTapLyrics,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double heroHeight =
        (MediaQuery.sizeOf(context).height * 0.40).clamp(240.0, 400.0);
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    final double bottomPad = bottomInset > 20 ? bottomInset + 8 : 18;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 固定高度封面区（不再弹性：底部信息区保持稳定高度）。
        SizedBox(
          height: heroHeight,
          child: Center(
            child: _PosterArtwork(
              songSignal: songSignal,
              heroHeight: heroHeight,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Watch.builder(
                  builder: (context) {
                    final SongEntity? song = songSignal.value;
                    final String title = song?.title.trim().isEmpty == true
                        ? '未知歌曲'
                        : (song?.title ?? '未知歌曲');
                    return Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                child: Watch.builder(
                  builder: (context) {
                    final SongEntity? song = songSignal.value;
                    final String artist =
                        song?.artistDisplay?.trim().isEmpty == true
                        ? '未知歌手'
                        : (song?.artistDisplay ?? '未知歌手');
                    return Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    );
                  },
                ),
              ),
              // 歌词预览：弹性占满「标题之下、控制区之上」的剩余空间，
              // 空间不足时收缩。点击跳转到歌词页（与底栏迷你歌词一致）。
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTapLyrics,
                  child: _PosterLyricsPreview(),
                ),
              ),
              _PosterMetaRow(player: player, songSignal: songSignal),
              const SizedBox(height: 8),
              PlayerSeekBar(player: player),
              const SizedBox(height: 12),
              PosterControls(player: player),
              SizedBox(height: bottomPad),
            ],
          ),
        ),
      ],
    );
  }
}

/// 海报布局的歌词预览（标题之下、控制区之上）。
class _PosterLyricsPreview extends StatelessWidget {
  const _PosterLyricsPreview();

  @override
  Widget build(BuildContext context) {
    return Watch.builder(
      builder: (context) {
        final LyricsService lyrics = LyricsService.instance;
        final LyricsSnapshot snap = lyrics.snapshotSignal.value;
        final fl.LyricModel? model = lyrics.lyricModelSignal.value;
        final List<fl.LyricLine> lines =
            model?.lines ?? const <fl.LyricLine>[];
        // 加载新歌歌词时保持空白，歌词就绪后直接展示真实行。
        if (snap.status == LyricsLoadStatus.loading && lines.isEmpty) {
          return const SizedBox.shrink();
        }
        if (lines.isEmpty) {
          // 标题/歌手已在上方展示，这里用中性占位，避免重复。
          return const Align(
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PosterLyricLine(text: '暂无歌词', active: true),
                SizedBox(height: 8),
                _PosterLyricLine(text: '纯音乐或未匹配到歌词', active: false),
                SizedBox(height: 8),
                _PosterLyricLine(text: ' ', active: false),
              ],
            ),
          );
        }

        // 复用歌词页的 LyricView 渲染管线，保证与歌词页一致的流畅逐字动画。
        // LayoutBuilder 读取实际可用高度：海报布局中该预览区是弹性空间，
        // 矮屏/大字体机型下会收缩而不是溢出。外层 Container 已带水平内边距，
        // contentPadding: EdgeInsets.zero 让歌词与标题左对齐。
        return LayoutBuilder(
          builder: (context, constraints) {
            final double h = constraints.hasBoundedHeight
                ? constraints.maxHeight
                : 118.0;
            return LyricPreview(
              height: h.clamp(0.0, 1000.0),
              textAlign: TextAlign.start,
              contentAlignment: CrossAxisAlignment.start,
              showTranslation: true,
              fontSize: 15,
              activeFontSize: 18,
              contentPadding: EdgeInsets.zero,
              fadeEdges: true,
            );
          },
        );
      },
    );
  }
}

class _PosterLyricLine extends StatelessWidget {
  final String text;
  final bool active;

  const _PosterLyricLine({required this.text, required this.active});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: active
            ? scheme.onSurface.withValues(alpha: 0.92)
            : scheme.onSurfaceVariant.withValues(alpha: 0.68),
        fontSize: active ? 18 : 15,
        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
        height: 1.15,
      ),
    );
  }
}

/// 海报布局信息行：收藏 + 播放队列。
class _PosterMetaRow extends StatelessWidget {
  final FnPlayerService player;
  final Signal<SongEntity?> songSignal;

  const _PosterMetaRow({required this.player, required this.songSignal});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        FavoriteButton(songSignal: songSignal),
        IconButton(
          icon: const Icon(Icons.format_list_bulleted_rounded),
          onPressed: () => showPlayerPlaylistSheet(context, player),
        ),
      ],
    );
  }
}

/// 海报大封面：方形铺满可用空间，顶部做渐隐融入背景。
class _PosterArtwork extends StatelessWidget {
  final Signal<SongEntity?> songSignal;
  final double heroHeight;

  const _PosterArtwork({
    required this.songSignal,
    required this.heroHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Watch.builder(
      builder: (context) {
        final SongEntity? song = songSignal.value;
        final double size = math.min(
          MediaQuery.sizeOf(context).width,
          heroHeight,
        );
        return SizedBox(
          width: size,
          height: size,
          child: ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (Rect bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.white,
              ],
              stops: <double>[0.0, 0.62, 0.88, 1.0],
            ).createShader(bounds),
            child: ArtworkWidget(
              imageUrl: ApiClient.instance.coverUrl(song?.coverId),
              size: size,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      },
    );
  }
}
