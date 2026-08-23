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
            // 恢复会话期间显示闪屏，避免「先登录页后首页」的闪烁。
            if (status == AuthStatus.restoring) {
              return const _StartupSplash();
            }
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

/// 会话恢复闪屏：登录态未确定前短暂展示，避免启动时先闪登录页再进首页。
class _StartupSplash extends StatelessWidget {
  const _StartupSplash();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.music_note, size: 72, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              '飞牛音乐',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 12),
            Text(
              '正在恢复会话…',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
