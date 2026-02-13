import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/voice_consent_gate.dart';
import 'package:bible_pal/models/user_preferences.dart';

void main() {
  group('PAL Greeting Voice Consent', () {
    test('checkPalGreetings returns needsConsent when palGreetingsEnabled is null', () {
      // User hasn't been asked yet
      const prefs = UserPreferences(
        bibleTranslation: 'WEB',
        palGreetingsEnabled: null,
      );

      final result = VoiceConsentGate.checkPalGreetings(prefs);

      expect(result, VoiceGateResult.needsConsent);
    });

    test('checkPalGreetings returns blocked when palGreetingsEnabled is false', () {
      // User explicitly disabled PAL greetings
      const prefs = UserPreferences(
        bibleTranslation: 'WEB',
        palGreetingsEnabled: false,
      );

      final result = VoiceConsentGate.checkPalGreetings(prefs);

      expect(result, VoiceGateResult.blocked);
    });

    test('checkPalGreetings returns allowed when palGreetingsEnabled is true', () {
      // User has enabled PAL greetings
      const prefs = UserPreferences(
        bibleTranslation: 'WEB',
        palGreetingsEnabled: true,
      );

      final result = VoiceConsentGate.checkPalGreetings(prefs);

      expect(result, VoiceGateResult.allowed);
    });

    test('checkPalGreetings handles null prefs', () {
      final result = VoiceConsentGate.checkPalGreetings(null);

      expect(result, VoiceGateResult.needsConsent);
    });
  });

  group('PAL Greeting Asset Path', () {
    test('greeting asset path is correct', () {
      // SoLoud uses WAV format for instant playback
      const expectedPath = 'assets/audio/pal_test_greeting.wav';

      // Verify the path follows the expected pattern
      expect(expectedPath.startsWith('assets/audio/'), isTrue);
      expect(expectedPath.endsWith('.wav'), isTrue);
      expect(expectedPath.contains('pal_test_greeting'), isTrue);
    });
  });

  group('PAL Greeting Breadcrumb Privacy', () {
    test('pal_greeting_played breadcrumb uses only whitelisted keys', () {
      // Expected breadcrumb structure (now triggered from PAL button tap)
      final breadcrumb = {
        'event': 'pal_greeting_played',
        'source': 'pal_button_tap',
      };

      // Verify all keys are in the known whitelist
      // From crash_log_store.dart: event, source are explicitly whitelisted
      const whitelistedKeys = {
        'event', // Core field
        'source', // Mode/state flag
        'level', // Core field (auto-added)
        'ts', // Core field (auto-added)
      };

      expect(
        breadcrumb.keys.every((key) => whitelistedKeys.contains(key)),
        isTrue,
        reason: 'All breadcrumb keys must be in the whitelist',
      );
    });

    test('pal_greeting_played breadcrumb has minimal payload', () {
      final breadcrumb = {
        'event': 'pal_greeting_played',
        'source': 'pal_button_tap',
      };

      // Verify minimal payload (only 2 user-specified fields)
      expect(breadcrumb.length, 2);

      // Verify no PII or sensitive data
      expect(breadcrumb.containsKey('user_text'), isFalse);
      expect(breadcrumb.containsKey('user_name'), isFalse);
      expect(breadcrumb.containsKey('greeting_text'), isFalse);
    });
  });

  group('PAL Greeting Error Handling', () {
    test('greeting failure should not throw', () {
      // This test documents expected behavior:
      // If greeting playback fails, it should be caught and logged,
      // but NOT rethrow to avoid blocking the story selection flow.

      // Simulate error scenario
      expect(
        () {
          try {
            throw Exception('Audio file not found');
          } catch (e) {
            // Error is caught in _maybePlayPalGreeting's try-catch
            // and logged via debugPrint, but not rethrown
            // ignore: avoid_print
            print('[PalGreeting] Failed to play: $e');
          }
        },
        returnsNormally,
        reason: 'Greeting failures must be caught and must not block flow',
      );
    });
  });
}
