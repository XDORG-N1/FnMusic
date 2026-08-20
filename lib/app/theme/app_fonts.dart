import 'package:flutter/material.dart';

/// 中文字体回退链。优先使用系统字体，保证 Android 上中文渲染一致。
abstract class AppFonts {
  /// 全局 fallback 字体族（不内置字体包，依赖系统字体）。
  static const List<String> fallbackFamily = <String>[
    'PingFang SC',
    'HarmonyOS Sans SC',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  /// 应用到 [TextTheme] 上的基础样式。
  static const TextStyle baseStyle = TextStyle(
    fontFamilyFallback: fallbackFamily,
  );
}
