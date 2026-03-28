import 'package:flutter/material.dart';

/// Bible PAL — Sacred Night Theme
///
/// Design philosophy: Candlelight scripture reading under a night sky.
/// Dark, warm, luminous — reverent but not heavy.
class AppTheme {
  // ── Sacred Night Palette ────────────────────────────────────────────────────

  /// Deep midnight backdrop
  static const Color midnightNavy = Color(0xFF0D1827);

  /// Celestial accent blue — primary
  static const Color celestialBlue = Color(0xFF5B9BD5);

  /// Warm gold — secondary accent (unchanged value, always beautiful)
  static const Color warmGold = Color(0xFFD4AF37);

  /// Bright gold — for text highlights and ornamental details
  static const Color brightGold = Color(0xFFF0C040);

  /// Warm ivory — primary text colour
  static const Color warmIvory = Color(0xFFEEE8D5);

  /// Muted slate — secondary / placeholder text
  static const Color mutedSlate = Color(0xFF7A8BA0);

  /// Glass card surface — for cards and input fills
  static const Color glassCard = Color(0xFF132035);

  /// Glass border — for card outlines and dividers
  static const Color glassBorder = Color(0xFF2A4A70);

  // ── Backward-compatibility aliases ─────────────────────────────────────────
  // Existing screens reference these by name. Renaming the values here
  // automatically propagates the dark theme without touching screen files.

  /// Was parchment off-white, now midnight navy.
  static const Color parchment = midnightNavy;

  /// Was flat sky blue, now celestial blue.
  static const Color softSkyBlue = celestialBlue;

  /// Was deep charcoal text, now warm ivory (text is light on dark bg).
  static const Color deepCharcoal = warmIvory;

  /// Was light-blue container, now glass-card dark container.
  static const Color lightBlue = glassBorder;

  /// Was pale gold highlight, now dark glass border.
  static const Color paleGold = glassCard;

  // ── Theme ───────────────────────────────────────────────────────────────────

  // Kids Mode Colors — warmer, softer, more playful
  static const Color kidsWarmPeach = Color(0xFFFFA07A); // Primary - warm peach
  static const Color kidsSunshine = Color(0xFFFFD700); // Secondary - sunshine gold
  static const Color kidsCreamBg = Color(0xFFFFF8F0); // Background - warm cream
  static const Color kidsLavender = Color(0xFFE6D5F5); // Container - soft lavender
  static const Color kidsMintGreen = Color(0xFFB8E6C8); // Accent - gentle mint

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,

      colorScheme: ColorScheme.dark(
        brightness: Brightness.dark,
        primary: celestialBlue,
        onPrimary: const Color(0xFF001838),
        primaryContainer: const Color(0xFF1A3558),
        onPrimaryContainer: const Color(0xFFC8DFFF),
        secondary: warmGold,
        onSecondary: const Color(0xFF1A0F00),
        secondaryContainer: const Color(0xFF2C2210),
        onSecondaryContainer: brightGold,
        tertiary: const Color(0xFF9B8FD8),
        tertiaryContainer: const Color(0xFF1D1840),
        onTertiaryContainer: const Color(0xFFD4CCFF),
        surface: midnightNavy,
        onSurface: warmIvory,
        onSurfaceVariant: mutedSlate,
        outline: glassBorder,
        surfaceContainerHighest: glassCard,
        error: const Color(0xFFFF7070),
        onError: const Color(0xFF200000),
      ),

      scaffoldBackgroundColor: midnightNavy,

      // App Bar — transparent, light text
      appBarTheme: AppBarTheme(
        backgroundColor: midnightNavy,
        foregroundColor: warmIvory,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: warmIvory,
          fontSize: 20,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),

      // Cards — dark glass surface with subtle border
      cardTheme: CardThemeData(
        color: glassCard,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: glassBorder, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // Elevated button — celestial blue
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: celestialBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // Outlined button — glass style
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: warmIvory,
          side: const BorderSide(color: glassBorder),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // Text button — celestial blue
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: celestialBlue,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      // Inputs — dark glass fill
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glassCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: glassBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: glassBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: celestialBlue, width: 2),
        ),
        labelStyle: TextStyle(color: warmIvory.withOpacity(0.7)),
        hintStyle: const TextStyle(color: mutedSlate),
      ),

      // Slider — glowing celestial blue track
      sliderTheme: SliderThemeData(
        activeTrackColor: celestialBlue,
        inactiveTrackColor: glassBorder,
        thumbColor: celestialBlue,
        overlayColor: celestialBlue.withOpacity(0.2),
        trackHeight: 3,
      ),

      // Dividers
      dividerTheme: DividerThemeData(
        color: glassBorder.withOpacity(0.8),
        thickness: 1,
        space: 24,
      ),

      // Icons
      iconTheme: const IconThemeData(
        color: celestialBlue,
        size: 24,
      ),

      // Switches
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? celestialBlue : mutedSlate),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? celestialBlue.withOpacity(0.4)
                : glassBorder),
      ),

      // Radio buttons
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? celestialBlue : mutedSlate),
      ),

      // Typography — warm ivory, readable on dark
      textTheme: TextTheme(
        displayLarge: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            color: warmIvory,
            letterSpacing: -0.5,
            height: 1.2),
        displayMedium: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: warmIvory,
            letterSpacing: -0.3,
            height: 1.2),
        displaySmall: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: warmIvory,
            letterSpacing: -0.2,
            height: 1.3),
        headlineLarge: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: warmIvory,
            letterSpacing: -0.5,
            height: 1.2),
        headlineMedium: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: warmIvory,
            letterSpacing: 0.3,
            height: 1.3),
        headlineSmall: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: warmIvory,
            letterSpacing: 0.3,
            height: 1.3),
        titleLarge: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: warmIvory,
            letterSpacing: 0.2,
            height: 1.4),
        titleMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: warmIvory,
            letterSpacing: 0.2,
            height: 1.4),
        titleSmall: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: warmIvory,
            letterSpacing: 0.2,
            height: 1.4),
        bodyLarge: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: warmIvory,
            letterSpacing: 0.2,
            height: 1.6),
        bodyMedium: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: warmIvory,
            letterSpacing: 0.2,
            height: 1.6),
        bodySmall: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: warmIvory,
            letterSpacing: 0.2,
            height: 1.5),
        labelLarge: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: warmIvory,
            letterSpacing: 0.3),
        labelMedium: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: warmIvory,
            letterSpacing: 0.3),
        labelSmall: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: mutedSlate,
            letterSpacing: 0.3),
      ),

      // Page transitions — gentle, purposeful
      pageTransitionsTheme: const PageTransitionsTheme(
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
