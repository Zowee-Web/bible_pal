import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/pal_audio_service.dart';
import 'package:bible_pal/core/pal_voice_registry.dart';

void main() {
  group('PalAudioService.moodToBucket', () {
    test('joyful maps to positive', () {
      expect(PalAudioService.moodToBucket('joyful'), 'positive');
    });

    test('weary maps to negative', () {
      expect(PalAudioService.moodToBucket('weary'), 'negative');
    });

    test('anxious maps to negative', () {
      expect(PalAudioService.moodToBucket('anxious'), 'negative');
    });

    test('hurting maps to negative', () {
      expect(PalAudioService.moodToBucket('hurting'), 'negative');
    });

    test('neutral maps to neutral', () {
      expect(PalAudioService.moodToBucket('neutral'), 'neutral');
    });

    test('unknown mood falls back to neutral', () {
      expect(PalAudioService.moodToBucket('unknown'), 'neutral');
    });
  });

  group('PalAudioService.assetPath', () {
    test('builds correct path for greeting', () {
      expect(
        PalAudioService.assetPath('VOICE_SARAH_STORYTELLER', 'greeting_01'),
        'assets/pal/audio/VOICE_SARAH_STORYTELLER/greeting_01.mp3',
      );
    });

    test('builds correct path for compassionate reply', () {
      expect(
        PalAudioService.assetPath('VOICE_JAMES_HUSKY', 'comp_neg_03'),
        'assets/pal/audio/VOICE_JAMES_HUSKY/comp_neg_03.mp3',
      );
    });

    test('builds correct path for preview', () {
      expect(
        PalAudioService.assetPath('VOICE_HANNAH_HOPE', 'preview_01'),
        'assets/pal/audio/VOICE_HANNAH_HOPE/preview_01.mp3',
      );
    });

    test('builds correct path for onboarding', () {
      expect(
        PalAudioService.assetPath('VOICE_SARAH_STORYTELLER', 'onboard_01'),
        'assets/pal/audio/VOICE_SARAH_STORYTELLER/onboard_01.mp3',
      );
    });

    test('all voice keys produce valid paths', () {
      for (final voice in PalVoiceRegistry.voices) {
        final path = PalAudioService.assetPath(voice.voiceKey, 'greeting_01');
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
}
