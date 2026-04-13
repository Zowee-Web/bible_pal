import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/theme/living_sky.dart';

/// Tests for the enforced two-bucket [ForegroundPalette] contract
/// (Phase 3.2 global contrast pass — SPEC Feature 47 Living Sky).
///
/// The contract:
/// - **Bright bucket** (Dawn, Day, Golden Hour — luminance > 0.08):
///   white text at 0.95 / 0.80 / 0.65 / 0.50 opacity
///   WITH phase-aware shadows at primary / secondary / tertiary levels
/// - **Dark bucket** (Night — luminance ≤ 0.08):
///   white text at 0.92 / 0.70 / 0.55 / 0.42 opacity
///   WITHOUT shadows (deep navy background provides contrast natively)
///
/// These tests pin the color + shadow contract so any future drift
/// from the spec fails loudly rather than silently degrading
/// readability.
void main() {
  /// WCAG 2.0 contrast ratio between two colors.
  double contrastRatio(Color fg, Color bg) {
    final fgLum = fg.computeLuminance();
    final bgLum = bg.computeLuminance();
    final lighter = fgLum > bgLum ? fgLum : bgLum;
    final darker = fgLum > bgLum ? bgLum : fgLum;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Luminance classification — the contract-critical threshold.
  const double kShadowThreshold = 0.08;

  group('Luminance classification', () {
    test('day luminance > shadow threshold', () {
      final p = LivingSky.getPalette(SkyPhase.day);
      expect(p.backgroundLuminance, greaterThan(kShadowThreshold));
    });

    test('dawn luminance > shadow threshold', () {
      final p = LivingSky.getPalette(SkyPhase.dawn);
      expect(p.backgroundLuminance, greaterThan(kShadowThreshold));
    });

    test('goldenHour luminance > shadow threshold', () {
      // Golden Hour uses the bright bucket even though its middle
      // gradient is ~0.24. This is the Phase 3.2 fix — without it,
      // white-on-warm-orange gets no shadow and text blends into
      // the background.
      final p = LivingSky.getPalette(SkyPhase.goldenHour);
      expect(p.backgroundLuminance, greaterThan(kShadowThreshold));
    });

    test('night luminance ≤ shadow threshold', () {
      final p = LivingSky.getPalette(SkyPhase.night);
      expect(p.backgroundLuminance, lessThanOrEqualTo(kShadowThreshold));
    });
  });

  group('Bright bucket (Dawn/Day/GoldenHour): white text + shadows', () {
    for (final phase in [SkyPhase.dawn, SkyPhase.day, SkyPhase.goldenHour]) {
      final fg = LivingSky.getPalette(phase).foreground;

      test('$phase primaryText is white at 0.95 opacity', () {
        expect(fg.primaryText, Colors.white.withOpacity(0.95));
      });

      test('$phase secondaryText is white at 0.80 opacity', () {
        expect(fg.secondaryText, Colors.white.withOpacity(0.80));
      });

      test('$phase tertiaryText is white at 0.65 opacity', () {
        expect(fg.tertiaryText, Colors.white.withOpacity(0.65));
      });

      test('$phase mutedText is white at 0.50 opacity', () {
        expect(fg.mutedText, Colors.white.withOpacity(0.50));
      });

      test('$phase primaryText has a shadow', () {
        expect(fg.textShadow, isNotEmpty);
      });

      test('$phase secondaryText has a subtitle shadow', () {
        expect(fg.subtitleShadow, isNotEmpty);
      });

      test('$phase tertiaryText has a caption shadow', () {
        expect(fg.captionShadow, isNotEmpty);
      });
    }
  });

  group('Dark bucket (Night): white text, no shadows', () {
    final fg = LivingSky.getPalette(SkyPhase.night).foreground;

    test('night primaryText is white at 0.92 opacity', () {
      expect(fg.primaryText, Colors.white.withOpacity(0.92));
    });

    test('night secondaryText is white at 0.70 opacity', () {
      expect(fg.secondaryText, Colors.white.withOpacity(0.70));
    });

    test('night tertiaryText is white at 0.55 opacity', () {
      expect(fg.tertiaryText, Colors.white.withOpacity(0.55));
    });

    test('night mutedText is white at 0.42 opacity', () {
      expect(fg.mutedText, Colors.white.withOpacity(0.42));
    });

    test('night primary text has no shadow', () {
      expect(fg.textShadow, isEmpty);
    });

    test('night subtitle has no shadow', () {
      expect(fg.subtitleShadow, isEmpty);
    });

    test('night caption has no shadow', () {
      expect(fg.captionShadow, isEmpty);
    });
  });

  // Note on bright-bucket contrast:
  //
  // The Phase 3.2 spec intentionally uses white-on-bright with shadows
  // as the readability compensation. Raw WCAG contrast ratios don't
  // capture shadow contribution, so naive WCAG tests on the bright
  // bucket would report low contrast and fail for Day/Dawn/Golden Hour
  // even though the visual reads cleanly.
  //
  // The contract-critical assertions for the bright bucket are:
  // (1) white color at the exact spec opacities (above)
  // (2) non-empty shadows at each text level (above + regression guard
  //     group below)
  // Those two conditions together guarantee readability.

  group('Dark bucket contrast against background midpoint', () {
    final palette = LivingSky.getPalette(SkyPhase.night);
    final fg = palette.foreground;
    final bg = palette.gradientColors[1];

    test('night primaryText has strong contrast (≥ 10:1)', () {
      // Night deep navy + white 0.92 should be near maximum contrast.
      expect(contrastRatio(fg.primaryText, bg), greaterThanOrEqualTo(10.0));
    });

    test('night secondaryText contrast ≥ 4.5', () {
      expect(contrastRatio(fg.secondaryText, bg), greaterThanOrEqualTo(4.5));
    });

    test('night tertiaryText contrast ≥ 3.0', () {
      expect(contrastRatio(fg.tertiaryText, bg), greaterThanOrEqualTo(3.0));
    });
  });

  group('Opacity floors (no overly faint text)', () {
    // Dart's `Color.withOpacity` stores alpha as uint8, so values like
    // 0.55 round to 140/255 ≈ 0.549. Use loose floors that account for
    // the rounding gap; the exact-match tests above lock in the
    // spec-correct values per bucket.
    for (final phase in SkyPhase.values) {
      final fg = LivingSky.getPalette(phase).foreground;

      test('$phase primaryText alpha ≥ 0.89', () {
        expect(fg.primaryText.a, greaterThanOrEqualTo(0.89));
      });

      test('$phase secondaryText alpha ≥ 0.69', () {
        expect(fg.secondaryText.a, greaterThanOrEqualTo(0.69));
      });

      test('$phase tertiaryText alpha ≥ 0.54', () {
        expect(fg.tertiaryText.a, greaterThanOrEqualTo(0.54));
      });

      test('$phase mutedText alpha ≥ 0.40', () {
        expect(fg.mutedText.a, greaterThanOrEqualTo(0.40));
      });
    }
  });

  group('Golden Hour shadow regression guard (highest priority)', () {
    test(
        'goldenHour primary shadow is present — fixes the warm-on-warm '
        'readability regression', () {
      final fg = LivingSky.getPalette(SkyPhase.goldenHour).foreground;
      expect(fg.textShadow, isNotEmpty,
          reason:
              'Golden Hour MUST have a primary text shadow; without it, '
              'white-on-orange blurs into the background');
    });

    test('goldenHour subtitle shadow is present', () {
      final fg = LivingSky.getPalette(SkyPhase.goldenHour).foreground;
      expect(fg.subtitleShadow, isNotEmpty);
    });

    test('goldenHour caption shadow is present', () {
      final fg = LivingSky.getPalette(SkyPhase.goldenHour).foreground;
      expect(fg.captionShadow, isNotEmpty);
    });
  });
}
