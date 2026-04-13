import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Foreground contrast palette — semantic text/icon colors locked by sky
// phase. Every phase-aware surface in Bible PAL routes through this so the
// app has exactly one source of truth for text color.
// ---------------------------------------------------------------------------

/// Semantic foreground colors locked to the current [SkyPhase] — the
/// single source of truth for text and icon contrast across every
/// screen in Bible PAL.
///
/// **Locked phase-based text system (SPEC Feature 47).** Every text
/// rendering in the app MUST route through a `ForegroundPalette`
/// instance obtained via `palette.foreground`. No widget is allowed to
/// hardcode phase-aware text colors or use raw `.withOpacity()` chains
/// to "guess" contrast per component.
///
/// Two-bucket contract:
/// - **Bright phases** (Dawn, Day, Golden Hour) — dark text:
///   `#1A1A1A` / `#4A4A4A` / `#6B6B6B`
/// - **Night phase** — light text:
///   `#FFFFFF` / white@0.85 / white@0.65
///
/// Three text levels + three shadow levels:
/// - [primaryText] / [textShadow] — titles, headings, important labels
/// - [secondaryText] / [subtitleShadow] — subtitles, helper text, labels
/// - [tertiaryText] / [captionShadow] — hints, scripture refs, captions
/// - [mutedText] — decorative captions (muted state)
///
/// Shadows are non-empty only for Night (the deep navy already has
/// native contrast, but hero text over the starfield still benefits
/// from a faint lift). For bright phases, text is dark on warm/light
/// backgrounds — no shadow is required. See `SkyPalette.foreground`
/// for the exact mapping.
class ForegroundPalette {
  /// Full-strength primary text — titles, headings, important content.
  final Color primaryText;

  /// Strong secondary text — subtitles, labels, descriptions.
  /// Always clearly readable against the background.
  final Color secondaryText;

  /// Softer tertiary text — hints, placeholders, captions, scripture
  /// references. Visible but not prominent.
  final Color tertiaryText;

  /// Very subtle text — UI hints like "swipe", decorative captions.
  final Color mutedText;

  /// Primary icon color — interactive elements.
  final Color primaryIcon;

  /// Secondary icon color — decorative / informational icons.
  final Color secondaryIcon;

  /// Divider / separator color.
  final Color divider;

  /// Adaptive text shadow for primary / title text.
  final List<Shadow> textShadow;

  /// Slightly stronger shadow for secondary / smaller text.
  final List<Shadow> subtitleShadow;

  /// Subtle shadow for tertiary / caption text. Tuned narrower than
  /// [subtitleShadow] so small text reads cleanly without blur halo.
  final List<Shadow> captionShadow;

  /// Subtle local contrast layer for content regions. Transparent by
  /// default; reserved for rare cases that need a rounded darkening
  /// pane over the sky gradient.
  final Color scrimColor;

  /// Very light translucent fill for "subtle glass" surfaces — the
  /// ambient container background, unselected chip backgrounds,
  /// inactive pill tiles. Phase-adaptive: translucent dark on bright
  /// phases, translucent white on Night. Always reads as "quietly
  /// present" rather than washed-out or invisible.
  final Color subtleSurface;

  /// Matching border for [subtleSurface]. Slightly stronger than the
  /// fill so the edge is visible without feeling heavy.
  final Color subtleBorder;

