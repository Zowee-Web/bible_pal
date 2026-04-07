import 'package:flutter/material.dart';

/// The four phases of the living sky, determined by time of day.
enum SkyPhase {
  /// 5:00 AM - 7:59 AM
  dawn,

  /// 8:00 AM - 4:59 PM
  day,

  /// 5:00 PM - 7:59 PM
  goldenHour,

  /// 8:00 PM - 4:59 AM
  night,
}

/// Holds the complete color palette for a single [SkyPhase].
class SkyPalette {
  /// Three colors for the vertical gradient background.
  final List<Color> gradientColors;

  /// Three stops corresponding to [gradientColors].
  final List<double> gradientStops;

  /// Color of floating particles.
  final Color particleColor;

  /// Maximum opacity of floating particles.
  final double particleOpacity;

  /// The PAL orb's glow/accent color.
  final Color orbGlowColor;

  /// Three colors for the PAL orb radial gradient.
  final List<Color> orbGradientColors;

  /// Primary text color.
  final Color textColor;

  /// Secondary/subtitle text color.
  final Color subtitleColor;

  /// Accent color for gold accents, verse references.
  final Color accentColor;

  /// Glass card background color.
  final Color cardColor;

  /// Glass card border color.
  final Color cardBorder;

  /// Swipe hint chevron color.
  final Color chevronColor;

  /// Glow intensity multiplier for premium UI elements.
  /// Night = strongest (1.0), Day = most restrained (0.6).
  final double glowIntensity;

  const SkyPalette({
    required this.gradientColors,
    required this.gradientStops,
    required this.particleColor,
    required this.particleOpacity,
    required this.orbGlowColor,
    required this.orbGradientColors,
    required this.textColor,
    required this.subtitleColor,
    required this.accentColor,
    required this.cardColor,
    required this.cardBorder,
    required this.chevronColor,
    this.glowIntensity = 0.8,
  });

  /// Background luminance (0.0 = black, 1.0 = white) computed from the
  /// middle gradient color — the region where lower-screen text sits.
  /// Use this to drive adaptive text opacity and shadow for readability.
  double get backgroundLuminance => gradientColors[1].computeLuminance();

  /// Whether the background midpoint is bright (luminance > 0.35).
  bool get isBrightBackground => backgroundLuminance > 0.35;

  /// Adaptive text shadow for readability on varying backgrounds.
  /// Returns a subtle dark shadow on bright backgrounds, none on dark.
  List<Shadow> get adaptiveTextShadow => isBrightBackground
      ? [
          Shadow(
            color: Color(0xFF000000).withOpacity(0.3),
            blurRadius: 4,
          ),
        ]
      : [];
}

/// Determines the current sky phase and returns the corresponding palette.
///
/// The Living Sky system maps the user's local time of day to a [SkyPhase],
/// each with a distinct color palette that drives the entire app's visual
/// presentation.
class LivingSky {
  LivingSky._();

  /// Determines the [SkyPhase] from the current (or provided) time.
  ///
  /// Hour ranges:
  /// - 5-7: [SkyPhase.dawn]
  /// - 8-16: [SkyPhase.day]
  /// - 17-19: [SkyPhase.goldenHour]
  /// - 20-4: [SkyPhase.night]
  static SkyPhase getPhase([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour >= 5 && hour <= 7) return SkyPhase.dawn;
    if (hour >= 8 && hour <= 16) return SkyPhase.day;
    if (hour >= 17 && hour <= 19) return SkyPhase.goldenHour;
    return SkyPhase.night;
  }

  /// Returns the [SkyPalette] for the given [phase].
  static SkyPalette getPalette(SkyPhase phase) {
    switch (phase) {
      case SkyPhase.dawn:
        return _dawn;
      case SkyPhase.day:
        return _day;
      case SkyPhase.goldenHour:
        return _goldenHour;
      case SkyPhase.night:
        return _night;
    }
  }

  // ---------------------------------------------------------------------------
  // Palettes
  // ---------------------------------------------------------------------------

  /// Purple-pink-gold sunrise.
  static const _dawn = SkyPalette(
    gradientColors: [Color(0xFF2D1B3D), Color(0xFFE8896B), Color(0xFFFFC87A)],
    gradientStops: [0.0, 0.5, 1.0],
    particleColor: Color(0xFFD4AF37),
    particleOpacity: 0.4,
    orbGlowColor: Color(0xFFE8896B),
    orbGradientColors: [
      Color(0xFFE8896B),
      Color(0xFFC06848),
      Color(0xFF8B3A3A),
    ],
    textColor: Color(0xFF2A1A0A),
    subtitleColor: Color(0xFF4A3A2A),
    accentColor: Color(0xFFD4AF37),
    cardColor: Color(0x30FFFFFF),
    cardBorder: Color(0x40FFFFFF),
    chevronColor: Color(0xFF6B5A4A),
    glowIntensity: 0.8,
  );

  /// Sky blue to warm cream.
  static const _day = SkyPalette(
    gradientColors: [Color(0xFF87CEEB), Color(0xFFB8E0F0), Color(0xFFF5F0E8)],
    gradientStops: [0.0, 0.5, 1.0],
    particleColor: Color(0xFFD4AF37),
    particleOpacity: 0.3,
    orbGlowColor: Color(0xFFD4AF37),
    orbGradientColors: [
      Color(0xFFD4AF37),
      Color(0xFFB8941E),
      Color(0xFF8B6914),
    ],
    textColor: Color(0xFF1A1A1A),
    subtitleColor: Color(0xFF3A3A3A),
    accentColor: Color(0xFFB8941E),
    cardColor: Color(0x25000000),
    cardBorder: Color(0x20000000),
    chevronColor: Color(0xFF5A5A5A),
    glowIntensity: 0.6,
  );

