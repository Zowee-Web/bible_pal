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

    test('default voice key is VOICE_HOPE', () {
      expect(PalVoiceRegistry.defaultVoiceKey, 'VOICE_HOPE');
    });

    test('default voice exists in the list', () {
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

    test('all voices have non-empty display names, descriptions, and emojis',
        () {
      for (final voice in PalVoiceRegistry.voices) {
        expect(voice.displayName.isNotEmpty, true,
            reason: '${voice.voiceKey} displayName is empty');
        expect(voice.description.isNotEmpty, true,
            reason: '${voice.voiceKey} description is empty');
        expect(voice.emoji.isNotEmpty, true,
            reason: '${voice.voiceKey} emoji is empty');
      }
    });

    test('voice keys match expected PAL canonical keys', () {
      final expected = {
        'VOICE_HOPE',
        'VOICE_SHEPHERD',
        'VOICE_RUTH_COMFORT',
        'VOICE_STILLWATER',
      };
      final actual = PalVoiceRegistry.voices.map((v) => v.voiceKey).toSet();
      expect(actual, expected);
    });

    test('getVoice returns correct voice for valid key', () {
      final voice = PalVoiceRegistry.getVoice('VOICE_SHEPHERD');
      expect(voice.voiceKey, 'VOICE_SHEPHERD');
      expect(voice.displayName, 'Shepherd');
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
  });

  group('PalVoiceRegistry voice key migration', () {
    test('old voice keys are recognized as legacy', () {
      expect(PalVoiceRegistry.isLegacyKey('VOICE_SARAH_STORYTELLER'), true);
      expect(PalVoiceRegistry.isLegacyKey('VOICE_HANNAH_HOPE'), true);
      expect(PalVoiceRegistry.isLegacyKey('VOICE_JAMES_HUSKY'), true);
      expect(PalVoiceRegistry.isLegacyKey('VOICE_DAVID_SHEPHERD'), true);
    });

    test('current voice keys are not legacy', () {
      expect(PalVoiceRegistry.isLegacyKey('VOICE_HOPE'), false);
      expect(PalVoiceRegistry.isLegacyKey('VOICE_SHEPHERD'), false);
      expect(PalVoiceRegistry.isLegacyKey('VOICE_RUTH_COMFORT'), false);
      expect(PalVoiceRegistry.isLegacyKey('VOICE_STILLWATER'), false);
    });

    test('VOICE_GRACE is now legacy', () {
      // Grace was retired 2026-04-23; existing users on Grace
      // migrate to the current default (Hope) on next launch.
      expect(PalVoiceRegistry.isLegacyKey('VOICE_GRACE'), true);
    });

    test('migrateVoiceKey maps old keys to current default', () {
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_SARAH_STORYTELLER'),
          'VOICE_HOPE');
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_HANNAH_HOPE'),
          'VOICE_HOPE');
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_JAMES_HUSKY'),
          'VOICE_HOPE');
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_DAVID_SHEPHERD'),
          'VOICE_HOPE');
      expect(
          PalVoiceRegistry.migrateVoiceKey('VOICE_GRACE'), 'VOICE_HOPE');
    });

    test('migrateVoiceKey preserves valid current keys', () {
      // Existing users on any current voice (including Ruth, who is
      // no longer the default but remains valid) keep their choice.
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_HOPE'), 'VOICE_HOPE');
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_SHEPHERD'),
          'VOICE_SHEPHERD');
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_RUTH_COMFORT'),
          'VOICE_RUTH_COMFORT');
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_STILLWATER'),
          'VOICE_STILLWATER');
    });

    test('migrateVoiceKey maps unknown keys to current default', () {
      expect(
          PalVoiceRegistry.migrateVoiceKey('VOICE_UNKNOWN'), 'VOICE_HOPE');
    });
  });
}
