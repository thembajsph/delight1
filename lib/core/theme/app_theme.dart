import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Delight Brand Colors ─────────────────────────────────────────────────
// Inspired by money, wealth, and African luxury

class DelightColors {
  // Backgrounds
  static const background   = Color(0xFF060F0A);   // Near-black with green undertone
  static const surface      = Color(0xFF0D1A12);
  static const surfaceHigh  = Color(0xFF142019);
  static const surfaceBorder = Color(0xFF1E3028);

  // Brand — Emerald & Gold
  static const emerald      = Color(0xFF00C96A);   // Primary emerald
  static const emeraldDark  = Color(0xFF009E52);
  static const emeraldDeep  = Color(0xFF006636);
  static const emeraldGlow  = Color(0x1A00C96A);

  static const gold         = Color(0xFFD4AF37);   // Money gold
  static const goldLight    = Color(0xFFF5D76E);
  static const goldDark     = Color(0xFFA88A1F);
  static const goldGlow     = Color(0x1AD4AF37);

  // Text
  static const textPrimary  = Color(0xFFEFF7F2);
  static const textSecondary = Color(0xFF7A9E8A);
  static const textMuted    = Color(0xFF3D5E4A);
  static const textInverse  = Color(0xFF060F0A);

  // Semantic
  static const success      = Color(0xFF00C96A);
  static const error        = Color(0xFFFF4757);
  static const warning      = Color(0xFFD4AF37);
  static const info         = Color(0xFF4A9EFF);
  static const blue         = Color(0xFF4A9EFF);

  // Gradients
  static const emeraldGradient = [Color(0xFF00C96A), Color(0xFF006636)];
  static const goldGradient    = [Color(0xFFF5D76E), Color(0xFFA88A1F)];
  static const darkGradient    = [Color(0xFF142019), Color(0xFF0D1A12)];
  static const heroGradient    = [Color(0xFF00C96A), Color(0xFF004D28)];
}

// ─── Typography ───────────────────────────────────────────────────────────

class DelightText {
  // Display — Clash Display (bold geometric, money-magazine feel)
  static TextStyle display1(BuildContext context) => TextStyle(
    fontFamily: 'Clash',
    fontSize: 48,
    fontWeight: FontWeight.w700,
    color: DelightColors.textPrimary,
    height: 1.1,
    letterSpacing: -1.0,
  );

  static TextStyle display2(BuildContext context) => TextStyle(
    fontFamily: 'Clash',
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: DelightColors.textPrimary,
    height: 1.15,
    letterSpacing: -0.5,
  );

  static TextStyle heading1(BuildContext context) => TextStyle(
    fontFamily: 'Clash',
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: DelightColors.textPrimary,
    height: 1.2,
    letterSpacing: -0.3,
  );

  static TextStyle heading2(BuildContext context) => TextStyle(
    fontFamily: 'Clash',
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: DelightColors.textPrimary,
    height: 1.25,
  );

  static TextStyle heading3(BuildContext context) => TextStyle(
    fontFamily: 'Clash',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: DelightColors.textPrimary,
  );

  // Body — Satoshi (clean, readable)
  static TextStyle bodyLarge(BuildContext context) => const TextStyle(
    fontFamily: 'Satoshi',
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: DelightColors.textPrimary,
    height: 1.6,
  );

  static TextStyle bodyMedium(BuildContext context) => const TextStyle(
    fontFamily: 'Satoshi',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: DelightColors.textSecondary,
    height: 1.55,
  );

  static TextStyle bodySmall(BuildContext context) => const TextStyle(
    fontFamily: 'Satoshi',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: DelightColors.textMuted,
    height: 1.5,
  );

  static TextStyle label(BuildContext context) => const TextStyle(
    fontFamily: 'Satoshi',
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: DelightColors.textSecondary,
    letterSpacing: 0.3,
  );

  static TextStyle mono(BuildContext context) => const TextStyle(
    fontFamily: 'Courier',
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: DelightColors.textPrimary,
    letterSpacing: 1.0,
  );
}

// ─── Theme ────────────────────────────────────────────────────────────────

ThemeData buildDelightTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: DelightColors.background,
    colorScheme: const ColorScheme.dark(
      primary: DelightColors.emerald,
      secondary: DelightColors.gold,
      surface: DelightColors.surface,
      onPrimary: DelightColors.textInverse,
      onSecondary: DelightColors.textInverse,
      onSurface: DelightColors.textPrimary,
      error: DelightColors.error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: DelightColors.background,
      foregroundColor: DelightColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      titleTextStyle: TextStyle(
        fontFamily: 'Clash',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: DelightColors.textPrimary,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: DelightColors.surface,
      selectedItemColor: DelightColors.emerald,
      unselectedItemColor: DelightColors.textMuted,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
    ),
    cardTheme: CardTheme(
      color: DelightColors.surfaceHigh,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: DelightColors.surfaceBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DelightColors.surfaceHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: DelightColors.surfaceBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: DelightColors.surfaceBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: DelightColors.emerald, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: DelightColors.error),
      ),
      hintStyle: const TextStyle(
        fontFamily: 'Satoshi',
        color: DelightColors.textMuted,
        fontSize: 14,
      ),
      labelStyle: const TextStyle(
        fontFamily: 'Satoshi',
        color: DelightColors.textSecondary,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: DelightColors.emerald,
        foregroundColor: DelightColors.textInverse,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
        textStyle: const TextStyle(
          fontFamily: 'Satoshi',
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: DelightColors.emerald,
        textStyle: const TextStyle(
          fontFamily: 'Satoshi',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: DelightColors.surfaceBorder,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: DelightColors.surfaceHigh,
      contentTextStyle: const TextStyle(
        fontFamily: 'Satoshi',
        color: DelightColors.textPrimary,
        fontSize: 14,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
