import 'package:flutter/foundation.dart';

/// 布局相关全局状态。
///
/// 参考项目含 TV / 平板布局开关，本项目当前仅移动端；
/// 后续 P8 补充 TV / 平板时在此扩展。
class AppLayoutSettings {
  AppLayoutSettings._();

  /// 播放页路由是否激活：迷你播放器据此隐藏（避免全屏播放器下重复展示）。
  static final ValueNotifier<bool> playerRouteActive =
      ValueNotifier<bool>(false);
}
