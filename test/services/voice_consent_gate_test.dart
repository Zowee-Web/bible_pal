// CRITICAL VOICE CONSENT GATE TEST
// This test verifies the VoiceConsentGate enforces the tri-state consent model.
// The gate is the SINGLE SOURCE OF TRUTH for voice playback authorization.
//
// DO NOT DISABLE OR WEAKEN THIS TEST.

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/voice_consent_gate.dart';
import 'package:bible_pal/models/user_preferences.dart';

void main() {
  group('CRITICAL: VoiceConsentGate', () {
    group('checkStoryNarration', () {
      test('CRITICAL: returns needsConsent when storyNarrationEnabled is null', () {
        final prefs = UserPreferences.defaults();
        expect(prefs.storyNarrationEnabled, isNull);

        final result = VoiceConsentGate.checkStoryNarration(prefs);

        expect(
          result,
          VoiceGateResult.needsConsent,
          reason: '🚨 CONSENT GATE: null must return needsConsent',
        );
      });

      test('CRITICAL: returns blocked when storyNarrationEnabled is false', () {
        final prefs = UserPreferences(
          faithTradition: '',
          bibleTranslation: 'WEB',
          storyNarrationEnabled: false,
        );

        final result = VoiceConsentGate.checkStoryNarration(prefs);

        expect(
          result,
          VoiceGateResult.blocked,
          reason: '🚨 CONSENT GATE: false must return blocked',
        );
      });

      test('CRITICAL: returns allowed ONLY when storyNarrationEnabled is true', () {
        final prefs = UserPreferences(
          faithTradition: '',
          bibleTranslation: 'WEB',
          storyNarrationEnabled: true,
        );

        final result = VoiceConsentGate.checkStoryNarration(prefs);

        expect(
          result,
          VoiceGateResult.allowed,
          reason: 'true must return allowed',
        );
      });

      test('CRITICAL: returns needsConsent when prefs is null', () {
        final result = VoiceConsentGate.checkStoryNarration(null);

        expect(
          result,
          VoiceGateResult.needsConsent,
          reason: '🚨 CONSENT GATE: null prefs must return needsConsent',
        );
      });
    });

    group('checkPalGreetings', () {
      test('CRITICAL: returns needsConsent when palGreetingsEnabled is null', () {
        final prefs = UserPreferences.defaults();
        expect(prefs.palGreetingsEnabled, isNull);

        final result = VoiceConsentGate.checkPalGreetings(prefs);

        expect(
          result,
          VoiceGateResult.needsConsent,
          reason: '🚨 CONSENT GATE: null must return needsConsent',
        );
      });

      test('CRITICAL: returns blocked when palGreetingsEnabled is false', () {
        final prefs = UserPreferences(
          faithTradition: '',
          bibleTranslation: 'WEB',
          palGreetingsEnabled: false,
        );

        final result = VoiceConsentGate.checkPalGreetings(prefs);

        expect(
          result,
          VoiceGateResult.blocked,
          reason: '🚨 CONSENT GATE: false must return blocked',
        );
      });

      test('CRITICAL: returns allowed ONLY when palGreetingsEnabled is true', () {
        final prefs = UserPreferences(
          faithTradition: '',
          bibleTranslation: 'WEB',
          palGreetingsEnabled: true,
        );

        final result = VoiceConsentGate.checkPalGreetings(prefs);

        expect(
          result,
          VoiceGateResult.allowed,
          reason: 'true must return allowed',
        );
      });

      test('CRITICAL: returns needsConsent when prefs is null', () {
        final result = VoiceConsentGate.checkPalGreetings(null);

        expect(
          result,
          VoiceGateResult.needsConsent,
          reason: '🚨 CONSENT GATE: null prefs must return needsConsent',
        );
      });
    });

    group('Independence of consent types', () {
      test('story narration and PAL greetings are checked independently', () {
        // Story enabled, PAL disabled
        final prefs1 = UserPreferences(
          faithTradition: '',
          bibleTranslation: 'WEB',
          storyNarrationEnabled: true,
          palGreetingsEnabled: false,
        );

        expect(VoiceConsentGate.checkStoryNarration(prefs1), VoiceGateResult.allowed);
        expect(VoiceConsentGate.checkPalGreetings(prefs1), VoiceGateResult.blocked);

        // Story disabled, PAL enabled
        final prefs2 = UserPreferences(
          faithTradition: '',
          bibleTranslation: 'WEB',
          storyNarrationEnabled: false,
          palGreetingsEnabled: true,
        );

        expect(VoiceConsentGate.checkStoryNarration(prefs2), VoiceGateResult.blocked);
        expect(VoiceConsentGate.checkPalGreetings(prefs2), VoiceGateResult.allowed);

        // Story null, PAL true
        final prefs3 = UserPreferences(
          faithTradition: '',
          bibleTranslation: 'WEB',
          storyNarrationEnabled: null,
          palGreetingsEnabled: true,
        );

        expect(VoiceConsentGate.checkStoryNarration(prefs3), VoiceGateResult.needsConsent);
        expect(VoiceConsentGate.checkPalGreetings(prefs3), VoiceGateResult.allowed);
      });
    });
  });
}
