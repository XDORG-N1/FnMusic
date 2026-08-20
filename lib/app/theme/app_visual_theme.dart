import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'app_colors.dart';
import 'app_fonts.dart';
import 'app_styles.dart';

/// 构建 Material 3 主题（miuix 风格：大圆角、柔和阴影、克制的表面色）。
///
/// [scheme] 可传入系统动态取色的 ColorScheme（Android 12+），
/// 否则按 [seedColor] 生成。
ThemeData buildMiuixMaterialTheme({
  required Brightness brightness,
  ColorScheme? scheme,
  Color seedColor = AppSeedColors.feiniuOrange,
}) {
  final ColorScheme colorScheme = scheme ??
      ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      );

  final bool isDark = brightness == Brightness.dark;

  const double radius = 18;
  final BorderRadiusGeometry rounded = BorderRadius.circular(radius);

  final TextTheme textTheme = TextTheme(
    titleLarge: const TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
    ).apply(fontFamilyFallback: AppFonts.fallbackFamily),
    titleMedium: const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
    ).apply(fontFamilyFallback: AppFonts.fallbackFamily),
    titleSmall: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
    ).apply(fontFamilyFallback: AppFonts.fallbackFamily),
    bodyLarge: const TextStyle(fontSize: 16)
        .apply(fontFamilyFallback: AppFonts.fallbackFamily),
    bodyMedium: const TextStyle(fontSize: 14)
        .apply(fontFamilyFallback: AppFonts.fallbackFamily),
    bodySmall: const TextStyle(fontSize: 12)
        .apply(fontFamilyFallback: AppFonts.fallbackFamily),
    labelLarge: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ).apply(fontFamilyFallback: AppFonts.fallbackFamily),
    labelMedium: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ).apply(fontFamilyFallback: AppFonts.fallbackFamily),
  );

  final ColorScheme scheme2 = colorScheme;
  final Color surface = isDark
      ? scheme2.surface
      : scheme2.surface;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme2,
    scaffoldBackgroundColor: surface,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      backgroundColor: surface,
      foregroundColor: scheme2.onSurface,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.appPanelColor,
      shape: RoundedRectangleBorder(
        borderRadius: rounded,
        side: BorderSide(color: colorScheme.appPanelBorderColor),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.appPanelColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius + 4)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.appPanelColor,
      indicatorColor: scheme2.primary.withValues(alpha: 0.12),
      elevation: 0,
      height: 68,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.appPanelColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme2.onSurface.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme2.primary, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.appPanelBorderColor,
      thickness: 0.5,
      space: 0.5,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: CoverPageTransitionsBuilder(),
      },
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: WidgetStatePropertyAll(true),
    ),
  );
}

/// 便捷包装：根据 [Brightness] 与 [dynamicColor] 生成主题。
/// 在 app.dart 中配合 [DynamicColorBuilder] 使用。
ThemeData buildThemeForBrightness(
  Brightness brightness, {
  required ColorScheme? dynamicScheme,
  required Color seedColor,
}) {
  return buildMiuixMaterialTheme(
    brightness: brightness,
    scheme: dynamicScheme,
    seedColor: seedColor,
  );
}
