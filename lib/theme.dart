import 'package:flutter/material.dart';

/// 仿照 ChatGPT 官网的色板，分别给 light / dark 各定义一套。
/// 没用 ColorScheme.fromSeed，是因为 ChatGPT 视觉对中性灰依赖很重，
/// seed 生成会偏色，手写更可控。
class AppColors {
  AppColors._();

  // ---- Brand ----
  static const Color brandGreen = Color(0xFF10A37F); // ChatGPT 标志绿

  // ---- Light ----
  static const Color lightSidebarBg = Color(0xFFF9F9F9);
  static const Color lightSidebarItemHover = Color(0xFFEDEDED);
  static const Color lightSidebarItemActive = Color(0xFFECECEC);
  static const Color lightMainBg = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightUserBubble = Color(0xFFF4F4F4);
  static const Color lightBorder = Color(0xFFE5E5E5);
  static const Color lightBorderStrong = Color(0xFFD0D0D0);
  static const Color lightTextPrimary = Color(0xFF0D0D0D);
  static const Color lightTextSecondary = Color(0xFF5D5D5D);
  static const Color lightTextTertiary = Color(0xFF8E8E8E);
  static const Color lightInputBg = Color(0xFFFFFFFF);
  static const Color lightComposerBg = Color(0xFFFFFFFF);
  static const Color lightSendIdle = Color(0xFFE5E5E5);
  static const Color lightSendActive = Color(0xFF0D0D0D);

  // 代码块 / 引用 / 行内代码
  static const Color lightCodeBg = Color(0xFFF4F4F5);
  static const Color lightCodeHeaderBg = Color(0xFFEAEAEC);
  static const Color lightCodeInlineBg = Color(0xFFEDEDF0);
  static const Color lightQuoteBg = Color(0xFFF6F6F7);
  static const Color lightCodeText = Color(0xFF1A1A1A);

  // ---- Dark ----
  static const Color darkSidebarBg = Color(0xFF171717);
  static const Color darkSidebarItemHover = Color(0xFF2A2A2A);
  static const Color darkSidebarItemActive = Color(0xFF2A2A2A);
  static const Color darkMainBg = Color(0xFF212121);
  static const Color darkSurface = Color(0xFF2F2F2F);
  static const Color darkUserBubble = Color(0xFF2F2F2F);
  static const Color darkBorder = Color(0xFF2D2D2D);
  static const Color darkBorderStrong = Color(0xFF3D3D3D);
  static const Color darkTextPrimary = Color(0xFFECECEC);
  static const Color darkTextSecondary = Color(0xFFB4B4B4);
  static const Color darkTextTertiary = Color(0xFF8E8E8E);
  static const Color darkInputBg = Color(0xFF2F2F2F);
  static const Color darkComposerBg = Color(0xFF2F2F2F);
  static const Color darkSendIdle = Color(0xFF3D3D3D);
  static const Color darkSendActive = Color(0xFFFFFFFF);

  // 代码块 / 引用 / 行内代码
  static const Color darkCodeBg = Color(0xFF2A2A2A);
  static const Color darkCodeHeaderBg = Color(0xFF353535);
  static const Color darkCodeInlineBg = Color(0xFF3A3A3A);
  static const Color darkQuoteBg = Color(0xFF262626);
  static const Color darkCodeText = Color(0xFFE4E4E4);
}

/// 集中提供所有主题色访问，widget 通过 `AppTheme.of(context)` 拿。
class AppPalette {
  final bool isDark;
  const AppPalette({required this.isDark});

  // Brand
  Color get brand => AppColors.brandGreen;

  // Layout
  Color get sidebarBg => isDark ? AppColors.darkSidebarBg : AppColors.lightSidebarBg;
  Color get mainBg => isDark ? AppColors.darkMainBg : AppColors.lightMainBg;
  Color get surface => isDark ? AppColors.darkSurface : AppColors.lightSurface;

  // Items
  Color get itemHover => isDark ? AppColors.darkSidebarItemHover : AppColors.lightSidebarItemHover;
  Color get itemActive => isDark ? AppColors.darkSidebarItemActive : AppColors.lightSidebarItemActive;

