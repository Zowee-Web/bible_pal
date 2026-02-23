// CRITICAL VOICE CONSENT TEST
// This test ensures voice features default to ON and respect user's OFF choice.
// The consent model: true (default ON), false (user disabled), null (edge case).
//
// DO NOT DISABLE OR WEAKEN THIS TEST.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/models/user_preferences.dart';

void main() {
  group('CRITICAL: Voice Consent System', () {
    group('Defaults-ON consent model', () {
      test('CRITICAL: default preferences have voice features ON', () {
        // ARRANGE: Default preferences
        final prefs = UserPreferences.defaults();

        // ASSERT: Consent fields default to true (ON by default)
        expect(
          prefs.storyNarrationEnabled,
          true,
          reason: 'Default preferences MUST have storyNarrationEnabled=true.\n'
              'Voice features are ON by default until user turns them OFF.',
        );
        expect(
          prefs.palGreetingsEnabled,
          true,
          reason: 'Default preferences MUST have palGreetingsEnabled=true.\n'
              'Voice features are ON by default until user turns them OFF.',
        );
        expect(
          prefs.voiceConsentVersion,
          currentVoiceConsentVersion,
          reason:
              'voiceConsentVersion MUST be set for default preferences.',
        );
      });

      test('CRITICAL: hasAskedStoryNarrationConsent returns true for defaults',
          () {
        // ARRANGE: Default preferences (ON by default)
        final prefs = UserPreferences.defaults();

        // ASSERT: Defaults are treated as "asked" (value is non-null)
        expect(
          prefs.hasAskedStoryNarrationConsent,
          true,
          reason: 'hasAskedStoryNarrationConsent MUST return true when '
              'storyNarrationEnabled is true (default ON).',
        );
      });

      test('CRITICAL: hasAskedStoryNarrationConsent returns true when false',
          () {
        // ARRANGE: User explicitly declined
        final prefs = UserPreferences(
          bibleTranslation: 'WEB',
          storyNarrationEnabled: false,
          voiceConsentVersion: currentVoiceConsentVersion,
        );

        // ASSERT: Helper correctly identifies asked state (even if declined)
        expect(
          prefs.hasAskedStoryNarrationConsent,
          true,
          reason: 'hasAskedStoryNarrationConsent MUST return true when '
              'storyNarrationEnabled is false (user declined, but was asked).',
        );
      });

      test('CRITICAL: hasAskedStoryNarrationConsent returns true when true',
          () {
        // ARRANGE: User enabled narration
        final prefs = UserPreferences(
          bibleTranslation: 'WEB',
          storyNarrationEnabled: true,
          voiceConsentVersion: currentVoiceConsentVersion,
        );

        // ASSERT: Helper correctly identifies asked state
        expect(
          prefs.hasAskedStoryNarrationConsent,
          true,
          reason: 'hasAskedStoryNarrationConsent MUST return true when '
              'storyNarrationEnabled is true (user enabled).',
        );
      });

      test('CRITICAL: isStoryNarrationEnabled returns true for defaults', () {
        // ARRANGE: Default (ON)
        final prefs = UserPreferences.defaults();

        // ASSERT: Must return true for defaults (ON by default)
        expect(
          prefs.isStoryNarrationEnabled,
          true,
          reason: 'isStoryNarrationEnabled MUST return true for defaults.\n'
              'Voice features are ON by default.',
        );
      });

      test('CRITICAL: isStoryNarrationEnabled returns false when false', () {
        // ARRANGE: User declined
        final prefs = UserPreferences(
          bibleTranslation: 'WEB',
          storyNarrationEnabled: false,
          voiceConsentVersion: currentVoiceConsentVersion,
        );

        // ASSERT
        expect(
          prefs.isStoryNarrationEnabled,
          false,
          reason: 'isStoryNarrationEnabled MUST return false when disabled.',
        );
      });

      test('CRITICAL: isStoryNarrationEnabled returns true ONLY when true', () {
        // ARRANGE: User enabled
        final prefs = UserPreferences(
          bibleTranslation: 'WEB',
          storyNarrationEnabled: true,
          voiceConsentVersion: currentVoiceConsentVersion,
        );

        // ASSERT
        expect(
          prefs.isStoryNarrationEnabled,
          true,
          reason: 'isStoryNarrationEnabled should return true when enabled.',
        );
      });
    });

    group('PAL greetings consent', () {
      test('CRITICAL: PAL greetings defaults to ON, respects user OFF', () {
        // ARRANGE: Defaults (ON)
        final defaults = UserPreferences.defaults();

        // ASSERT: Defaults are ON
        expect(defaults.hasAskedPalGreetingsConsent, true);
        expect(defaults.isPalGreetingsEnabled, true);

        // ARRANGE: Declined
        final declined = UserPreferences(
          bibleTranslation: 'WEB',
          palGreetingsEnabled: false,
          voiceConsentVersion: currentVoiceConsentVersion,
        );

        // ASSERT
        expect(declined.hasAskedPalGreetingsConsent, true);
        expect(declined.isPalGreetingsEnabled, false);

        // ARRANGE: Enabled
        final enabled = UserPreferences(
          bibleTranslation: 'WEB',
          palGreetingsEnabled: true,
          voiceConsentVersion: currentVoiceConsentVersion,
        );

        // ASSERT
        expect(enabled.hasAskedPalGreetingsConsent, true);
        expect(enabled.isPalGreetingsEnabled, true);
      });
    });

    group('Consent version tracking', () {
      test('CRITICAL: voiceConsentVersion tracks schema version', () {
        // ARRANGE: User granted consent
        final prefs = UserPreferences(
          bibleTranslation: 'WEB',
          storyNarrationEnabled: true,
          palGreetingsEnabled: true,
          voiceConsentVersion: currentVoiceConsentVersion,
        );

        // ASSERT: Version is recorded
        expect(
          prefs.voiceConsentVersion,
          currentVoiceConsentVersion,
          reason:
              'voiceConsentVersion MUST be set to currentVoiceConsentVersion '
              'when consent is granted.',
        );
      });

      test('CRITICAL: needsConsentVersionUpgrade detects outdated consent', () {
        // ARRANGE: Old consent version (simulate future version bump)
        final oldConsent = UserPreferences(
          bibleTranslation: 'WEB',
          storyNarrationEnabled: true,
          voiceConsentVersion: 0, // Old version
        );

        // ASSERT: Should need upgrade if current version > saved version
        if (currentVoiceConsentVersion > 0) {
          expect(
            oldConsent.needsConsentVersionUpgrade,
            true,
            reason: 'needsConsentVersionUpgrade MUST return true when '
                'saved version < currentVoiceConsentVersion.',
          );
        }
      });

      test('needsConsentVersionUpgrade returns false for current version', () {
        // ARRANGE: Current consent version (defaults)
        final prefs = UserPreferences.defaults();

        // ASSERT: No upgrade needed
        expect(
          prefs.needsConsentVersionUpgrade,
          false,
          reason: 'needsConsentVersionUpgrade should return false when '
              'voiceConsentVersion equals currentVoiceConsentVersion.',
        );
      });

      test('needsConsentVersionUpgrade returns false for current version (explicit)',
          () {
        // ARRANGE: Current consent version
        final prefs = UserPreferences(
          bibleTranslation: 'WEB',
          storyNarrationEnabled: true,
          voiceConsentVersion: currentVoiceConsentVersion,
        );

        // ASSERT: No upgrade needed
        expect(
          prefs.needsConsentVersionUpgrade,
          false,
          reason: 'needsConsentVersionUpgrade should return false when '
              'voiceConsentVersion equals currentVoiceConsentVersion.',
        );
      });
    });

    group('JSON persistence', () {
      test('CRITICAL: default consent (true) persists correctly through JSON',
          () {
        // ARRANGE: Default preferences (ON by default)
        final original = UserPreferences.defaults();

        // ACT: Serialize and deserialize
        final json = original.toJson();
        final restored = UserPreferences.fromJson(json);

        // ASSERT: true consent is preserved
        expect(
          restored.storyNarrationEnabled,
          true,
          reason: 'Default storyNarrationEnabled (true) MUST persist through JSON.',
        );
        expect(
          restored.palGreetingsEnabled,
          true,
          reason: 'Default palGreetingsEnabled (true) MUST persist through JSON.',
        );
        expect(
          restored.voiceConsentVersion,
          currentVoiceConsentVersion,
          reason:
              'Default voiceConsentVersion MUST persist through JSON.',
        );
      });

      test('CRITICAL: false consent persists correctly through JSON', () {
        // ARRANGE: User declined
        final original = UserPreferences(
          bibleTranslation: 'WEB',
          storyNarrationEnabled: false,
          palGreetingsEnabled: false,
          voiceConsentVersion: currentVoiceConsentVersion,
        );

        // ACT: Serialize and deserialize
        final json = original.toJson();
        final restored = UserPreferences.fromJson(json);

        // ASSERT: false consent is preserved
        expect(
          restored.storyNarrationEnabled,
          false,
          reason: 'false storyNarrationEnabled MUST be preserved through JSON.',
        );
        expect(
          restored.palGreetingsEnabled,
          false,
          reason: 'false palGreetingsEnabled MUST be preserved through JSON.',
        );
        expect(
          restored.voiceConsentVersion,
          currentVoiceConsentVersion,
          reason: 'voiceConsentVersion MUST be preserved through JSON.',
        );
      });

      test('CRITICAL: true consent persists correctly through JSON', () {
        // ARRANGE: User enabled
        final original = UserPreferences(
          bibleTranslation: 'WEB',
          storyNarrationEnabled: true,
          palGreetingsEnabled: true,
          voiceConsentVersion: currentVoiceConsentVersion,
        );

        // ACT: Serialize and deserialize
        final json = original.toJson();
        final restored = UserPreferences.fromJson(json);

        // ASSERT: true consent is preserved
        expect(
          restored.storyNarrationEnabled,
          true,
          reason: 'true storyNarrationEnabled MUST be preserved through JSON.',
        );
        expect(
          restored.palGreetingsEnabled,
          true,
          reason: 'true palGreetingsEnabled MUST be preserved through JSON.',
        );
      });

      test('Legacy JSON without voice fields defaults to true (ON by default)',
          () {
        // ARRANGE: Old JSON without voice consent fields (migration case)
        final legacyJson = {
          'bibleTranslation': 'WEB',
          'storytellingMode': 'creative',
          'contentFilteringEnabled': true,
          'kidFriendlyOnly': false,
          'hasCompletedOnboarding': true,
          // Note: No storyNarrationEnabled, palGreetingsEnabled, voiceConsentVersion
        };

        // ACT: Parse legacy JSON
        final prefs = UserPreferences.fromJson(legacyJson);

        // ASSERT: Voice fields default to true (ON by default)
        expect(
          prefs.storyNarrationEnabled,
          true,
          reason: 'Legacy JSON without voice fields MUST default to true (ON).\n'
              'Voice features are ON by default for all users.',
        );
        expect(
          prefs.palGreetingsEnabled,
          true,
          reason: 'Legacy JSON without voice fields MUST default to true (ON).',
        );
        expect(
          prefs.voiceConsentVersion,
          isNull,
          reason: 'Legacy JSON without voice version should remain null.',
        );
      });
    });

    group('copyWith behavior', () {
      test('CRITICAL: copyWith preserves default consent when not specified',
          () {
        // ARRANGE: Preferences with default consent (true)
        final original = UserPreferences.defaults();

        // ACT: Update unrelated field
        final updated = original.copyWith(bibleTranslation: 'KJV');

        // ASSERT: Default consent is preserved
        expect(
          updated.storyNarrationEnabled,
          true,
          reason: 'copyWith MUST preserve consent when not specified.',
        );
        expect(
          updated.palGreetingsEnabled,
          true,
          reason: 'copyWith MUST preserve consent when not specified.',
        );
      });

      test('copyWith can set consent to true', () {
        // ARRANGE
        final original = UserPreferences.defaults();

        // ACT
        final updated = original.copyWith(
          storyNarrationEnabled: true,
          voiceConsentVersion: currentVoiceConsentVersion,
        );

        // ASSERT
        expect(updated.storyNarrationEnabled, true);
        expect(updated.voiceConsentVersion, currentVoiceConsentVersion);
      });

      test('copyWith can set consent to false', () {
        // ARRANGE: Previously enabled
        final original = UserPreferences(
          bibleTranslation: 'WEB',
          storyNarrationEnabled: true,
          voiceConsentVersion: currentVoiceConsentVersion,
        );

        // ACT: Disable
        final updated = original.copyWith(storyNarrationEnabled: false);

        // ASSERT
        expect(updated.storyNarrationEnabled, false);
      });
    });
  });
}
