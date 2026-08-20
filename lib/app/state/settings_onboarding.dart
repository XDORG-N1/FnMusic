import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首次启动引导状态。
class SettingsOnboarding {
  SettingsOnboarding._();

  static final ValueNotifier<bool> completed = ValueNotifier<bool>(false);

  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    completed.value = prefs.getBool(_prefsCompleted) ?? false;
    _loaded = true;
  }

  static Future<void> setCompleted(bool value) async {
    completed.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsCompleted, value);
  }

  static const String _prefsCompleted = 'settings_onboarding.completed';
}
