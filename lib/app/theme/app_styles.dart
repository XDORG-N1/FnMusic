import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// 应用级滚动行为：启用鼠标拖拽滚动，并正确处理 edge-to-edge 下的 padding。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// 自定义页面切换过渡：轻微的滑入 + 淡入。
class CoverPageTransitionsBuilder extends PageTransitionsBuilder {
  const CoverPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Offset begin = const Offset(1, 0); // 从右侧滑入
    final Animatable<Offset> tween =
        Tween<Offset>(begin: begin, end: Offset.zero).chain(
      CurveTween(curve: Curves.easeOutCubic),
    );
    return SlideTransition(
      position: animation.drive(tween),
      child: FadeTransition(opacity: animation, child: child),
    );
  }
}

/// 主题表面扩展：为面板 / 玻璃卡片提供统一配色。
extension AppThemeSurfaceX on ColorScheme {
  Color get appPanelColor =>
      brightness == Brightness.light
          ? AppPanelColors.light
          : AppPanelColors.dark;

  Color get appPanelBorderColor =>
      brightness == Brightness.light
          ? AppPanelColors.lightBorder
          : AppPanelColors.darkBorder;

  Color get appPanelShadowColor => brightness == Brightness.light
      ? Colors.black.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: 0.5);
}
