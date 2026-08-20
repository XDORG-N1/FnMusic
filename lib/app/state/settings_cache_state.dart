import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/player/stream_cache_service.dart';

/// 缓存设置域。
class AppCacheSettings {
  AppCacheSettings._();

  static const String _prefsCacheLimitMb = 'cache_limit_mb';

  /// 缓存上限（MB）。修改时同步到 [StreamCacheService.maxCacheMb]。
  static final ValueNotifier<int> cacheLimitMb = ValueNotifier<int>(1024);

  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? limit = prefs.getInt(_prefsCacheLimitMb);
    if (limit != null && limit > 0) {
      cacheLimitMb.value = limit;
      StreamCacheService.instance.maxCacheMb = limit;
    }
    _loaded = true;
  }

  static Future<void> setCacheLimitMb(int mb) async {
    if (mb <= 0) return;
    cacheLimitMb.value = mb;
    StreamCacheService.instance.maxCacheMb = mb;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsCacheLimitMb, mb);
  }
}
