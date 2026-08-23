import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';

/// 外观设置：主题模式 / 动态取色 / 种子色。
///
/// 采用原设计的模式：静态类持有 `static final ValueNotifier`，
/// `ensureLoaded()` 惰性加载，setter 写入 SharedPreferences 并通知。
class SettingsTheme {
  SettingsTheme._();

  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);
  static final ValueNotifier<bool> dynamicColorEnabled =
      ValueNotifier<bool>(true);
  static final ValueNotifier<Color> seedColor =
      ValueNotifier<Color>(AppSeedColors.feiniuOrange);

  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    themeMode.value = ThemeMode.values[
        prefs.getInt(_prefsThemeMode)?.clamp(0, ThemeMode.values.length - 1) ??
            ThemeMode.system.index];
    dynamicColorEnabled.value = prefs.getBool(_prefsDynamicColor) ?? true;
    seedColor.value = _colorFromValue(prefs.getInt(_prefsSeedColor));
    _loaded = true;
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsThemeMode, mode.index);
  }

  static Future<void> setDynamicColorEnabled(bool enabled) async {
    dynamicColorEnabled.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsDynamicColor, enabled);
  }

  static Future<void> setSeedColor(Color color) async {
    seedColor.value = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsSeedColor, color.toARGB32());
  }

  static const String _prefsThemeMode = 'settings_theme.mode';
  static const String _prefsDynamicColor = 'settings_theme.dynamicColor';
  static const String _prefsSeedColor = 'settings_theme.seed';

  static Color _colorFromValue(int? value) {
    if (value == null) return AppSeedColors.feiniuOrange;
    return Color(value);
  }
}