  // Lines
  Color get border => isDark ? AppColors.darkBorder : AppColors.lightBorder;
  Color get borderStrong => isDark ? AppColors.darkBorderStrong : AppColors.lightBorderStrong;

  // Bubble
  Color get userBubble => isDark ? AppColors.darkUserBubble : AppColors.lightUserBubble;

  // Composer
  Color get composerBg => isDark ? AppColors.darkComposerBg : AppColors.lightComposerBg;
  Color get inputBg => isDark ? AppColors.darkInputBg : AppColors.lightInputBg;
  Color get sendIdle => isDark ? AppColors.darkSendIdle : AppColors.lightSendIdle;
  Color get sendActive => isDark ? AppColors.darkSendActive : AppColors.lightSendActive;

  // Text
  Color get textPrimary => isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  Color get textSecondary => isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
  Color get textTertiary => isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary;

  // Inverse (用来在主元素上反色，比如 send button)
  Color get inverse => isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  Color get inverseOn => isDark ? AppColors.darkMainBg : AppColors.lightMainBg;

  // 代码块 / 引用 / 行内代码
  Color get codeBg => isDark ? AppColors.darkCodeBg : AppColors.lightCodeBg;
  Color get codeHeaderBg => isDark ? AppColors.darkCodeHeaderBg : AppColors.lightCodeHeaderBg;
  Color get codeInlineBg => isDark ? AppColors.darkCodeInlineBg : AppColors.lightCodeInlineBg;
  Color get quoteBg => isDark ? AppColors.darkQuoteBg : AppColors.lightQuoteBg;
  Color get codeText => isDark ? AppColors.darkCodeText : AppColors.lightCodeText;
}

class AppTheme {
  AppTheme._();

  // 字体跟随系统（ChatGPT 用 web 字体，Flutter 这边用系统即可）

  static ThemeData light() {
    const p = AppPalette(isDark: false);
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: p.mainBg,
      canvasColor: p.mainBg,
      dividerColor: p.border,
      splashFactory: NoSplash.splashFactory,
      highlightColor: p.itemHover,
      colorScheme: const ColorScheme.light(
        primary: AppColors.brandGreen,
        onPrimary: Colors.white,
        surface: AppColors.lightSurface,
        onSurface: AppColors.lightTextPrimary,
        secondary: AppColors.lightTextSecondary,
        onSecondary: Colors.white,
        error: Color(0xFFB42318),
        onError: Colors.white,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w600, letterSpacing: -0.5, height: 1.2),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 15, height: 1.55, color: AppColors.lightTextPrimary),
        bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: AppColors.lightTextPrimary),
        bodySmall: TextStyle(fontSize: 12, color: AppColors.lightTextTertiary),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      iconTheme: const IconThemeData(color: AppColors.lightTextPrimary, size: 20),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightMainBg,
        foregroundColor: AppColors.lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.lightTextPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.lightTextPrimary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  static ThemeData dark() {
    const p = AppPalette(isDark: true);
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: p.mainBg,
      canvasColor: p.mainBg,
      dividerColor: p.border,
      splashFactory: NoSplash.splashFactory,
      highlightColor: p.itemHover,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.brandGreen,
        onPrimary: Colors.white,
        surface: AppColors.darkSurface,
        onSurface: AppColors.darkTextPrimary,
        secondary: AppColors.darkTextSecondary,
        onSecondary: AppColors.darkMainBg,
        error: Color(0xFFB42318),
        onError: Colors.white,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w600, letterSpacing: -0.5, height: 1.2, color: AppColors.darkTextPrimary),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.darkTextPrimary),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.darkTextPrimary),
        bodyLarge: TextStyle(fontSize: 15, height: 1.55, color: AppColors.darkTextPrimary),
        bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: AppColors.darkTextPrimary),
        bodySmall: TextStyle(fontSize: 12, color: AppColors.darkTextTertiary),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.darkTextPrimary),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.darkTextPrimary),
      ),
      iconTheme: const IconThemeData(color: AppColors.darkTextPrimary, size: 20),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkMainBg,
        foregroundColor: AppColors.darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.darkTextPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.lightTextPrimary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
