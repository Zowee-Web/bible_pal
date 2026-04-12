import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/theme/living_sky.dart';

/// Tests that [ForegroundPalette] produces readable foreground colors for
/// every [SkyPhase] brightness bucket.
void main() {
  /// WCAG 2.0 minimum contrast ratio for normal text (AA).
  const double kMinContrast = 3.0;

  /// Computes the WCAG contrast ratio between two colors.
  double contrastRatio(Color fg, Color bg) {
    final fgLum = fg.computeLuminance();
    final bgLum = bg.computeLuminance();
    final lighter = fgLum > bgLum ? fgLum : bgLum;
    final darker = fgLum > bgLum ? bgLum : fgLum;
    return (lighter + 0.05) / (darker + 0.05);
  }

  group('Brightness bucket classification', () {
    test('day is bright', () {
      final p = LivingSky.getPalette(SkyPhase.day);
      expect(p.isBrightBackground, isTrue);
    });

    test('dawn is bright', () {
      final p = LivingSky.getPalette(SkyPhase.dawn);
      expect(p.isBrightBackground, isTrue);
    });

    test('goldenHour is medium', () {
      final p = LivingSky.getPalette(SkyPhase.goldenHour);
      expect(p.isBrightBackground, isFalse);
      expect(p.backgroundLuminance, greaterThan(0.08));
    });

    test('night is dark', () {
      final p = LivingSky.getPalette(SkyPhase.night);
      expect(p.backgroundLuminance, lessThan(0.08));
    });
  });

  group('Foreground palette contrast', () {
    for (final phase in SkyPhase.values) {
      final palette = LivingSky.getPalette(phase);
      final fg = palette.foreground;
      // Use the gradient midpoint as the representative background.
      final bg = palette.gradientColors[1];

      test('$phase primaryText has sufficient contrast', () {
        expect(contrastRatio(fg.primaryText, bg),
            greaterThanOrEqualTo(kMinContrast),
            reason: '$phase primaryText');
      });

      test('$phase secondaryText has sufficient contrast', () {
        expect(contrastRatio(fg.secondaryText, bg),
            greaterThanOrEqualTo(kMinContrast),
            reason: '$phase secondaryText');
      });

      test('$phase tertiaryText has measurable contrast', () {
        // Tertiary text is intentionally softer, but still ≥ 2.5:1
        expect(contrastRatio(fg.tertiaryText, bg),
            greaterThanOrEqualTo(2.5),
            reason: '$phase tertiaryText');
      });
    }
  });

  group('Bright backgrounds produce dark text', () {
    for (final phase in [SkyPhase.day, SkyPhase.dawn]) {
      final fg = LivingSky.getPalette(phase).foreground;

      test('$phase primaryText is dark', () {
        expect(fg.primaryText.computeLuminance(), lessThan(0.2));
      });

      test('$phase secondaryText is dark', () {
        expect(fg.secondaryText.computeLuminance(), lessThan(0.25));
      });
    }
  });

  group('Dark backgrounds produce light text', () {
    final fg = LivingSky.getPalette(SkyPhase.night).foreground;

    test('night primaryText is light', () {
      expect(fg.primaryText.computeLuminance(), greaterThan(0.7));
    });

    test('night secondaryText is light', () {
      expect(fg.secondaryText.computeLuminance(), greaterThan(0.5));
    });
  });

  group('Medium backgrounds get text shadows', () {
    test('goldenHour foreground has non-empty textShadow', () {
      final fg = LivingSky.getPalette(SkyPhase.goldenHour).foreground;
      expect(fg.textShadow, isNotEmpty);
      expect(fg.subtitleShadow, isNotEmpty);
    });

    test('goldenHour adaptiveTextShadow is non-empty', () {
      final p = LivingSky.getPalette(SkyPhase.goldenHour);
      expect(p.adaptiveTextShadow, isNotEmpty);
    });
  });

  group('Dark backgrounds have no text shadows', () {
    test('night foreground has empty textShadow', () {
      final fg = LivingSky.getPalette(SkyPhase.night).foreground;
      expect(fg.textShadow, isEmpty);
      expect(fg.subtitleShadow, isEmpty);
    });
  });

  group('No overly faint opacity values', () {
    for (final phase in SkyPhase.values) {
      final fg = LivingSky.getPalette(phase).foreground;

      test('$phase secondaryText alpha ≥ 0.75', () {
        expect(fg.secondaryText.a, greaterThanOrEqualTo(0.75));
      });

      test('$phase tertiaryText alpha ≥ 0.55', () {
        expect(fg.tertiaryText.a, greaterThanOrEqualTo(0.55));
      });

      test('$phase mutedText alpha ≥ 0.40', () {
        expect(fg.mutedText.a, greaterThanOrEqualTo(0.40));
      });
    }
  });
}
