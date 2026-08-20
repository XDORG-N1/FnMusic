export 'player_style_settings.dart';
export 'settings_cache_state.dart';
export 'settings_theme.dart';
export 'settings_onboarding.dart';
export 'settings_notification_state.dart';
export 'settings_fn_state.dart';

import 'player_style_settings.dart';
import 'settings_cache_state.dart';
import 'settings_fn_state.dart';
import 'settings_notification_state.dart';
import 'settings_onboarding.dart';
import 'settings_theme.dart';

/// 设置状态汇总加载器。应用启动时调用一次，确保所有设置域就绪。
///
/// 新增设置域时：在 [loadAll] 中补充对应 `ensureLoaded()` 调用，
/// 并在下方 export 中暴露。
abstract class SettingsState {
  static bool _loaded = false;

  static Future<void> loadAll() async {
    if (_loaded) return;
    await Future.wait(<Future<void>>[
      SettingsTheme.ensureLoaded(),
      SettingsOnboarding.ensureLoaded(),
      PlayerStyleSettings.ensureLoaded(),
      MediaNotificationSettings.ensureLoaded(),
      AppCacheSettings.ensureLoaded(),
      AppFnConnectionSettings.ensureLoaded(),
    ]);
    _loaded = true;
  }
}
