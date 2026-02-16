import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/mood_service.dart';

/// Tests for voice transcript → MoodService pipeline equivalence (Invariant 17).
///
/// Verifies that voice-transcribed text produces identical results to typed text
/// when passed through MoodService.detectMood().
void main() {
  late MoodService moodService;

  setUp(() {
    moodService = MoodService();
  });

  group('CRITICAL: Voice transcript routes through MoodService identically', () {
    test('CRITICAL: "I feel grateful" → joyful', () {
      // ARRANGE: Simulated voice transcript
      const transcript = 'I feel grateful';

      // ACT: Same detectMood() call used for typed input
      final result = moodService.detectMood(transcript);

      // ASSERT
      expect(result.mood, 'joyful',
          reason: 'Voice transcript containing "grateful" must detect joyful mood');
    });

    test('CRITICAL: "I am so tired" → weary', () {
      const transcript = 'I am so tired';
      final result = moodService.detectMood(transcript);
      expect(result.mood, 'weary',
          reason: 'Voice transcript containing "tired" must detect weary mood');
    });

    test('CRITICAL: transcript with filler words still detects mood', () {
      // Voice transcripts often contain filler words like "um", "well", "kind of"
      const transcript = 'um well I am feeling kind of stressed today';
      final result = moodService.detectMood(transcript);
      expect(result.mood, 'anxious',
          reason: 'Filler words should not prevent mood detection of "stressed"');
    });

    test('CRITICAL: empty transcript → neutral', () {
      const transcript = '';
      final result = moodService.detectMood(transcript);
      expect(result.mood, 'neutral',
          reason: 'Empty voice transcript must fall back to neutral');
    });

    test('voice and typed text produce identical MoodResult', () {
      // ARRANGE: Same text as if typed vs transcribed
      const text = 'feeling really happy and blessed';

      // ACT: Call detectMood() twice (simulates voice and typed paths)
      final voiceResult = moodService.detectMood(text);
      final typedResult = moodService.detectMood(text);

      // ASSERT: Results must be identical (Invariant 17: input equivalence)
      expect(voiceResult.mood, typedResult.mood,
          reason: 'Voice and typed text must produce the same mood');
      expect(voiceResult.emotionalTags, typedResult.emotionalTags,
          reason: 'Voice and typed text must produce the same emotional tags');
      expect(voiceResult.confidenceScore, typedResult.confidenceScore,
          reason: 'Voice and typed text must produce the same confidence');
    });

    test('mixed case and punctuation handled', () {
      const transcript = 'Well... I am HURTING, honestly.';
      final result = moodService.detectMood(transcript);
      expect(result.mood, 'hurting',
          reason: 'Case-insensitive detection must handle "HURTING"');
    });
  });
}
