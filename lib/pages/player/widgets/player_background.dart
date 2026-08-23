import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../../app/services/feiniu/api_client.dart';
import '../../../app/state/song_state.dart';

/// 播放器背景 / 封面相关设置（原设计 PlayerBackgroundSettings）。
class PlayerBackgroundSettings {
  static const String _prefsPlaybackThemeMode = 'setting_playback_theme_mode';
  static const String _prefsDynamicGradientEnabled = 'dynamic_gradient_enabled';
  static const String _prefsSaturation = 'gradient_saturation';
  static const String _prefsHueShift = 'gradient_hue_shift';
  static const String _prefsRoundCover = 'player_round_cover';
  static const String _prefsRotateCover = 'player_rotate_cover';

  static final ValueNotifier<ThemeMode> playbackThemeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);
  static final ValueNotifier<bool> dynamicGradientEnabled =
      ValueNotifier<bool>(true);
  static final ValueNotifier<double> saturation = ValueNotifier<double>(1.2);
  static final ValueNotifier<double> hueShift = ValueNotifier<double>(120.0);
  static final ValueNotifier<bool> roundCover = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> rotateCover = ValueNotifier<bool>(true);

  static Future<void>? _loading;

  static Future<void> ensureLoaded() => _loading ??= _doLoad();

  static Future<void> _doLoad() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    playbackThemeMode.value = _modeFromString(
      prefs.getString(_prefsPlaybackThemeMode),
    );
    dynamicGradientEnabled.value =
        prefs.getBool(_prefsDynamicGradientEnabled) ?? true;
    saturation.value = prefs.getDouble(_prefsSaturation) ?? 1.2;
    hueShift.value = prefs.getDouble(_prefsHueShift) ?? 120.0;
    roundCover.value = prefs.getBool(_prefsRoundCover) ?? true;
    rotateCover.value =
        (prefs.getBool(_prefsRotateCover) ?? true) && roundCover.value;
  }

  static ThemeMode _modeFromString(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static Future<void> setPlaybackThemeMode(ThemeMode mode) async {
    playbackThemeMode.value = mode;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPlaybackThemeMode, mode.name);
  }

  static Future<void> setDynamicGradientEnabled(bool enabled) async {
    dynamicGradientEnabled.value = enabled;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsDynamicGradientEnabled, enabled);
  }

  static Future<void> setRoundCover(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsRoundCover, value);
    roundCover.value = value;
    // 圆形封面与旋转封面联动：打开圆形时开启旋转，关闭圆形时关闭旋转。
    if (value && !rotateCover.value) {
      await prefs.setBool(_prefsRotateCover, true);
      rotateCover.value = true;
    } else if (!value && rotateCover.value) {
      await prefs.setBool(_prefsRotateCover, false);
      rotateCover.value = false;
    }
  }

  static Future<void> setRotateCover(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsRotateCover, value);
    rotateCover.value = value;
  }
}

/// 播放页整体主题覆盖：跟随"播放页主题模式"设置切换亮暗。
class PlayerTheme extends StatelessWidget {
  final Widget child;

