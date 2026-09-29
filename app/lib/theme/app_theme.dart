import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app's shared color palette. Every screen/widget should read colors
/// from here (or from `Theme.of(context)`) instead of repeating literal
/// `Color(0x...)`/`Colors.white70`-style values.
class AppColors {
  const AppColors._();

  /// Primary near-black surface: scaffold background, app bars, top/bottom
  /// bars.
  static const background = Color(0xFF121212);

  /// Warm dark surface used for the category filter bottom sheet.
  static const sheetBackground = Color(0xFF171310);

  /// The brand red, taken from the app icon/wordmark lockup.
  static const accent = Color(0xFFE1483A);

  static const textPrimary = Colors.white;
  static const textSecondary = Colors.white70;
  static const textTertiary = Colors.white54;

  // Anton display font, for the wordmark and category pills only — never for
  // fetched article headlines/snippets (Anton has no Bengali glyphs).
  static final TextStyle wordmarkStyle = GoogleFonts.anton(fontSize: 18);
  static final TextStyle pillLabelStyle = GoogleFonts.anton(fontSize: 13);
}

/// Status bar / Android nav bar icon styling for the app's single (dark)
/// theme, applied once at startup since most screens have no [AppBar] for
/// Flutter to auto-derive it from.
const kSystemOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: AppColors.background,
  systemNavigationBarIconBrightness: Brightness.light,
);

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
  ).copyWith(primary: AppColors.accent, surface: AppColors.background);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      systemOverlayStyle: kSystemOverlayStyle,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.sheetBackground,
    ),
  );
}
