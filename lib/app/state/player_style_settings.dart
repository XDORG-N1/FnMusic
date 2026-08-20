import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放器样式预设。
enum PlayerStylePreset {
  /// 经典布局：顶部标题 + 居中封面 + 底部控制面板。
  classic,

  /// 海报布局：大封面铺顶 + 底部信息与控制。
  poster,
}

/// 播放器样式设置（静态类，懒加载 + SharedPreferences 持久化）。
class PlayerStyleSettings {
  PlayerStyleSettings._();

  static const String _prefsStylePreset = 'setting_player_style_preset';

  static final ValueNotifier<PlayerStylePreset> stylePreset =
      ValueNotifier<PlayerStylePreset>(PlayerStylePreset.classic);

  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    stylePreset.value = prefs.getString(_prefsStylePreset) == 'poster'
        ? PlayerStylePreset.poster
        : PlayerStylePreset.classic;
    _loaded = true;
  }

  static Future<void> setStylePreset(PlayerStylePreset preset) async {
    stylePreset.value = preset;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsStylePreset,
      preset == PlayerStylePreset.poster ? 'poster' : 'classic',
    );
  }
}