  /// Deep purple to amber-orange.
  static const _goldenHour = SkyPalette(
    gradientColors: [Color(0xFF1A1040), Color(0xFFD4652A), Color(0xFFFFAA50)],
    gradientStops: [0.0, 0.5, 1.0],
    particleColor: Color(0xFFFFAA50),
    particleOpacity: 0.35,
    orbGlowColor: Color(0xFFD4652A),
    orbGradientColors: [
      Color(0xFFD4652A),
      Color(0xFFA04820),
      Color(0xFF6B2A10),
    ],
    textColor: Color(0xFFFFF8F0),
    subtitleColor: Color(0xFFDDCCAA),
    accentColor: Color(0xFFFFAA50),
    cardColor: Color(0x30000000),
    cardBorder: Color(0x25FFFFFF),
    chevronColor: Color(0xFFBBA888),
    glowIntensity: 0.8,
  );

  /// Builds a full [ThemeData] from the given [phase]'s palette.
  ///
  /// This allows the entire app to inherit time-of-day colors through
  /// Flutter's theme system — every screen automatically gets the right
  /// text colors, button styles, card colors, etc.
  static ThemeData buildTheme(SkyPhase phase) {
    final p = getPalette(phase);
    final isDark = phase == SkyPhase.night || phase == SkyPhase.goldenHour;
    final brightness = isDark ? Brightness.dark : Brightness.light;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: p.orbGlowColor,
        onPrimary: isDark ? const Color(0xFF001838) : Colors.white,
        primaryContainer: p.cardColor,
        onPrimaryContainer: p.textColor,
        secondary: p.accentColor,
        onSecondary: isDark ? const Color(0xFF1A0F00) : Colors.white,
        secondaryContainer: p.cardColor,
        onSecondaryContainer: p.textColor,
        tertiary: p.subtitleColor,
        tertiaryContainer: p.cardColor,
        onTertiaryContainer: p.textColor,
        surface: p.gradientColors.last,
        onSurface: p.textColor,
        onSurfaceVariant: p.subtitleColor,
        outline: p.cardBorder,
        surfaceContainerHighest: p.cardColor,
        error: const Color(0xFFFF7070),
        onError: const Color(0xFF200000),
      ),
      scaffoldBackgroundColor: p.gradientColors.last,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: p.textColor,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: p.textColor,
          fontSize: 20,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.cardColor,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.cardBorder, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.orbGlowColor,
          foregroundColor: isDark ? Colors.white : const Color(0xFF1A1A1A),
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
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textColor,
          side: BorderSide(color: p.cardBorder),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.orbGlowColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.cardColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.cardBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.cardBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.orbGlowColor, width: 2),
        ),
        labelStyle: TextStyle(color: p.textColor.withOpacity(0.7)),
        hintStyle: TextStyle(color: p.subtitleColor),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.orbGlowColor,
        inactiveTrackColor: p.cardBorder,
        thumbColor: p.orbGlowColor,
        overlayColor: p.orbGlowColor.withOpacity(0.2),
        trackHeight: 3,
      ),
      dividerTheme: DividerThemeData(
        color: p.cardBorder.withOpacity(0.8),
        thickness: 1,
        space: 24,
      ),
      iconTheme: IconThemeData(
        color: p.orbGlowColor,
        size: 24,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? p.orbGlowColor : p.subtitleColor),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? p.orbGlowColor.withOpacity(0.4)
                : p.cardBorder),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? p.orbGlowColor : p.subtitleColor),
      ),
      listTileTheme: ListTileThemeData(
        textColor: p.textColor,
        iconColor: p.orbGlowColor,
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w600, color: p.textColor, letterSpacing: -0.5, height: 1.2),
        displayMedium: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: p.textColor, letterSpacing: -0.3, height: 1.2),
        displaySmall: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: p.textColor, letterSpacing: -0.2, height: 1.3),
        headlineLarge: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.textColor, letterSpacing: -0.5, height: 1.2),
        headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: p.textColor, letterSpacing: 0.3, height: 1.3),
        headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: p.textColor, letterSpacing: 0.3, height: 1.3),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: p.textColor, letterSpacing: 0.2, height: 1.4),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: p.textColor, letterSpacing: 0.2, height: 1.4),
        titleSmall: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.textColor, letterSpacing: 0.2, height: 1.4),
        bodyLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: p.textColor, letterSpacing: 0.2, height: 1.6),
        bodyMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: p.textColor, letterSpacing: 0.2, height: 1.6),
        bodySmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: p.textColor, letterSpacing: 0.2, height: 1.5),
        labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: p.textColor, letterSpacing: 0.3),
        labelMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.textColor, letterSpacing: 0.3),
        labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: p.textColor, letterSpacing: 0.3),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Sacred Night — deep navy.
  static const _night = SkyPalette(
    gradientColors: [Color(0xFF091422), Color(0xFF0D1827), Color(0xFF0F1E30)],
    gradientStops: [0.0, 0.5, 1.0],
    particleColor: Colors.white,
    particleOpacity: 0.0,
    orbGlowColor: Color(0xFF5B9BD5),
    orbGradientColors: [
      Color(0xFF4A86C8),
      Color(0xFF1E4A80),
      Color(0xFF0D1E3A),
    ],
    textColor: Color(0xFFF5F0E5),
    subtitleColor: Color(0xFFAABBCC),
    accentColor: Color(0xFFD4AF37),
    cardColor: Color(0xFF132035),
    cardBorder: Color(0xFF2A4A70),
    chevronColor: Color(0xFFAABBCC),
    glowIntensity: 1.0,
  );
}