  const PlayerTheme({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: PlayerBackgroundSettings.playbackThemeMode,
      builder: (context, _) {
        final ThemeMode mode = PlayerBackgroundSettings.playbackThemeMode.value;
        final Brightness brightness = playerBrightnessForMode(context, mode);
        final ThemeData base = Theme.of(context);
        if (base.brightness == brightness) return child;
        final ColorScheme scheme = ColorScheme.fromSeed(
          seedColor: base.colorScheme.primary,
          brightness: brightness,
        );
        return Theme(
          data: base.copyWith(
            brightness: brightness,
            colorScheme: scheme,
            iconTheme: base.iconTheme.copyWith(color: scheme.onSurface),
            textTheme: base.textTheme.apply(
              bodyColor: scheme.onSurface,
              displayColor: scheme.onSurface,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

/// 播放页背景：取当前歌曲封面的主色做"极光"渐变底。
class PlayerBackground extends StatefulWidget {
  final Signal<SongEntity?> songSignal;

  const PlayerBackground({super.key, required this.songSignal});

  @override
  State<PlayerBackground> createState() => _PlayerBackgroundState();
}

class _PlayerBackgroundState extends State<PlayerBackground> {
  static const int _dominantCacheLimit = 128;
  static final Map<String, Color> _dominantCache = <String, Color>{};
  static final Map<String, Future<Color?>> _dominantInflight =
      <String, Future<Color?>>{};

  String? _lastCoverId;
  Color? _dominantColor;

  @override
  void initState() {
    super.initState();
    PlayerBackgroundSettings.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Watch.builder(
      builder: (context) {
        final SongEntity? song = widget.songSignal.value;
        _handleCoverChange(song?.coverId);
        return AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            PlayerBackgroundSettings.playbackThemeMode,
            PlayerBackgroundSettings.dynamicGradientEnabled,
            PlayerBackgroundSettings.saturation,
            PlayerBackgroundSettings.hueShift,
          ]),
          builder: (context, _) {
            final bool dynamicEnabled =
                PlayerBackgroundSettings.dynamicGradientEnabled.value;
            final double saturation = PlayerBackgroundSettings.saturation.value;
            final double hueShift = PlayerBackgroundSettings.hueShift.value;
            final bool preferLight =
                playerBrightnessForMode(
                  context,
                  PlayerBackgroundSettings.playbackThemeMode.value,
                ) ==
                Brightness.light;
            final Color surface = _tintSurface(scheme.surface, preferLight);
            final Color dominant = _dominantColor ?? scheme.primary;
            final Color baseColor = _adjustBackground(dominant, preferLight);
            if (dynamicEnabled) {
              return _DynamicGradientBackground(
                baseColor: baseColor,
                saturation: saturation,
                hueShift: hueShift,
              );
            }
            return _FallbackBackground(
              color: Color.lerp(surface, baseColor, 0.58) ?? surface,
            );
          },
        );
      },
    );
  }

  void _handleCoverChange(String? coverId) {
    if (_lastCoverId == coverId) return;
    _lastCoverId = coverId;
    _dominantColor = null;
    if (coverId == null || coverId.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDominantColor(coverId);
    });
  }

  Future<void> _loadDominantColor(String coverId) async {
    final Color? cached = _dominantCache[coverId];
    if (cached != null) {
      if (!mounted) return;
      setState(() => _dominantColor = cached);
      return;
    }
    final Future<Color?> future = _dominantInflight[coverId] ??
        (_dominantInflight[coverId] = _computeDominantColor(coverId));
    final Color? color = await future;
    _dominantInflight.remove(coverId);
    if (!mounted) return;
    if (_lastCoverId != coverId) return;
    if (color != null) {
      if (_dominantCache.length >= _dominantCacheLimit) {
        _dominantCache.remove(_dominantCache.keys.first);
      }
      _dominantCache[coverId] = color;
    }
    setState(() => _dominantColor = color);
  }

  Future<Color?> _computeDominantColor(String coverId) async {
    try {
      final ApiClient api = ApiClient.instance;
      final String? url = api.coverUrl(coverId, size: 40);
      if (url == null) return null;
      final Dio dio = Dio();
      final Response<dynamic> response = await dio.get<dynamic>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: api.authHeaders(),
        ),
      );
      final Uint8List bytes = response.data as Uint8List;
      return await averageImageColor(bytes);
    } catch (_) {
      return null;
    }
  }
}

/// 图片字节的平均主色（缩小后采样，速度优先）。
Future<Color?> averageImageColor(Uint8List bytes) async {
  if (bytes.isEmpty) return null;
  final ui.Codec codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: 40,
    targetHeight: 40,
  );
  final ui.FrameInfo frame = await codec.getNextFrame();
  final ui.Image image = frame.image;
  final ByteData? data = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  if (data == null) return null;
  final Uint8List list = data.buffer.asUint8List();
  int r = 0;
  int g = 0;
  int b = 0;
  int count = 0;
  for (int i = 0; i + 3 < list.length; i += 4) {
    final int a = list[i + 3];
    if (a < 10) continue;
    r += list[i];
    g += list[i + 1];
    b += list[i + 2];
    count += 1;
  }
  if (count == 0) return null;
  return Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);
}

Brightness playerBrightnessForMode(BuildContext context, ThemeMode mode) {
  if (mode == ThemeMode.system) {
    return Theme.of(context).brightness;
  }
  return mode == ThemeMode.light ? Brightness.light : Brightness.dark;
}

Color _adjustBackground(Color color, bool preferLightBackground) {
  final HSLColor hsl = HSLColor.fromColor(color);
  double lightness = hsl.lightness;
  if (preferLightBackground) {
    if (lightness < 0.78) lightness = 0.78;
    if (lightness > 0.92) lightness = 0.92;
  } else {
    if (lightness > 0.32) lightness = 0.32;
    if (lightness < 0.18) lightness = 0.18;
  }
  return hsl.withLightness(lightness).toColor();
}

Color _tintSurface(Color surface, bool preferLight) {
  return Color.lerp(surface, preferLight ? Colors.white : Colors.black, 0.18)!;
}

