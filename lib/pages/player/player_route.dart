import 'package:flutter/material.dart';

import '../../app/router/app_router.dart';
import 'player_page.dart';

/// 打开全屏播放页的底部滑入路由（含轻微缩放 + 淡入），不遮挡整页背景。
Route<void> buildPlayerPageRoute() {
  return PageRouteBuilder<void>(
    settings: const RouteSettings(name: AppRoutes.player),
    opaque: false,
    barrierColor: Colors.transparent,
    pageBuilder: (BuildContext context, Animation<double> animation,
            Animation<double> secondaryAnimation) =>
        const PlayerPage(),
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (BuildContext context, Animation<double> animation,
        Animation<double> secondaryAnimation, Widget child) {
      final CurvedAnimation curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final Animation<Offset> offset = Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(curved);
      final Animation<double> scale = Tween<double>(begin: 0.97, end: 1.0)
          .animate(curved);
      final Animation<double> fade = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      );
      return SlideTransition(
        position: offset,
        child: FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        ),
      );
    },
  );
}

/// 打开全屏播放页（迷你播放器 / 首页等入口）。
void openPlayerPage(BuildContext context) {
  Navigator.of(context).push(buildPlayerPageRoute());
}
