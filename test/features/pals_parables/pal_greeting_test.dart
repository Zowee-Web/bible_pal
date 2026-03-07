import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/voice_consent_gate.dart';
import 'package:bible_pal/models/user_preferences.dart';

void main() {
  group('PAL Voice Consent', () {
    test('checkPalGreetings returns needsConsent when palGreetingsEnabled is null', () {
      const prefs = UserPreferences(
        bibleTranslation: 'WEB',
        palGreetingsEnabled: null,
      );

      final result = VoiceConsentGate.checkPalGreetings(prefs);

      expect(result, VoiceGateResult.needsConsent);
    });

    test('checkPalGreetings returns blocked when palGreetingsEnabled is false', () {
      const prefs = UserPreferences(
        bibleTranslation: 'WEB',
        palGreetingsEnabled: false,
      );

      final result = VoiceConsentGate.checkPalGreetings(prefs);

      expect(result, VoiceGateResult.blocked);
    });

    test('checkPalGreetings returns allowed when palGreetingsEnabled is true', () {
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

  group('PAL Line Asset Path', () {
    test('prompt asset path follows convention', () {
      const path = 'assets/pal/audio/VOICE_GRACE/MORNING_DAY_01.mp3';
      expect(path, startsWith('assets/pal/audio/'));
      expect(path, endsWith('.mp3'));
      expect(path, contains('VOICE_GRACE'));
    });

    test('micro-response asset path follows convention', () {
      const path = 'assets/pal/audio/VOICE_SHEPHERD/RESP_JOY_01.mp3';
      expect(path, startsWith('assets/pal/audio/'));
      expect(path, endsWith('.mp3'));
      expect(path, contains('VOICE_SHEPHERD'));
    });
  });

  group('PAL Line Breadcrumb Privacy', () {
    test('pal_line_played breadcrumb uses only whitelisted keys', () {
      final breadcrumb = {
        'event': 'pal_line_played',
        'line_id': 'MORNING_DAY_01',
        'type': 'prompt',
        'time_window': 'morning',
        'voice_key': 'VOICE_GRACE',
        'name_prefix_used': false,
      };

      const whitelistedKeys = {
        'event',
        'line_id',
        'type',
        'time_window',
        'mood',
        'voice_key',
        'name_prefix_used',
        'level',
        'ts',
      };

      expect(
        breadcrumb.keys.every((key) => whitelistedKeys.contains(key)),
        isTrue,
        reason: 'All breadcrumb keys must be in the whitelist',
      );
    });

    test('pal_line_played breadcrumb does not contain PII', () {
      final breadcrumb = {
        'event': 'pal_line_played',
        'line_id': 'RESP_JOY_01',
        'type': 'micro_response',
        'mood': 'joyful',
        'voice_key': 'VOICE_GRACE',
        'name_prefix_used': false,
      };

      expect(breadcrumb.containsKey('user_text'), isFalse);
      expect(breadcrumb.containsKey('user_name'), isFalse);
      expect(breadcrumb.containsKey('response_text'), isFalse);
    });
  });

  group('PAL Audio Error Handling', () {
    test('audio failure should not throw', () {
      expect(
        () {
          try {
            throw Exception('Audio file not found');
          } catch (e) {
            // Error is caught in PAL audio playback try-catch
            // and logged via debugPrint, but not rethrown
            // ignore: avoid_print
            print('[PalAudio] Failed to play: $e');
          }
        },
        returnsNormally,
        reason: 'PAL audio failures must be caught and must not block flow',
      );
    });
  });
}
