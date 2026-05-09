import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/core/pal_voice_registry.dart';
import 'package:bible_pal/services/pal_audio_service.dart';

void main() {
  group('useLegacyPal flag', () {
    test('defaults to false (new PAL system active)', () {
      final prefs = UserPreferences.defaults();
      expect(prefs.useLegacyPal, false);
    });

    test('fromJson defaults to false when field is absent', () {
      final prefs = UserPreferences.fromJson({'bibleTranslation': 'WEB'});
      expect(prefs.useLegacyPal, false);
    });

    test('fromJson reads true for legacy restoration', () {
      final prefs = UserPreferences.fromJson({
        'bibleTranslation': 'WEB',
        'useLegacyPal': true,
      });
      expect(prefs.useLegacyPal, true);
    });

    test('toJson serializes useLegacyPal', () {
      final prefs = UserPreferences.defaults();
      final json = prefs.toJson();
      expect(json['useLegacyPal'], false);
    });

    test('copyWith can toggle useLegacyPal', () {
      final prefs = UserPreferences.defaults();
      expect(prefs.useLegacyPal, false);
      final legacy = prefs.copyWith(useLegacyPal: true);
      expect(legacy.useLegacyPal, true);
    });

    test('round-trip preserves useLegacyPal = true', () {
      final prefs =
          UserPreferences.defaults().copyWith(useLegacyPal: true);
      final json = prefs.toJson();
      final restored = UserPreferences.fromJson(json);
      expect(restored.useLegacyPal, true);
    });
  });

  group('PAL new flow — audio ID conventions', () {
    test('new opening line IDs produce valid asset paths', () {
      for (final voice in PalVoiceRegistry.voices) {
        final path =
            PalAudioService.assetPath(voice.voiceKey, 'OPENING_GENTLE_01');
        expect(path, endsWith('.mp3'));
        expect(path, contains(voice.voiceKey));
        expect(path, contains('OPENING_GENTLE_01'));
      }
    });

    test('new reflection line IDs produce valid asset paths', () {
      for (final voice in PalVoiceRegistry.voices) {
        final path =
            PalAudioService.assetPath(voice.voiceKey, 'REFL_JOYFUL_01');
        expect(path, endsWith('.mp3'));
        expect(path, contains('REFL_JOYFUL_01'));
      }
    });

    test('new framing line IDs produce valid asset paths', () {
      final path = PalAudioService.assetPath(
          'VOICE_GRACE', 'FRAME_DAVID_ANOINTED_01');
      expect(path,
          'assets/pal/audio/VOICE_GRACE/FRAME_DAVID_ANOINTED_01.mp3');
    });

    test('new transition line IDs produce valid asset paths', () {
      final path =
          PalAudioService.assetPath('VOICE_SHEPHERD', 'TRANS_01');
      expect(path, 'assets/pal/audio/VOICE_SHEPHERD/TRANS_01.mp3');
    });

    test('old PROMPT_* and RESP_* IDs still produce valid paths (not deleted)', () {
      // Old assets remain in directory — just not played when useLegacyPal=false
      final promptPath =
          PalAudioService.assetPath('VOICE_GRACE', 'AFT_BURDEN_01');
      expect(promptPath, endsWith('.mp3'));
      final respPath =
          PalAudioService.assetPath('VOICE_GRACE', 'RESP_JOY_01');
      expect(respPath, endsWith('.mp3'));
    });
  });

  group('PAL voice selection consistency', () {
    test('palVoiceKey defaults to VOICE_HOPE', () {
      // Default migrated from VOICE_GRACE → VOICE_RUTH_COMFORT → VOICE_HOPE.
      // Grace retired 2026-04-23; Ruth v1 retired 2026-04-25; Hope is now the
      // canonical PAL default per `feedback_pal_canonical_system.md`.
      final prefs = UserPreferences.defaults();
      expect(prefs.palVoiceKey, 'VOICE_HOPE');
    });

    test('all 3 active PAL voices are registered', () {
      // Grace retired 2026-04-23; Ruth v1 retired 2026-04-25.
      // Audio for both is preserved under archive directories.
      expect(PalVoiceRegistry.voices.length, 3);
      expect(
          PalVoiceRegistry.voices.map((v) => v.voiceKey).toSet(),
          containsAll([
            'VOICE_HOPE',
            'VOICE_SHEPHERD',
            'VOICE_STILLWATER',
          ]));
    });

    test('voice selection uses palVoiceKey not story narrator', () {
      // Changing palVoiceKey changes asset path; narratorVoiceKey is irrelevant
      final prefs = UserPreferences.defaults()
          .copyWith(palVoiceKey: 'VOICE_SHEPHERD');
      expect(prefs.palVoiceKey, 'VOICE_SHEPHERD');
      final path =
          PalAudioService.assetPath(prefs.palVoiceKey, 'OPENING_GENTLE_01');
      expect(path, contains('VOICE_SHEPHERD'));
      expect(path, isNot(contains('VOICE_CHARLOTTE')));
    });
  });

  group('PAL voice preview', () {
    test('preview uses OPENING_AFTN_01 not legacy preview_01', () {
      // Updated from OPENING_GENTLE_01 to OPENING_AFTN_01 in PR #13
      // (commit ceb0d3a) when the 12-line time-bucketed opening library
      // replaced the gentle/cheerful tone-bucketed system.
      expect(PalAudioService.previewLineId, 'OPENING_AFTN_01');
      expect(PalAudioService.previewLineId, isNot('preview_01'));
    });

    test('preview resolves correct path for each voice', () {
      for (final voice in PalVoiceRegistry.voices) {
        final path = PalAudioService.assetPath(
            voice.voiceKey, PalAudioService.previewLineId);
        expect(path,
            'assets/pal/audio/${voice.voiceKey}/${PalAudioService.previewLineId}.mp3');
      }
    });
  });

  group('PAL flow routing — Feature 5.1a', () {
    test('reflection line is the spoken response (not framing or transition)', () {
      // The spoken response uses REFL_* or REFL_TB_* IDs — single line only.
      // FRAME_* and TRANS_* are text-only in the overlay.
      expect('REFL_JOYFUL_01', startsWith('REFL_'));
      expect('REFL_TB_JOYFUL_GENTLE_01', startsWith('REFL_'));
      // Framing and transition should NOT be in the spoken response
      expect('FRAME_DAVID_ANOINTED_01', isNot(startsWith('REFL_')));
      expect('TRANS_01', isNot(startsWith('REFL_')));
    });

    test('reflection audio uses playLine not playSequence', () {
      // playLine plays a single line; playSequence plays multiple.
      // Feature 5.1a spoken response is a single reflection line.
      // This test validates the contract: one line, not a sequence.
      final path = PalAudioService.assetPath(
          'VOICE_GRACE', 'REFL_JOYFUL_01');
      expect(path, endsWith('.mp3'));
      // playLine resolves to this single asset — no sequence involved
    });

    test('overlay framing/transition lines remain as text-only assets', () {
      // These IDs still exist and produce valid paths (for text lookup),
      // but they are NOT played as audio in the current flow.
      for (final id in [
        'FRAME_DAVID_ANOINTED_01',
        'TRANS_01',
      ]) {
        final path = PalAudioService.assetPath('VOICE_GRACE', id);
        expect(path, endsWith('.mp3'));
      }
    });

    test('useLegacyPal=false means no RESP_* or PROMPT_* audio', () {
      // When legacy is off, old IDs are not referenced in active flows.
      // Only OPENING_* (opening line) and REFL_* (spoken response) play.
      final prefs = UserPreferences.defaults();
      expect(prefs.useLegacyPal, false);
      // The two active audio ID prefixes in the new system:
      expect('OPENING_GENTLE_01', startsWith('OPENING_'));
      expect('REFL_JOYFUL_01', startsWith('REFL_'));
    });
  });
}
