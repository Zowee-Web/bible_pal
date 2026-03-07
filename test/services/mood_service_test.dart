import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/mood_service.dart';

void main() {
  group('MoodService.getMicroResponseText', () {
    test('returns a non-empty response for each mood', () {
      final service = MoodService(random: Random(0));

      for (final mood in ['joyful', 'weary', 'anxious', 'hurting', 'neutral']) {
        final text = service.getMicroResponseText(mood);
        expect(text.isNotEmpty, true,
            reason: '$mood response should not be empty');
      }
    });

    test('unknown mood falls back to neutral', () {
      final service = MoodService(random: Random(0));
      final text = service.getMicroResponseText('unknown_mood');
      expect(text.isNotEmpty, true);
    });

    test('all micro-response texts are 12 words or fewer', () {
      for (final mood in ['joyful', 'weary', 'anxious', 'hurting', 'neutral']) {
        for (var seed = 0; seed < 50; seed++) {
          final s = MoodService(random: Random(seed));
          final text = s.getMicroResponseText(mood);
          final wordCount = text.split(RegExp(r'\s+')).length;
          expect(wordCount, lessThanOrEqualTo(12),
              reason: '$mood response "$text" has $wordCount words (max 12)');
        }
      }
    });

    test('all micro-response texts contain a transition indicator', () {
      for (final mood in ['joyful', 'weary', 'anxious', 'hurting', 'neutral']) {
        for (var seed = 0; seed < 50; seed++) {
          final s = MoodService(random: Random(seed));
          final text = s.getMicroResponseText(mood);
          final lower = text.toLowerCase();
          expect(
            lower.contains('story') ||
                lower.contains('listen') ||
                lower.contains('play') ||
                lower.contains('share') ||
                lower.contains('hear') ||
                lower.contains('something') ||
                lower.contains("here's"),
            true,
            reason: '$mood response should contain a transition indicator: "$text"',
          );
        }
      }
    });
  });

  group('MoodService.detectMood', () {
    test('detects mood from keywords', () {
      final service = MoodService(random: Random(0));
      final result = service.detectMood('I am feeling very anxious today');
      expect(result.mood, isNotEmpty);
    });

    test('returns neutral for empty input', () {
      final service = MoodService(random: Random(0));
      final result = service.detectMood('');
      expect(result.mood, 'neutral');
    });
  });
}
