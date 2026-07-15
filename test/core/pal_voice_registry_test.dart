import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/pal_voice_registry.dart';

void main() {
  group('PalVoiceRegistry', () {
    test('contains exactly 3 active voices', () {
      // Ruth v1 retired 2026-04-25 (audio archived to
      // assets/pal/audio_archive_ruth_v1_2026_04_25/). Grace was
      // retired 2026-04-23. Miriam is staged (registered, not yet
      // selectable) until her audio library renders — see the
      // staged-voices group below.
      expect(PalVoiceRegistry.voices.length, 3);
    });

    test('has 2 male and 1 female voices', () {
      // Active roster: Hope (female), Shepherd (male),
      // Stillwater (male). Miriam (female, staged) balances this
      // to 2/2 when she activates.
      final males =
          PalVoiceRegistry.voices.where((v) => v.gender == 'male').toList();
      final females =
          PalVoiceRegistry.voices.where((v) => v.gender == 'female').toList();
      expect(males.length, 2);
      expect(females.length, 1);
    });

    test('default voice key is VOICE_STILLWATER', () {
      // Switched from VOICE_HOPE → VOICE_STILLWATER 2026-06-27 to
      // align with PAL Memory Slice 2d: Stillwater is the only voice
      // with rendered memory clips, so the default must point at it
      // for new installs to ever hear a memory line.
      expect(PalVoiceRegistry.defaultVoiceKey, 'VOICE_STILLWATER');
    });

    test('default voice exists in the list', () {
      expect(
        PalVoiceRegistry.voices
            .any((v) => v.voiceKey == PalVoiceRegistry.defaultVoiceKey),
        true,
      );
    });

    test('default voice is male (Stillwater)', () {
      final defaultVoice =
          PalVoiceRegistry.getVoice(PalVoiceRegistry.defaultVoiceKey);
      expect(defaultVoice.gender, 'male');
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

  group('PalVoiceRegistry staged voices', () {
    // Staged = registered with an approved persona and ElevenLabs
    // source, but no rendered PAL audio library yet. Must stay
    // invisible to the picker and runtime until activation
    // (SPEC 17b, ADR-029).
    test('Miriam is staged with pinned key, ID, and gender', () {
      final miriam = PalVoiceRegistry.stagedVoices
          .firstWhere((v) => v.voiceKey == 'VOICE_MIRIAM');
      expect(miriam.displayName, 'Miriam');
      expect(miriam.gender, 'female');
      expect(miriam.elevenLabsId, 'XrExE9yKIg1WjnnlVkGX');
    });

    test('staged voices are not in the active list', () {
      final activeKeys =
          PalVoiceRegistry.voices.map((v) => v.voiceKey).toSet();
      for (final staged in PalVoiceRegistry.stagedVoices) {
        expect(activeKeys.contains(staged.voiceKey), false,
            reason: '${staged.voiceKey} must not be active while staged');
      }
    });

    test('staged keys are not valid and migrate to the default', () {
      for (final staged in PalVoiceRegistry.stagedVoices) {
        expect(PalVoiceRegistry.isValid(staged.voiceKey), false,
            reason: '${staged.voiceKey} must not validate while staged');
        expect(PalVoiceRegistry.migrateVoiceKey(staged.voiceKey),
            PalVoiceRegistry.defaultVoiceKey,
            reason: '${staged.voiceKey} must migrate to default '
                'while staged');
      }
    });

    test('staged voices never resolve via getVoice', () {
      for (final staged in PalVoiceRegistry.stagedVoices) {
        expect(PalVoiceRegistry.getVoice(staged.voiceKey).voiceKey,
            PalVoiceRegistry.defaultVoiceKey);
      }
    });

    test('PAL keys (active + staged) are disjoint from the narrator pool',
        () {
      // PAL voices and story narrator voices are two separate systems
      // that must never share keys (story_voice_registry.py, permanent
      // rule). Miriam's ElevenLabs SOURCE is shared with narrator
      // VOICE_MIRIAM_JOYFUL (owner-approved exception, ADR-029), but
      // the keys stay distinct — this guards the key namespace, not
      // the source voice.
      final voicesJson = jsonDecode(
              File('server/voices.json').readAsStringSync())
          as Map<String, dynamic>;
      final narratorKeys = (voicesJson['voices'] as List<dynamic>)
          .map((v) => (v as Map<String, dynamic>)['voiceKey'] as String)
          .toSet();
      final palKeys = [
        ...PalVoiceRegistry.voices,
        ...PalVoiceRegistry.stagedVoices,
      ].map((v) => v.voiceKey).toSet();
      expect(palKeys.intersection(narratorKeys), isEmpty,
          reason: 'PAL voice keys must never appear in the narrator pool');
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
      expect(PalVoiceRegistry.isLegacyKey('VOICE_STILLWATER'), false);
    });

    test('retired voices are legacy', () {
      // Grace retired 2026-04-23, Ruth v1 retired 2026-04-25.
      // Existing users on either migrate to the current default
      // on next launch.
      expect(PalVoiceRegistry.isLegacyKey('VOICE_GRACE'), true);
      expect(PalVoiceRegistry.isLegacyKey('VOICE_RUTH_COMFORT'), true);
    });

    test('migrateVoiceKey maps old keys to current default', () {
      // Default switched to VOICE_STILLWATER 2026-06-27 (see
      // pal_voice_registry.dart docstring).
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_SARAH_STORYTELLER'),
          'VOICE_STILLWATER');
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_HANNAH_HOPE'),
          'VOICE_STILLWATER');
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_JAMES_HUSKY'),
          'VOICE_STILLWATER');
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_DAVID_SHEPHERD'),
          'VOICE_STILLWATER');
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_GRACE'),
          'VOICE_STILLWATER');
      // Ruth v1 retired 2026-04-25 — existing Ruth users land on the
      // current default on next launch.
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_RUTH_COMFORT'),
          'VOICE_STILLWATER');
    });

    test('migrateVoiceKey preserves valid current keys (incl. HOPE)', () {
      // Hope is still a valid choice — users who explicitly selected
      // Hope keep Hope; only legacy/unknown keys migrate to the
      // current default.
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_HOPE'), 'VOICE_HOPE');
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_SHEPHERD'),
          'VOICE_SHEPHERD');
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_STILLWATER'),
          'VOICE_STILLWATER');
    });

    test('migrateVoiceKey maps unknown keys to current default', () {
      expect(PalVoiceRegistry.migrateVoiceKey('VOICE_UNKNOWN'),
          'VOICE_STILLWATER');
    });
  });
}
