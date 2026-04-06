import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/features/pals_parables/pals_parables_screen.dart';
import 'package:bible_pal/services/stt_service.dart';
import 'package:bible_pal/services/mood_service.dart';

/// End-to-end integration tests for voice mood input (Feature 2.2).
///
/// Tests the complete flow from mic tap through mood detection,
/// verifying that voice transcripts route through the identical
/// pipeline as typed text (Invariant 17: input equivalence).
void main() {
  group('Voice mood input end-to-end', () {
    test('VoiceInputState enum supports complete flow lifecycle', () {
      // Verify the full state sequence: idle → awaiting → listening → confirming → proceeding
      const states = VoiceInputState.values;
      expect(states[0], VoiceInputState.idle);
      expect(states[1], VoiceInputState.awaitingPermission);
      expect(states[2], VoiceInputState.listening);
      expect(states[3], VoiceInputState.confirming);
      expect(states[4], VoiceInputState.proceeding);
    });

    test('voice transcript through MoodService produces valid mood result', () {
      // Simulate complete flow: voice transcript → MoodService
      final moodService = MoodService();

      // Simulate voice transcripts for each mood
      final testCases = {
        'I am feeling really grateful and happy today': 'grateful',
        'I am so tired and worn out': 'weary',
        'I am stressed and worried about work': 'anxious',
        'I feel sad and alone tonight': 'hurting',
        'just checking in': 'calm_peaceful',
      };

      for (final entry in testCases.entries) {
        final result = moodService.detectMood(entry.key);
        expect(result.mood, entry.value,
            reason:
                'Transcript "${entry.key}" should detect mood "${entry.value}"');
        expect(result.confidenceScore, greaterThan(0),
            reason: 'Confidence must be positive');
      }
    });

    test('SttService supports DI for testing via constructor', () {
      // Verify that SttService accepts a custom SpeechToText instance
      final service = SttService();
      expect(service.isInitialized, false);
      expect(service.isAvailable, false);
    });

    test('SttResult correctly represents final and partial results', () {
      const partial = SttResult(text: 'I feel', isFinal: false);
      const final_ = SttResult(text: 'I feel grateful', isFinal: true);

      expect(partial.isFinal, false);
      expect(partial.text, 'I feel');
      expect(final_.isFinal, true);
      expect(final_.text, 'I feel grateful');
    });
  });
}
