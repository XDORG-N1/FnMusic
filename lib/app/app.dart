import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'navigator_key.dart';
import 'router/app_router.dart';
import 'router/app_page_route.dart';
import 'services/feiniu/auth_service.dart';
import 'state/settings_state.dart';
import 'theme/app_visual_theme.dart';
import '../pages/login/login_page.dart';
import '../pages/onboarding/onboarding_page.dart';

/// 应用根组件。
class FnMusicApp extends StatelessWidget {
  const FnMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: SettingsTheme.themeMode,
          builder: (context, mode, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: SettingsTheme.dynamicColorEnabled,
              builder: (context, dynamicColorEnabled, _) {
                final Color seedColor = SettingsTheme.seedColor.value;
                // 动态取色开启时使用系统方案；关闭时退回固定种子色。
                final ColorScheme? lightScheme =
                    dynamicColorEnabled ? lightDynamic : null;
                final ColorScheme? darkScheme =
                    dynamicColorEnabled ? darkDynamic : null;
                return MaterialApp(
                  title: '飞牛音乐',
                  debugShowCheckedModeBanner: false,
                  navigatorKey: appNavigatorKey,
                  scaffoldMessengerKey: appMessengerKey,
                  theme: buildThemeForBrightness(
                    Brightness.light,
                    dynamicScheme: lightScheme,
                    seedColor: seedColor,
                  ),
                  darkTheme: buildThemeForBrightness(
                    Brightness.dark,
                    dynamicScheme: darkScheme,
                    seedColor: seedColor,
                  ),
                  themeMode: mode,
                  locale: const Locale('zh', 'CN'),
                  supportedLocales: const <Locale>[
                    Locale('zh', 'CN'),
                  ],
                  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  onGenerateRoute: _buildRoute,
                  home: const AppStartupGate(),
                );
              },
            );
          },
        );
      },
    );
  }

  Route<dynamic>? _buildRoute(RouteSettings settings) {
    final WidgetBuilder? builder = AppRouter.routes[settings.name];
    if (builder == null) return null;
    return AppPageRoute<dynamic>(
      settings: settings,
      builder: builder,
    );
  }
}

/// 启动门：onboarding（首次引导）→ 登录 → 主界面。
class AppStartupGate extends StatefulWidget {
  const AppStartupGate({super.key});

  @override
  State<AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends State<AppStartupGate> {
  @override
  void initState() {
    super.initState();
    // 恢复已保存账号会话。
    AuthService.instance.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsOnboarding.completed,
      builder: (context, completed, _) {
        if (!completed) {
          return const OnboardingPage();
        }
        return ValueListenableBuilder<AuthStatus>(
          valueListenable: AuthService.instance.status,
          builder: (context, status, _) {
            if (status != AuthStatus.loggedIn) {
              return const LoginPage();
            }
            return const PrimaryNavigationShell();
          },
        );
      },
    );
  }
}
