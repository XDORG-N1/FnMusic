import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 媒体通知（MediaSession / 通知栏 / 车载歌词）设置。
///
/// 与原设计一致的 prefs key 前缀 `notification_`，控制通知栏是否显示
/// 歌词、歌词是否置顶、收藏/关闭自定义按钮、车载蓝牙歌词开关。
class MediaNotificationSettings {
  static const String _prefsShowLyrics = 'notification_show_lyrics';
  static const String _prefsShowCloseAction = 'notification_show_close_action';
  static const String _prefsLyricOnTop = 'notification_lyric_on_top';
  static const String _prefsShowFavoriteAction =
      'notification_show_favorite_action';
  static const String _prefsCarBluetoothLyrics =
      'notification_car_bluetooth_lyrics';

  static final ValueNotifier<bool> showLyrics = ValueNotifier(true);
  static final ValueNotifier<bool> showCloseAction = ValueNotifier(true);
  static final ValueNotifier<bool> lyricOnTop = ValueNotifier(false);
  static final ValueNotifier<bool> showFavoriteAction = ValueNotifier(true);
  static final ValueNotifier<bool> carBluetoothLyrics = ValueNotifier(false);

  static Future<void>? _loading;

  static Future<void> ensureLoaded() => _loading ??= _doLoad();

  static Future<void> _doLoad() async {
    final prefs = await SharedPreferences.getInstance();
    showLyrics.value = prefs.getBool(_prefsShowLyrics) ?? true;
    showCloseAction.value = prefs.getBool(_prefsShowCloseAction) ?? true;
    lyricOnTop.value = prefs.getBool(_prefsLyricOnTop) ?? false;
    showFavoriteAction.value = prefs.getBool(_prefsShowFavoriteAction) ?? true;
    carBluetoothLyrics.value =
        prefs.getBool(_prefsCarBluetoothLyrics) ?? false;
  }

  static Future<void> setShowLyrics(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsShowLyrics, enabled);
    showLyrics.value = enabled;
  }

  static Future<void> setShowCloseAction(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsShowCloseAction, enabled);
    showCloseAction.value = enabled;
  }

  static Future<void> setLyricOnTop(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsLyricOnTop, enabled);
    lyricOnTop.value = enabled;
  }

  static Future<void> setShowFavoriteAction(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsShowFavoriteAction, enabled);
    showFavoriteAction.value = enabled;
  }

  static Future<void> setCarBluetoothLyrics(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsCarBluetoothLyrics, enabled);
    carBluetoothLyrics.value = enabled;
  }
}
