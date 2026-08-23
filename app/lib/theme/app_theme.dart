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

  /// Slightly-elevated dark surface (e.g. a refresh spinner's backdrop).
  static const surfaceElevated = Color(0xFF1E1E1E);

  /// Warm dark surface used for the category filter bottom sheet.
  static const sheetBackground = Color(0xFF171310);

  /// The brand red, taken from the app icon/wordmark lockup.
  static const accent = Color(0xFFE1483A);

  static const textPrimary = Colors.white;
  static const textSecondary = Colors.white70;
  static const textTertiary = Colors.white54;
}

/// Custom text styles that don't map to a standard Material [TextTheme]
/// role — kept as their own [ThemeExtension] so setting them can't silently
/// reskin unrelated widgets that default to a shared role (e.g. buttons
/// defaulting to `labelLarge`).
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  final TextStyle wordmark;
  final TextStyle pillLabel;

  const AppTypography({required this.wordmark, required this.pillLabel});

  factory AppTypography.standard() {
    return AppTypography(
      wordmark: GoogleFonts.anton(fontSize: 18),
      pillLabel: GoogleFonts.anton(fontSize: 13),
    );
  }

  @override
  AppTypography copyWith({TextStyle? wordmark, TextStyle? pillLabel}) {
    return AppTypography(
      wordmark: wordmark ?? this.wordmark,
      pillLabel: pillLabel ?? this.pillLabel,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      wordmark: TextStyle.lerp(wordmark, other.wordmark, t)!,
      pillLabel: TextStyle.lerp(pillLabel, other.pillLabel, t)!,
    );
  }
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
    extensions: [AppTypography.standard()],
  );
}
