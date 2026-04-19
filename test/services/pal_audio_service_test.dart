import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/pal_audio_service.dart';
import 'package:bible_pal/core/pal_voice_registry.dart';

void main() {
  group('PalAudioService.assetPath', () {
    test('builds correct path for prompt', () {
      expect(
        PalAudioService.assetPath('VOICE_GRACE', 'MORNING_DAY_01'),
        'assets/pal/audio/VOICE_GRACE/MORNING_DAY_01.mp3',
      );
    });

    test('builds correct path for micro-response', () {
      expect(
        PalAudioService.assetPath('VOICE_SHEPHERD', 'RESP_JOY_01'),
        'assets/pal/audio/VOICE_SHEPHERD/RESP_JOY_01.mp3',
      );
    });

    test('builds correct path for preview (new PAL line)', () {
      expect(
        PalAudioService.assetPath(
            'VOICE_HOPE', PalAudioService.previewLineId),
        'assets/pal/audio/VOICE_HOPE/OPENING_GENTLE_01.mp3',
      );
    });

    test('builds correct path for onboarding', () {
      expect(
        PalAudioService.assetPath('VOICE_GRACE', 'onboard_01'),
        'assets/pal/audio/VOICE_GRACE/onboard_01.mp3',
      );
    });

    test('all voice keys produce valid paths', () {
      for (final voice in PalVoiceRegistry.voices) {
        final path =
            PalAudioService.assetPath(voice.voiceKey, 'MORNING_DAY_01');
        expect(path, contains(voice.voiceKey));
        expect(path, endsWith('.mp3'));
        expect(path, startsWith('assets/pal/audio/'));
      }
    });
  });

  group('PalLine', () {
    test('can be constructed with id and text', () {
      const line = PalLine(id: 'test_01', text: 'Hello friend.');
      expect(line.id, 'test_01');
      expect(line.text, 'Hello friend.');
    });
  });

  group('PalAudioService.assetPath for new line types', () {
    test('builds correct path for opening line', () {
      expect(
        PalAudioService.assetPath('VOICE_GRACE', 'OPENING_GENTLE_01'),
        'assets/pal/audio/VOICE_GRACE/OPENING_GENTLE_01.mp3',
      );
    });

    test('builds correct path for reflection line', () {
      expect(
        PalAudioService.assetPath('VOICE_SHEPHERD', 'REFL_JOYFUL_01'),
        'assets/pal/audio/VOICE_SHEPHERD/REFL_JOYFUL_01.mp3',
      );
    });

    test('builds correct path for tone-biased reflection', () {
      expect(
        PalAudioService.assetPath(
            'VOICE_HOPE', 'REFL_TB_JOYFUL_GENTLE_01'),
        'assets/pal/audio/VOICE_HOPE/REFL_TB_JOYFUL_GENTLE_01.mp3',
      );
    });

    test('builds correct path for framing line', () {
      expect(
        PalAudioService.assetPath(
            'VOICE_GRACE', 'FRAME_DAVID_ANOINTED_01'),
        'assets/pal/audio/VOICE_GRACE/FRAME_DAVID_ANOINTED_01.mp3',
      );
    });

    test('builds correct path for transition line', () {
      expect(
        PalAudioService.assetPath('VOICE_STILLWATER', 'TRANS_01'),
        'assets/pal/audio/VOICE_STILLWATER/TRANS_01.mp3',
      );
    });
  });
}
