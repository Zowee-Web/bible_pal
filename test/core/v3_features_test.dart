import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/mood_service.dart';
import 'package:bible_pal/models/journal_entry.dart';
import 'package:bible_pal/models/parable.dart';

void main() {
  group('Mood Detection: new moods', () {
    final service = MoodService(random: Random(42));

    test('detects grateful from "thankful" keywords', () {
      expect(service.detectMood('I am so grateful today').mood, 'grateful');
      expect(service.detectMood('feeling blessed and thankful').mood, 'grateful');
    });

    test('detects brave_courage from courage keywords', () {
      expect(service.detectMood('I need to be brave').mood, 'brave_courage');
      expect(service.detectMood('finding courage today').mood, 'brave_courage');
    });

    test('detects calm_peaceful from calm keywords', () {
      expect(service.detectMood('I feel so peaceful right now').mood, 'calm_peaceful');
      expect(service.detectMood('feeling calm and quiet').mood, 'calm_peaceful');
    });

    test('detects encouraging from motivated keywords', () {
      expect(service.detectMood('feeling motivated and energized').mood, 'encouraging');
      expect(service.detectMood('I am ready to go').mood, 'encouraging');
    });

    test('grateful takes priority over joyful for grateful keywords', () {
      // "grateful" should match grateful, not joyful (even though joyful had it before)
      expect(service.detectMood('I am grateful').mood, 'grateful');
      expect(service.detectMood('so thankful').mood, 'grateful');
    });

    test('empty input defaults to calm_peaceful', () {
      expect(service.detectMood('').mood, 'calm_peaceful');
    });

    test('unrecognized input defaults to weary (safe fallback)', () {
      expect(service.detectMood('hello there').mood, 'weary');
    });
  });

  group('Mood micro-responses: all moods covered', () {
    test('every mood has micro-responses', () {
      final service = MoodService(random: Random(0));
      for (final mood in ['joyful', 'grateful', 'weary', 'anxious', 'hurting', 'brave_courage', 'calm_peaceful', 'encouraging']) {
        final text = service.getMicroResponseText(mood);
        expect(text, isNotEmpty, reason: '$mood should have a micro-response');
      }
    });

    test('all micro-responses are 12 words or fewer', () {
      for (final mood in ['joyful', 'grateful', 'weary', 'anxious', 'hurting', 'brave_courage', 'calm_peaceful', 'encouraging']) {
        for (var seed = 0; seed < 50; seed++) {
          final s = MoodService(random: Random(seed));
          final text = s.getMicroResponseText(mood);
          final wordCount = text.split(RegExp(r'\s+')).length;
          expect(wordCount, lessThanOrEqualTo(12),
              reason: '$mood response "$text" has $wordCount words (max 12)');
        }
      }
    });
  });

  group('JournalEntry model', () {
    test('fromJson/toJson round-trip', () {
      final entry = JournalEntry(
        id: 'abc123',
        storyId: 'story_2001',
        storyTitle: 'The Quiet River',
        mood: 'calm_peaceful',
        note: 'This reminded me of my grandmother.',
        createdAt: DateTime(2026, 3, 28, 10, 30),
      );

      final json = entry.toJson();
      final restored = JournalEntry.fromJson(json);

      expect(restored.id, 'abc123');
      expect(restored.storyId, 'story_2001');
      expect(restored.storyTitle, 'The Quiet River');
      expect(restored.mood, 'calm_peaceful');
      expect(restored.note, 'This reminded me of my grandmother.');
      expect(restored.createdAt.year, 2026);
    });
  });

  group('Parable model: new fields', () {
    test('timeOfDay field round-trips through JSON', () {
      final parable = Parable(
        storyId: 'test_1',
        title: 'Test',
        mood: 'joyful',
        storytellingMode: 'creative',
        kidFriendly: false,
        timeOfDay: 'morning',
      );

      final json = parable.toJson();
      expect(json['timeOfDay'], 'morning');

      final restored = Parable.fromJson(json);
      expect(restored.timeOfDay, 'morning');
    });

    test('seasonTag field round-trips through JSON', () {
      final parable = Parable(
        storyId: 'test_2',
        title: 'Test',
        mood: 'joyful',
        storytellingMode: 'traditional',
        kidFriendly: true,
        seasonTag: 'advent',
      );

      final json = parable.toJson();
      expect(json['seasonTag'], 'advent');

      final restored = Parable.fromJson(json);
      expect(restored.seasonTag, 'advent');
    });

    test('null timeOfDay and seasonTag are omitted from JSON', () {
      final parable = Parable(
        storyId: 'test_3',
        title: 'Test',
        mood: 'joyful',
        storytellingMode: 'creative',
        kidFriendly: false,
      );

      final json = parable.toJson();
      expect(json.containsKey('timeOfDay'), false);
      expect(json.containsKey('seasonTag'), false);
    });
  });
}
