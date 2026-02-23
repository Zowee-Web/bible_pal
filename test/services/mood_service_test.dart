import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/mood_service.dart';

void main() {
  group('MoodService.generateCompassionateReply', () {
    test('returns a non-empty reply for each mood', () {
      final service = MoodService(random: Random(0));

      for (final mood in ['joyful', 'weary', 'anxious', 'hurting', 'neutral']) {
        final result = MoodResult(
          mood: mood,
          emotionalTags: [],
          confidenceScore: 0.8,
        );
        final reply = service.generateCompassionateReply(result);
        expect(reply.isNotEmpty, true, reason: '$mood reply should not be empty');
      }
    });

    test('replies have variety (at least 6 per mood)', () {
      for (final mood in ['joyful', 'weary', 'anxious', 'hurting', 'neutral']) {
        final replies = <String>{};
        for (var seed = 0; seed < 50; seed++) {
          final service = MoodService(random: Random(seed));
          final result = MoodResult(
            mood: mood,
            emotionalTags: [],
            confidenceScore: 0.8,
          );
          replies.add(service.generateCompassionateReply(result));
        }
        expect(replies.length, greaterThanOrEqualTo(6),
            reason: '$mood should have at least 6 unique replies');
      }
    });

    test('unknown mood falls back to neutral replies', () {
      final service = MoodService(random: Random(0));
      final result = MoodResult(
        mood: 'unknown_mood',
        emotionalTags: [],
        confidenceScore: 0.5,
      );
      final reply = service.generateCompassionateReply(result);
      expect(reply.isNotEmpty, true);
    });

    test('all replies contain a story transition', () {
      for (final mood in ['joyful', 'weary', 'anxious', 'hurting', 'neutral']) {
        for (var seed = 0; seed < 50; seed++) {
          final service = MoodService(random: Random(seed));
          final result = MoodResult(
            mood: mood,
            emotionalTags: [],
            confidenceScore: 0.8,
          );
          final reply = service.generateCompassionateReply(result);
          expect(
            reply.toLowerCase().contains('story') ||
                reply.toLowerCase().contains('something meaningful'),
            true,
            reason: '$mood reply should transition to story: "$reply"',
          );
        }
      }
    });
  });
}