class _FallbackBackground extends StatelessWidget {
  final Color color;

  const _FallbackBackground({required this.color});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            color,
            Color.lerp(color, scheme.surfaceContainer, 0.22) ?? color,
            Color.lerp(color, scheme.surface, 0.12) ?? color,
          ],
          stops: const <double>[0.0, 0.55, 1.0],
        ),
      ),
    );
  }
}

class _DynamicGradientBackground extends StatefulWidget {
  final Color baseColor;
  final double saturation;
  final double hueShift;

  const _DynamicGradientBackground({
    required this.baseColor,
    required this.saturation,
    required this.hueShift,
  });

  @override
  State<_DynamicGradientBackground> createState() =>
      _DynamicGradientBackgroundState();
}

class _DynamicGradientBackgroundState
    extends State<_DynamicGradientBackground>
    with SingleTickerProviderStateMixin {
  // ~30fps over the 22s loop：量化动画相位，让 painter 的 shouldRepaint
  // 在步进之间跳过整屏重绘，而缓慢漂移视觉上依然平滑。
  static const int _phaseSteps = 22 * 30;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final double t =
              (_controller.value * _phaseSteps).floorToDouble() / _phaseSteps;
          return CustomPaint(
            size: Size.infinite,
            painter: _AuroraPainter(
              t: t,
              base: widget.baseColor,
              saturation: widget.saturation,
              hueShift: widget.hueShift,
              isDark: isDark,
            ),
          );
        },
      ),
    );
  }
}

/// 流动的"极光"背景：基色渐变上叠加漂移的径向色斑。
class _AuroraPainter extends CustomPainter {
  final double t;
  final Color base;
  final double saturation;
  final double hueShift;
  final bool isDark;

  _AuroraPainter({
    required this.t,
    required this.base,
    required this.saturation,
    required this.hueShift,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final HSLColor hsl = HSLColor.fromColor(base);
    final double s = (hsl.saturation * saturation).clamp(0.18, 1.0);

    // 基色渐变填充。
    final Color bgTop = hsl.withSaturation(s).toColor();
    final Color bgBottom = hsl
        .withSaturation((s * 0.85).clamp(0.0, 1.0))
        .withLightness(
          (hsl.lightness + (isDark ? -0.04 : 0.03)).clamp(0.0, 1.0),
        )
        .toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, <Color>[
          bgTop,
          bgBottom,
        ]),
    );

    final List<Color> colors = _palette(hsl, s);
    final double blobAlpha = isDark ? 0.50 : 0.34;
    for (int i = 0; i < colors.length; i++) {
      final Offset center = _blobCenter(i, size);
      final double radius =
          size.shortestSide *
          (0.62 + 0.10 * math.sin(2 * math.pi * t + i * 1.3));
      final Color c = colors[i];
      final Paint paint = Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          <Color>[
            c.withValues(alpha: blobAlpha),
            c.withValues(alpha: blobAlpha * 0.45),
            c.withValues(alpha: 0.0),
          ],
          const <double>[0.0, 0.5, 1.0],
        );
      canvas.drawCircle(center, radius, paint);
    }
  }

  Offset _blobCenter(int i, Size size) {
    final double phase = i * 1.7;
    final double fx = 0.55 + i * 0.13;
    final double fy = 0.70 + i * 0.11;
    final double cx =
        size.width * (0.5 + 0.40 * math.sin(2 * math.pi * t * fx + phase));
    final double cy =
        size.height *
        (0.45 + 0.38 * math.cos(2 * math.pi * t * fy + phase * 1.3));
    return Offset(cx, cy);
  }

  List<Color> _palette(HSLColor hsl, double s) {
    final double sat = s.clamp(0.28, 1.0);
    Color mk(double deltaHue, double deltaLight) {
      return HSLColor.fromAHSL(
        1.0,
        (hsl.hue + deltaHue) % 360,
        sat,
        (hsl.lightness + deltaLight).clamp(isDark ? 0.18 : 0.62, 0.96),
      ).toColor();
    }

    final double shift = hueShift.clamp(0.0, 180.0);
    return <Color>[
      mk(0, isDark ? 0.06 : 0.0),
      mk(shift, isDark ? 0.0 : 0.04),
      mk(-shift, isDark ? 0.10 : -0.02),
      mk(shift * 1.7, isDark ? 0.03 : 0.02),
    ];
  }

  @override
  bool shouldRepaint(_AuroraPainter old) {
    return old.t != t ||
        old.base != base ||
        old.saturation != saturation ||
        old.hueShift != hueShift ||
        old.isDark != isDark;
  }
}
