import 'package:shared_preferences/shared_preferences.dart';

/// 与账号会话绑定的本地缓存（登出 / 会话失效时需要清除）。
///
/// 不清除会导致账号间数据串台：登出后换账号登录，首页等页面会先渲染
/// 上一个账号的缓存数据。设备级设置（主题、排序偏好等）不属于会话缓存，
/// 不在此清理。
class SessionCache {
  SessionCache._();

  /// 首页仪表盘缓存键（home_page.dart 读写）。
  static const String homeDashboardKey = 'home_dashboard_cache_v1';

  /// 清空当前会话相关的本地缓存。
  static Future<void> clearAll() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(homeDashboardKey);
  }
}
