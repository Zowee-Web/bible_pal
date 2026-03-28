import 'package:flutter/material.dart';

/// Bible PAL Custom Theme
/// Based on the UI/UX Design Specification
///
/// Design Philosophy:
/// - Calm, trustworthy, warm, modern but reverent
/// - Faith-first, never "techy"
/// - A gentle spiritual companion
class AppTheme {
  // Core Color Palette
  static const Color softSkyBlue = Color(0xFF87CEEB); // Primary - soft sky blue
  static const Color warmGold =
      Color(0xFFD4AF37); // Secondary accent - warm gold
  static const Color parchment =
      Color(0xFFFAF8F3); // Background - off-white/parchment
  static const Color deepCharcoal = Color(0xFF2C3E50); // Text - deep charcoal
  static const Color lightBlue =
      Color(0xFFB3E0F2); // Lighter shade for containers
  static const Color paleGold =
      Color(0xFFF5E6D3); // Pale gold for subtle highlights

  // Kids Mode Colors — warmer, softer, more playful
  static const Color kidsWarmPeach = Color(0xFFFFA07A); // Primary - warm peach
  static const Color kidsSunshine = Color(0xFFFFD700); // Secondary - sunshine gold
  static const Color kidsCreamBg = Color(0xFFFFF8F0); // Background - warm cream
  static const Color kidsLavender = Color(0xFFE6D5F5); // Container - soft lavender
  static const Color kidsMintGreen = Color(0xFFB8E6C8); // Accent - gentle mint

  /// Main theme for the app
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,

      // Color Scheme
      colorScheme: ColorScheme.light(
        primary: softSkyBlue,
        secondary: warmGold,
        surface: parchment,
        onPrimary: Colors.white,
        onSecondary: deepCharcoal,
        onSurface: deepCharcoal,
        primaryContainer: lightBlue,
        onPrimaryContainer: deepCharcoal,
        secondaryContainer: paleGold,
        onSecondaryContainer: deepCharcoal,
      ),

      // Scaffold Background
      scaffoldBackgroundColor: parchment,

      // App Bar Theme
      appBarTheme: AppBarTheme(
        backgroundColor: parchment,
        foregroundColor: deepCharcoal,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: deepCharcoal,
          fontSize: 20,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shadowColor: deepCharcoal.withOpacity(0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // Elevated Button Theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: softSkyBlue,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: deepCharcoal.withOpacity(0.15),
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // Text Button Theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: softSkyBlue,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: lightBlue, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: lightBlue, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: softSkyBlue, width: 2),
        ),
        labelStyle: TextStyle(color: deepCharcoal.withOpacity(0.7)),
        hintStyle: TextStyle(color: deepCharcoal.withOpacity(0.5)),
      ),

      // Divider Theme
      dividerTheme: DividerThemeData(
        color: lightBlue.withOpacity(0.5),
        thickness: 1,
        space: 24,
      ),

      // Icon Theme
      iconTheme: IconThemeData(
        color: softSkyBlue,
        size: 24,
      ),

      // Typography - Gentle, readable, timeless
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w500,
          color: deepCharcoal,
          letterSpacing: 0.5,
          height: 1.3,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w500,
          color: deepCharcoal,
          letterSpacing: 0.5,
          height: 1.3,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w500,
          color: deepCharcoal,
          letterSpacing: 0.5,
          height: 1.3,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: deepCharcoal,
          letterSpacing: 0.5,
          height: 1.4,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: deepCharcoal,
          letterSpacing: 0.5,
          height: 1.4,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: deepCharcoal,
          letterSpacing: 0.3,
          height: 1.4,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: deepCharcoal,
          letterSpacing: 0.3,
          height: 1.4,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: deepCharcoal,
          letterSpacing: 0.3,
          height: 1.4,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: deepCharcoal,
          letterSpacing: 0.2,
          height: 1.6,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: deepCharcoal,
          letterSpacing: 0.2,
          height: 1.6,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: deepCharcoal.withOpacity(0.8),
          letterSpacing: 0.2,
          height: 1.5,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: deepCharcoal,
          letterSpacing: 0.3,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: deepCharcoal,
          letterSpacing: 0.3,
        ),
        labelSmall: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: deepCharcoal.withOpacity(0.7),
          letterSpacing: 0.3,
        ),
      ),

      // Page Transitions - Gentle, slow, purposeful
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Kids Mode theme — warmer colors, bigger text, softer feel
  static ThemeData get kidsTheme {
    return theme.copyWith(
      colorScheme: ColorScheme.light(
        primary: kidsWarmPeach,
        secondary: kidsSunshine,
        surface: kidsCreamBg,
        onPrimary: Colors.white,
        onSecondary: deepCharcoal,
        onSurface: deepCharcoal,
        primaryContainer: kidsLavender,
        onPrimaryContainer: deepCharcoal,
        secondaryContainer: kidsMintGreen,
        onSecondaryContainer: deepCharcoal,
      ),
      scaffoldBackgroundColor: kidsCreamBg,
      appBarTheme: AppBarTheme(
        backgroundColor: kidsCreamBg,
        foregroundColor: deepCharcoal,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: deepCharcoal,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Duration for gentle animations
  static const Duration gentleTransition = Duration(milliseconds: 400);

  /// Duration for slow animations
  static const Duration slowTransition = Duration(milliseconds: 600);
}
