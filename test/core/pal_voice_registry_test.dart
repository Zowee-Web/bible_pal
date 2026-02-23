import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/pal_voice_registry.dart';

void main() {
  group('PalVoiceRegistry', () {
    test('contains exactly 4 voices', () {
      expect(PalVoiceRegistry.voices.length, 4);
    });

    test('has 2 male and 2 female voices', () {
      final males =
          PalVoiceRegistry.voices.where((v) => v.gender == 'male').toList();
      final females =
          PalVoiceRegistry.voices.where((v) => v.gender == 'female').toList();
      expect(males.length, 2);
      expect(females.length, 2);
    });

    test('default voice key exists in the list', () {
      expect(
        PalVoiceRegistry.voices
            .any((v) => v.voiceKey == PalVoiceRegistry.defaultVoiceKey),
        true,
      );
    });

    test('default voice is female', () {
      final defaultVoice =
          PalVoiceRegistry.getVoice(PalVoiceRegistry.defaultVoiceKey);
      expect(defaultVoice.gender, 'female');
    });

    test('all voice keys are unique', () {
      final keys = PalVoiceRegistry.voices.map((v) => v.voiceKey).toSet();
      expect(keys.length, PalVoiceRegistry.voices.length);
    });

    test('all voices have non-empty display names and descriptions', () {
      for (final voice in PalVoiceRegistry.voices) {
        expect(voice.displayName.isNotEmpty, true,
            reason: '${voice.voiceKey} displayName is empty');
        expect(voice.description.isNotEmpty, true,
            reason: '${voice.voiceKey} description is empty');
      }
    });

    test('getVoice returns correct voice for valid key', () {
      final voice = PalVoiceRegistry.getVoice('VOICE_JAMES_HUSKY');
      expect(voice.voiceKey, 'VOICE_JAMES_HUSKY');
      expect(voice.displayName, 'James');
    });

    test('getVoice returns default for unknown key', () {
      final voice = PalVoiceRegistry.getVoice('VOICE_UNKNOWN');
      expect(voice.voiceKey, PalVoiceRegistry.defaultVoiceKey);
    });

    test('getVoice returns default for null key', () {
      final voice = PalVoiceRegistry.getVoice(null);
      expect(voice.voiceKey, PalVoiceRegistry.defaultVoiceKey);
    });

    test('isValid returns true for all registered keys', () {
      for (final voice in PalVoiceRegistry.voices) {
        expect(PalVoiceRegistry.isValid(voice.voiceKey), true,
            reason: '${voice.voiceKey} should be valid');
      }
    });

    test('isValid returns false for unknown key', () {
      expect(PalVoiceRegistry.isValid('VOICE_UNKNOWN'), false);
    });

    test('voice keys match expected canonical keys', () {
      final expected = {
        'VOICE_SARAH_STORYTELLER',
        'VOICE_HANNAH_HOPE',
        'VOICE_JAMES_HUSKY',
        'VOICE_DAVID_SHEPHERD',
      };
      final actual = PalVoiceRegistry.voices.map((v) => v.voiceKey).toSet();
      expect(actual, expected);
    });
  });
}