  const ForegroundPalette({
    required this.primaryText,
    required this.secondaryText,
    required this.tertiaryText,
    required this.mutedText,
    required this.primaryIcon,
    required this.secondaryIcon,
    required this.divider,
    required this.textShadow,
    required this.subtitleShadow,
    this.captionShadow = const [],
    this.scrimColor = const Color(0x00000000),
    this.subtleSurface = const Color(0x00000000),
    this.subtleBorder = const Color(0x00000000),
  });
}

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

  /// Warm highlight color for selected-state borders, fills, and glows.
  /// Always a warm amber / gold tone regardless of phase — avoids cool-blue
  /// selection language that clashes with the warm Living Sky identity.
  final Color warmHighlight;

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
    required this.warmHighlight,
    this.glowIntensity = 0.8,
  });

  /// Background luminance (0.0 = black, 1.0 = white) computed from the
  /// middle gradient color — the region where lower-screen text sits.
  /// Use this to drive adaptive text opacity and shadow for readability.
  double get backgroundLuminance => gradientColors[1].computeLuminance();

  /// Whether the background midpoint is bright (luminance > 0.35).
  bool get isBrightBackground => backgroundLuminance > 0.35;

  /// Adaptive text shadow for readability on varying backgrounds.
  /// Returns a subtle dark shadow on bright backgrounds, a polarity-aware
  /// shadow on medium backgrounds, and none on dark backgrounds.
  List<Shadow> get adaptiveTextShadow {
    final lum = backgroundLuminance;
    if (lum > 0.35) {
      // Bright — subtle dark shadow behind dark text.
      return const [Shadow(color: Color(0x4D000000), blurRadius: 4)];
    }
    if (lum > 0.08) {
      // Medium — shadow opposite to text polarity for contrast.
      final darkShadow = textColor.computeLuminance() > 0.5;
      return [
        Shadow(
          color: darkShadow
              ? const Color(0x66000000)
              : const Color(0x55FFFFFF),
          blurRadius: 5,
        ),
      ];
    }
    return const [];
  }

  /// Locked semantic foreground palette (SPEC Feature 47).
  ///
  /// Two-bucket contract, determined purely by whether [textColor] is a
  /// dark tone or a light tone — which in turn is locked per phase in
  /// the `SkyPalette` constants below:
  ///
  /// - **Bright phases** — Dawn, Day, Golden Hour
  ///   Dark text: `#1A1A1A` / `#4A4A4A` / `#6B6B6B`. No shadow.
  ///
  /// - **Night phase** — white text: `#FFFFFF` / white@0.85 / white@0.65.
  ///   Hero text gets a faint drop shadow for lift over the starfield.
  ///
  /// There is no luminance-based heuristic and no per-component
  /// override. If you need a different color, change the phase's
  /// palette — the lock is the whole point.
  ForegroundPalette get foreground {
    // Night is the only dark-text case; every other phase uses the
    // locked bright-phase dark tones. We key on the palette's primary
    // textColor tone rather than a luminance threshold so the bucket
    // never drifts out of sync with the spec.
    final isNight = textColor.computeLuminance() > 0.5;

    if (isNight) {
      // Night — white text on deep navy. Hero primary gets a faint
      // shadow so landing verse / sanctuary titles lift off the
      // starfield; regular body text has no shadow.
      return ForegroundPalette(
        primaryText: const Color(0xFFFFFFFF),
        secondaryText: const Color(0xD9FFFFFF), // white @ 0.85
        tertiaryText: const Color(0xA6FFFFFF), // white @ 0.65
        mutedText: const Color(0x80FFFFFF), // white @ 0.50
        primaryIcon: orbGlowColor,
        secondaryIcon: const Color(0xD9FFFFFF),
        divider: cardBorder.withValues(alpha: 0.50),
        textShadow: const [
          Shadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
        subtitleShadow: const [],
        captionShadow: const [],
        subtleSurface: const Color(0x14FFFFFF), // white @ ~8%
        subtleBorder: const Color(0x33FFFFFF), // white @ 20%
      );
    }

    // Bright phases — Dawn, Day, Golden Hour. Locked dark tones.
    return ForegroundPalette(
      primaryText: const Color(0xFF1A1A1A),
      secondaryText: const Color(0xFF4A4A4A),
      tertiaryText: const Color(0xFF6B6B6B),
      mutedText: const Color(0xFF8A8A8A),
      primaryIcon: const Color(0xFF1A1A1A),
      secondaryIcon: const Color(0xFF4A4A4A),
      divider: const Color(0x1A1A1A1A), // #1A1A1A @ 10%
      textShadow: const [],
      subtitleShadow: const [],
      captionShadow: const [],
      scrimColor: const Color(0x00000000),
      subtleSurface: const Color(0x141A1A1A), // #1A1A1A @ ~8%
      subtleBorder: const Color(0x331A1A1A), // #1A1A1A @ 20%
    );
  }
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

  /// Purple-pink-gold sunrise. Locked bright-phase dark text.
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
    textColor: Color(0xFF1A1A1A),
    subtitleColor: Color(0xFF4A4A4A),
    accentColor: Color(0xFFD4AF37),
    cardColor: Color(0x30FFFFFF),
    cardBorder: Color(0x40FFFFFF),
    chevronColor: Color(0xFF6B5A4A),
    warmHighlight: Color(0xFFD4AF37),
    glowIntensity: 0.8,
  );

  /// Sky blue to warm cream. Locked bright-phase dark text.
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
    subtitleColor: Color(0xFF4A4A4A),
    accentColor: Color(0xFFB8941E),
    cardColor: Color(0x25000000),
    cardBorder: Color(0x20000000),
    chevronColor: Color(0xFF5A5A5A),
    warmHighlight: Color(0xFFD4AF37),
    glowIntensity: 0.6,
  );

  /// Deep purple to amber-orange. Locked bright-phase dark text (Golden
  /// Hour intentionally joins the bright bucket per SPEC Feature 47).
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
    textColor: Color(0xFF1A1A1A),
    subtitleColor: Color(0xFF4A4A4A),
    accentColor: Color(0xFFFFAA50),
    cardColor: Color(0x30000000),
    cardBorder: Color(0x25FFFFFF),
    chevronColor: Color(0xFF6B5A4A),
    warmHighlight: Color(0xFFFFAA50),
    glowIntensity: 0.8,
  );

  /// Builds a full [ThemeData] from the given [phase]'s palette.
  ///
  /// This allows the entire app to inherit time-of-day colors through
  /// Flutter's theme system — every screen automatically gets the right
  /// text colors, button styles, card colors, etc.
  static ThemeData buildTheme(SkyPhase phase) {
    final p = getPalette(phase);
    // Locked phase-based brightness: Night is the only dark-text phase.
    // Golden Hour joins Dawn/Day in the bright-phase dark-text bucket
    // per SPEC Feature 47.
    final isDark = phase == SkyPhase.night;
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
          backgroundColor: p.warmHighlight,
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
          foregroundColor: p.warmHighlight,
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
          borderSide: BorderSide(color: p.warmHighlight, width: 2),
        ),
        labelStyle: TextStyle(color: p.textColor.withOpacity(0.7)),
        hintStyle: TextStyle(color: p.subtitleColor),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.warmHighlight,
        inactiveTrackColor: p.cardBorder,
        thumbColor: p.warmHighlight,
        overlayColor: p.warmHighlight.withOpacity(0.2),
        trackHeight: 3,
      ),
      dividerTheme: DividerThemeData(
        color: p.cardBorder.withOpacity(0.8),
        thickness: 1,
        space: 24,
      ),
      iconTheme: IconThemeData(
        color: p.warmHighlight,
        size: 24,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? p.warmHighlight : p.subtitleColor),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? p.warmHighlight.withOpacity(0.4)
                : p.cardBorder),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? p.warmHighlight : p.subtitleColor),
      ),
      listTileTheme: ListTileThemeData(
        textColor: p.textColor,
        iconColor: p.warmHighlight,
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

  /// Sacred Night — deep navy. Locked night-phase white text.
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
    textColor: Color(0xFFFFFFFF),
    subtitleColor: Color(0xD9FFFFFF), // white @ 0.85
    accentColor: Color(0xFFD4AF37),
    cardColor: Color(0xFF1A1812),
    cardBorder: Color(0xFF3A3228),
    chevronColor: Color(0xFFAABBCC),
    warmHighlight: Color(0xFFD4AF37),
    glowIntensity: 1.0,
  );
}
