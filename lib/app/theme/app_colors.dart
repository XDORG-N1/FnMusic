import 'package:flutter/material.dart';

/// 品牌色板。默认 seed 色为飞牛橙（呼应 FNOS 品牌）。
abstract class AppSeedColors {
  static const Color feiniuOrange = Color(0xFFFF7A00);
  static const Color feiniuDeepOrange = Color(0xFFE06600);
}

/// 面板 / 玻璃拟态通用颜色，由主题扩展（appPanelColor）消费。
abstract class AppPanelColors {
  static const Color light = Color(0xFFFFFFFF);
  static const Color dark = Color(0xFF1E1E1E);
  static const Color lightBorder = Color(0x14000000);
  static const Color darkBorder = Color(0x1AFFFFFF);
}
