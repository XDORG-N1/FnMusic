import 'package:flutter/material.dart';

/// 全局根 [Navigator] 与 [ScaffoldMessenger] key。
/// 供服务层（无 BuildContext 上下文）弹出 Toast / 导航使用。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
