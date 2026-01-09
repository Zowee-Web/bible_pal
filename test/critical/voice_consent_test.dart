// CRITICAL VOICE CONSENT TEST
// This test ensures voice audio NEVER plays without explicit user consent.
// The tri-state consent model (null/false/true) MUST be enforced correctly.
//
// DO NOT DISABLE OR WEAKEN THIS TEST.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/models/user_preferences.dart';

void main() {
  group('CRITICAL: Voice Consent System', () {
    group('Tri-state consent model', () {
      test('CRITICAL: null consent means user has NOT been asked', () {
        // ARRANGE: Default preferences (never asked)
        final prefs = UserPreferences.defaults();

        // ASSERT: Consent fields are null (not asked)
        expect(
          prefs.storyNarrationEnabled,
          isNull,
          reason: '🚨 CONSENT VIOLATION 🚨\n'
              'Default preferences MUST have storyNarrationEnabled=null\n'
              'to indicate user has not been asked for consent.\n'
              'null = not asked, true = enabled, false = disabled',
        );
        expect(
          prefs.palGreetingsEnabled,
          isNull,
          reason: '🚨 CONSENT VIOLATION 🚨\n'
              'Default preferences MUST have palGreetingsEnabled=null\n'
              'to indicate user has not been asked for consent.',
        );
        expect(
          prefs.voiceConsentVersion,
          isNull,
          reason: 'voiceConsentVersion MUST be null for fresh preferences.',
        );
      });

      test('CRITICAL: hasAskedStoryNarrationConsent returns false when null', () {
        // ARRANGE: Preferences with null consent
        final prefs = UserPreferences.defaults();

        // ASSERT: Helper correctly identifies not-asked state
        expect(
          prefs.hasAskedStoryNarrationConsent,
          false,
          reason: 'hasAskedStoryNarrationConsent MUST return false when '
              'storyNarrationEnabled is null (not asked yet).',
        );
      });

      test('CRITICAL: hasAskedStoryNarrationConsent returns true when false', () {
        // ARRANGE: User explicitly declined
        final prefs = UserPreferences(
          faithTradition: '',
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

      test('CRITICAL: hasAskedStoryNarrationConsent returns true when true', () {
        // ARRANGE: User enabled narration
        final prefs = UserPreferences(
          faithTradition: '',
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

      test('CRITICAL: isStoryNarrationEnabled returns false when null', () {
        // ARRANGE: Not asked yet
        final prefs = UserPreferences.defaults();

        // ASSERT: Must NOT return true for null (not enabled)
        expect(
          prefs.isStoryNarrationEnabled,
          false,
          reason: '🚨 CONSENT VIOLATION 🚨\n'
              'isStoryNarrationEnabled MUST return false when null.\n'
              'Audio must NEVER play without explicit consent (true).',
        );
      });

      test('CRITICAL: isStoryNarrationEnabled returns false when false', () {
        // ARRANGE: User declined
        final prefs = UserPreferences(
          faithTradition: '',
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
          faithTradition: '',
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
      test('CRITICAL: PAL greetings consent follows same tri-state pattern', () {
        // ARRANGE: Not asked
        final notAsked = UserPreferences.defaults();

        // ASSERT
        expect(notAsked.hasAskedPalGreetingsConsent, false);
        expect(notAsked.isPalGreetingsEnabled, false);

        // ARRANGE: Declined
        final declined = UserPreferences(
          faithTradition: '',
          bibleTranslation: 'WEB',
          palGreetingsEnabled: false,
          voiceConsentVersion: currentVoiceConsentVersion,
        );

        // ASSERT
        expect(declined.hasAskedPalGreetingsConsent, true);
        expect(declined.isPalGreetingsEnabled, false);

        // ARRANGE: Enabled
        final enabled = UserPreferences(
          faithTradition: '',
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
          faithTradition: '',
          bibleTranslation: 'WEB',
          storyNarrationEnabled: true,
          palGreetingsEnabled: true,
          voiceConsentVersion: currentVoiceConsentVersion,
        );

        // ASSERT: Version is recorded
        expect(
          prefs.voiceConsentVersion,
          currentVoiceConsentVersion,
          reason: 'voiceConsentVersion MUST be set to currentVoiceConsentVersion '
              'when consent is granted.',
        );
      });

      test('CRITICAL: needsConsentVersionUpgrade detects outdated consent', () {
        // ARRANGE: Old consent version (simulate future version bump)
        final oldConsent = UserPreferences(
          faithTradition: '',
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

      test('needsConsentVersionUpgrade returns false for null version', () {
        // ARRANGE: Never consented (null version)
        final prefs = UserPreferences.defaults();

        // ASSERT: null version means never consented, not "needs upgrade"
        expect(
          prefs.needsConsentVersionUpgrade,
          false,
          reason: 'needsConsentVersionUpgrade should return false when '
              'voiceConsentVersion is null (never consented).',
        );
      });

      test('needsConsentVersionUpgrade returns false for current version', () {
        // ARRANGE: Current consent version
        final prefs = UserPreferences(
          faithTradition: '',
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
      test('CRITICAL: null consent persists correctly through JSON', () {
        // ARRANGE: Default preferences
        final original = UserPreferences.defaults();

        // ACT: Serialize and deserialize
        final json = original.toJson();
        final restored = UserPreferences.fromJson(json);

        // ASSERT: null consent is preserved
        expect(
          restored.storyNarrationEnabled,
          isNull,
          reason: '🚨 CONSENT VIOLATION 🚨\n'
              'null storyNarrationEnabled MUST be preserved through JSON.\n'
              'If null becomes false after persistence, consent UI may not show.',
        );
        expect(
          restored.palGreetingsEnabled,
          isNull,
          reason: 'null palGreetingsEnabled MUST be preserved through JSON.',
        );
        expect(
          restored.voiceConsentVersion,
          isNull,
          reason: 'null voiceConsentVersion MUST be preserved through JSON.',
        );
      });

      test('CRITICAL: false consent persists correctly through JSON', () {
        // ARRANGE: User declined
        final original = UserPreferences(
          faithTradition: 'Protestant',
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
          faithTradition: 'Protestant',
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

      test('Legacy JSON without voice fields defaults to null (not false)', () {
        // ARRANGE: Old JSON without voice consent fields (migration case)
        final legacyJson = {
          'faithTradition': 'Protestant',
          'bibleTranslation': 'WEB',
          'storytellingMode': 'creative',
          'contentFilteringEnabled': true,
          'kidFriendlyOnly': false,
          'hasCompletedOnboarding': true,
          // Note: No storyNarrationEnabled, palGreetingsEnabled, voiceConsentVersion
        };

        // ACT: Parse legacy JSON
        final prefs = UserPreferences.fromJson(legacyJson);

        // ASSERT: Voice fields default to null (not false)
        expect(
          prefs.storyNarrationEnabled,
          isNull,
          reason: '🚨 MIGRATION BUG 🚨\n'
              'Legacy JSON without voice fields MUST default to null.\n'
              'Defaulting to false would skip the consent dialog for existing users!',
        );
        expect(
          prefs.palGreetingsEnabled,
          isNull,
          reason: 'Legacy JSON without voice fields MUST default to null.',
        );
        expect(
          prefs.voiceConsentVersion,
          isNull,
          reason: 'Legacy JSON without voice fields MUST default to null.',
        );
      });
    });

    group('copyWith behavior', () {
      test('CRITICAL: copyWith preserves null consent when not specified', () {
        // ARRANGE: Preferences with null consent
        final original = UserPreferences.defaults();

        // ACT: Update unrelated field
        final updated = original.copyWith(faithTradition: 'Catholic');

        // ASSERT: Null consent is preserved
        expect(
          updated.storyNarrationEnabled,
          isNull,
          reason: 'copyWith MUST preserve null consent when not specified.',
        );
        expect(
          updated.palGreetingsEnabled,
          isNull,
          reason: 'copyWith MUST preserve null consent when not specified.',
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
          faithTradition: '',
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
