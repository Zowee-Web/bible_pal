import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/theme/living_sky.dart';

/// Locked phase-based text-color contract for [ForegroundPalette]
/// (SPEC Feature 47 Living Sky — LOCKED).
///
/// The contract:
/// - **Bright phases** (Dawn, Day, Golden Hour) — dark text only:
///     primary   #1A1A1A
///     secondary #4A4A4A
///     tertiary  #6B6B6B
///   No luminance heuristic, no per-component override, no shadows on
///   body text. Golden Hour is explicitly part of the bright bucket.
/// - **Night phase** — light text only:
///     primary   #FFFFFF
///     secondary rgba(255,255,255,0.85)
///     tertiary  rgba(255,255,255,0.65)
///   Hero primary gets a faint drop shadow to lift off the starfield;
///   body and caption do not.
///
/// This test is the guardian of the locked system. Any change that
/// loosens, bypasses, or re-introduces luminance-based heuristics for
/// text MUST update this contract deliberately — silent drift is a
/// regression.
void main() {
  const Color kBrightPrimary = Color(0xFF1A1A1A);
  const Color kBrightSecondary = Color(0xFF4A4A4A);
  const Color kBrightTertiary = Color(0xFF6B6B6B);

  const Color kNightPrimary = Color(0xFFFFFFFF);
  const Color kNightSecondary = Color(0xD9FFFFFF); // white @ 0.85
  const Color kNightTertiary = Color(0xA6FFFFFF); // white @ 0.65

  /// WCAG 2.0 contrast ratio between two colors.
  double contrastRatio(Color fg, Color bg) {
    final fgLum = fg.computeLuminance();
    final bgLum = bg.computeLuminance();
    final lighter = fgLum > bgLum ? fgLum : bgLum;
    final darker = fgLum > bgLum ? bgLum : fgLum;
    return (lighter + 0.05) / (darker + 0.05);
  }

  group('Bright phases (Dawn/Day/GoldenHour): locked dark text', () {
    for (final phase in [SkyPhase.dawn, SkyPhase.day, SkyPhase.goldenHour]) {
      final fg = LivingSky.getPalette(phase).foreground;

      test('$phase primaryText is locked #1A1A1A', () {
        expect(fg.primaryText, kBrightPrimary);
      });

      test('$phase secondaryText is locked #4A4A4A', () {
        expect(fg.secondaryText, kBrightSecondary);
      });

      test('$phase tertiaryText is locked #6B6B6B', () {
        expect(fg.tertiaryText, kBrightTertiary);
      });

      test('$phase primaryText is dark (luminance < 0.1)', () {
        expect(fg.primaryText.computeLuminance(), lessThan(0.1));
      });

      test('$phase has no body-text shadow (no contrast hacks)', () {
        expect(fg.textShadow, isEmpty);
        expect(fg.subtitleShadow, isEmpty);
        expect(fg.captionShadow, isEmpty);
      });
    }
  });

  group('Night phase: locked white text', () {
    final fg = LivingSky.getPalette(SkyPhase.night).foreground;

    test('night primaryText is locked #FFFFFF', () {
      expect(fg.primaryText, kNightPrimary);
    });

    test('night secondaryText is locked white @ 0.85', () {
      expect(fg.secondaryText, kNightSecondary);
    });

    test('night tertiaryText is locked white @ 0.65', () {
      expect(fg.tertiaryText, kNightTertiary);
    });

    test('night primaryText is light (luminance > 0.5)', () {
      expect(fg.primaryText.computeLuminance(), greaterThan(0.5));
    });

    test('night hero primary may have a shadow (raw-background lift)', () {
      // Allowed — this is the hero-text exception, not a contrast hack.
      // Body and caption shadows remain empty.
      expect(fg.subtitleShadow, isEmpty);
      expect(fg.captionShadow, isEmpty);
    });
  });

  group('Night phase: WCAG contrast against deep navy background', () {
    final palette = LivingSky.getPalette(SkyPhase.night);
    final fg = palette.foreground;
    final bg = palette.gradientColors[1];

    test('night primaryText has very strong contrast (≥ 10:1)', () {
      expect(contrastRatio(fg.primaryText, bg), greaterThanOrEqualTo(10.0));
    });

    test('night secondaryText contrast ≥ 4.5', () {
      expect(contrastRatio(fg.secondaryText, bg), greaterThanOrEqualTo(4.5));
    });

    test('night tertiaryText contrast ≥ 3.0', () {
      expect(contrastRatio(fg.tertiaryText, bg), greaterThanOrEqualTo(3.0));
    });
  });

  group('Bright phases: no white text leaks into the bright bucket', () {
    // Regression guard — the previous Phase 3.2 system rendered white
    // text at opacity in every phase. If any bright phase ever returns
    // a light color again, this will catch it.
    for (final phase in [SkyPhase.dawn, SkyPhase.day, SkyPhase.goldenHour]) {
      final fg = LivingSky.getPalette(phase).foreground;

      test('$phase primaryText is NOT white', () {
        expect(fg.primaryText, isNot(equals(Colors.white)));
        expect(fg.primaryText.computeLuminance(), lessThan(0.5));
      });

      test('$phase secondaryText is NOT white', () {
        expect(fg.secondaryText, isNot(equals(Colors.white)));
        expect(fg.secondaryText.computeLuminance(), lessThan(0.5));
      });

      test('$phase tertiaryText is NOT white', () {
        expect(fg.tertiaryText, isNot(equals(Colors.white)));
        expect(fg.tertiaryText.computeLuminance(), lessThan(0.5));
      });
    }
  });

  group('Night phase: no dark text leaks into the night bucket', () {
    final fg = LivingSky.getPalette(SkyPhase.night).foreground;

    test('night primaryText is light (> 0.5 luminance)', () {
      expect(fg.primaryText.computeLuminance(), greaterThan(0.5));
    });

    test('night secondaryText is light (> 0.5 luminance)', () {
      expect(fg.secondaryText.computeLuminance(), greaterThan(0.5));
    });

    test('night tertiaryText is light (> 0.5 luminance)', () {
      expect(fg.tertiaryText.computeLuminance(), greaterThan(0.5));
    });
  });

  group('Cross-phase tier ordering (primary > secondary > tertiary)', () {
    // Within a phase, each tier should step down in visual weight —
    // this keeps the hierarchy readable regardless of phase.
    for (final phase in SkyPhase.values) {
      final fg = LivingSky.getPalette(phase).foreground;
      final isNight = phase == SkyPhase.night;

      test('$phase tier ordering is primary > secondary > tertiary', () {
        if (isNight) {
          // Light tier: higher alpha = stronger.
          expect(fg.primaryText.a, greaterThanOrEqualTo(fg.secondaryText.a));
          expect(fg.secondaryText.a, greaterThanOrEqualTo(fg.tertiaryText.a));
        } else {
          // Dark tier: lower luminance = stronger.
          expect(fg.primaryText.computeLuminance(),
              lessThanOrEqualTo(fg.secondaryText.computeLuminance()));
          expect(fg.secondaryText.computeLuminance(),
              lessThanOrEqualTo(fg.tertiaryText.computeLuminance()));
        }
      });
    }
  });

  group('Subtle surface primitives (chip/container fill)', () {
    // subtleSurface + subtleBorder are the design-system primitives used
    // by inactive chips and quiet container panes (ambient sound block,
    // unselected ChoiceChips). They must adapt with the phase bucket —
    // translucent dark on bright phases, translucent white on Night.
    for (final phase in [SkyPhase.dawn, SkyPhase.day, SkyPhase.goldenHour]) {
      final fg = LivingSky.getPalette(phase).foreground;

      test('$phase subtleSurface is dark-family (matches bright bucket)', () {
        expect(fg.subtleSurface.computeLuminance(), lessThan(0.1));
      });

      test('$phase subtleBorder is dark-family', () {
        expect(fg.subtleBorder.computeLuminance(), lessThan(0.1));
      });

      test('$phase subtleBorder is stronger than subtleSurface', () {
        // Border alpha > fill alpha so the edge reads without overpowering.
        expect(fg.subtleBorder.a, greaterThan(fg.subtleSurface.a));
      });

      test('$phase subtleSurface is actually translucent (not opaque)', () {
        expect(fg.subtleSurface.a, lessThan(0.5));
      });
    }

    final nightFg = LivingSky.getPalette(SkyPhase.night).foreground;

    test('night subtleSurface is light-family (matches night bucket)', () {
      expect(nightFg.subtleSurface.computeLuminance(), greaterThan(0.5));
    });

    test('night subtleBorder is light-family', () {
      expect(nightFg.subtleBorder.computeLuminance(), greaterThan(0.5));
    });

    test('night subtleBorder is stronger than subtleSurface', () {
      expect(nightFg.subtleBorder.a, greaterThan(nightFg.subtleSurface.a));
    });

    test('night subtleSurface is actually translucent (not opaque)', () {
      expect(nightFg.subtleSurface.a, lessThan(0.5));
    });
  });

  group('SkyPalette.textColor matches ForegroundPalette contract', () {
    // buildTheme() feeds SkyPalette.textColor into the Material TextTheme,
    // so if it drifts from the ForegroundPalette contract, widgets that
    // inherit from the theme will render with the wrong color even though
    // ForegroundPalette itself is correct. Pin them together.
    for (final phase in [SkyPhase.dawn, SkyPhase.day, SkyPhase.goldenHour]) {
      final p = LivingSky.getPalette(phase);

      test('$phase SkyPalette.textColor is dark (matches bright bucket)', () {
        expect(p.textColor.computeLuminance(), lessThan(0.1));
      });

      test('$phase SkyPalette.subtitleColor is dark', () {
        expect(p.subtitleColor.computeLuminance(), lessThan(0.2));
      });
    }

    test('night SkyPalette.textColor is light', () {
      final p = LivingSky.getPalette(SkyPhase.night);
      expect(p.textColor.computeLuminance(), greaterThan(0.5));
    });
  });
}
