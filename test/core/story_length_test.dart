// CRITICAL: Story Length System Tests
// These tests verify the LOCKED SPEC for storyLength:
// - short: 250-600 words
// - full: 601-1200 words
// - long: 1201-2000 words
//
// DO NOT WEAKEN THESE TESTS.

@Tags(['critical'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/story_length_bucket.dart';
import 'package:bible_pal/models/parable.dart';

void main() {
  group('LOCKED SPEC: StoryLengthBucket word count ranges', () {
    test('short: 250-600 words', () {
      final range = StoryLengthBucket.short.wordCountRange;
      expect(range.$1, 250, reason: 'short min should be 250');
      expect(range.$2, 600, reason: 'short max should be 600');
    });

    test('full: 601-1200 words', () {
      final range = StoryLengthBucket.full.wordCountRange;
      expect(range.$1, 601, reason: 'full min should be 601');
      expect(range.$2, 1200, reason: 'full max should be 1200');
    });

    test('long: 1201-2000 words', () {
      final range = StoryLengthBucket.long.wordCountRange;
      expect(range.$1, 1201, reason: 'long min should be 1201');
      expect(range.$2, 2000, reason: 'long max should be 2000');
    });

    test('ranges are contiguous (no gaps at boundaries)', () {
      // short max + 1 = full min
      expect(StoryLengthBucket.short.wordCountRange.$2 + 1,
          StoryLengthBucket.full.wordCountRange.$1,
          reason: 'No gap between short max (600) and full min (601)');

      // full max + 1 = long min
      expect(StoryLengthBucket.full.wordCountRange.$2 + 1,
          StoryLengthBucket.long.wordCountRange.$1,
          reason: 'No gap between full max (1200) and long min (1201)');
    });
  });

  group('LOCKED SPEC: wordCountToBucket() function', () {
    test('boundary: 600 words -> short', () {
      expect(wordCountToBucket(600), StoryLengthBucket.short);
    });

    test('boundary: 601 words -> full', () {
      expect(wordCountToBucket(601), StoryLengthBucket.full);
    });

    test('boundary: 1200 words -> full', () {
      expect(wordCountToBucket(1200), StoryLengthBucket.full);
    });

    test('boundary: 1201 words -> long', () {
      expect(wordCountToBucket(1201), StoryLengthBucket.long);
    });

    test('edge cases within ranges', () {
      // Short range
      expect(wordCountToBucket(250), StoryLengthBucket.short);
      expect(wordCountToBucket(400), StoryLengthBucket.short);
      expect(wordCountToBucket(599), StoryLengthBucket.short);

      // Full range
      expect(wordCountToBucket(602), StoryLengthBucket.full);
      expect(wordCountToBucket(900), StoryLengthBucket.full);
      expect(wordCountToBucket(1199), StoryLengthBucket.full);

      // Long range
      expect(wordCountToBucket(1202), StoryLengthBucket.long);
      expect(wordCountToBucket(1500), StoryLengthBucket.long);
      expect(wordCountToBucket(2000), StoryLengthBucket.long);
    });

    test('very short stories (< 250) still map to short', () {
      expect(wordCountToBucket(100), StoryLengthBucket.short);
      expect(wordCountToBucket(1), StoryLengthBucket.short);
    });

    test('very long stories (> 2000) still map to long', () {
      expect(wordCountToBucket(2500), StoryLengthBucket.long);
      expect(wordCountToBucket(5000), StoryLengthBucket.long);
    });
  });

  group('StoryLengthBucket display labels', () {
    test('labels are exactly: Short Story, Full Story, Long Story', () {
      expect(StoryLengthBucket.short.displayLabel, 'Short Story');
      expect(StoryLengthBucket.full.displayLabel, 'Full Story');
      expect(StoryLengthBucket.long.displayLabel, 'Long Story');
    });

    test('no notes, descriptions, or minutes in labels', () {
      for (final bucket in StoryLengthBucket.values) {
        final label = bucket.displayLabel;
        expect(label.contains('min'), false,
            reason: 'Label should not contain "min"');
        expect(label.contains('minute'), false,
            reason: 'Label should not contain "minute"');
        expect(label.contains('note'), false,
            reason: 'Label should not contain "note"');
        expect(label.contains('('), false,
            reason: 'Label should not contain parentheses');
      }
    });
  });

  group('StoryLengthBucket serialization', () {
    test('toJson returns exact enum name', () {
      expect(StoryLengthBucket.short.toJson(), 'short');
      expect(StoryLengthBucket.full.toJson(), 'full');
      expect(StoryLengthBucket.long.toJson(), 'long');
    });

    test('fromJson parses valid values', () {
      expect(StoryLengthBucket.fromJson('short'), StoryLengthBucket.short);
      expect(StoryLengthBucket.fromJson('full'), StoryLengthBucket.full);
      expect(StoryLengthBucket.fromJson('long'), StoryLengthBucket.long);
    });

    test('fromJson defaults to short for invalid values', () {
      expect(StoryLengthBucket.fromJson('invalid'), StoryLengthBucket.short);
      expect(StoryLengthBucket.fromJson(''), StoryLengthBucket.short);
      expect(StoryLengthBucket.fromJson('SHORT'), StoryLengthBucket.short);
      expect(StoryLengthBucket.fromJson('5min'), StoryLengthBucket.short);
    });
  });

  group('Legacy minute-to-bucket mapping', () {
    test('5 min -> short', () {
      expect(lengthMinutesToBucket(5), StoryLengthBucket.short);
    });

    test('10 min -> short', () {
      expect(lengthMinutesToBucket(10), StoryLengthBucket.short);
    });

    test('15 min -> full', () {
      expect(lengthMinutesToBucket(15), StoryLengthBucket.full);
    });

    test('20 min -> long', () {
      expect(lengthMinutesToBucket(20), StoryLengthBucket.long);
    });
  });

  group('Parable model storyLength field', () {
    test('storyLength field is used when present', () {
      final parable = Parable(
        storyId: 'test_001',
        title: 'Test Story',
        mood: 'joyful',
        length: 5, // Legacy: would map to short
        storyLength: 'long', // Explicit: should override
        storytellingMode: 'creative',
        kidFriendly: false,
      );

      expect(parable.lengthBucket, StoryLengthBucket.long,
          reason: 'storyLength field should take priority over legacy length');
    });

    test('falls back to legacy length when storyLength is null', () {
      final parable = Parable(
        storyId: 'test_002',
        title: 'Test Story',
        mood: 'joyful',
        length: 15, // Should map to full
        // storyLength is null
        storytellingMode: 'creative',
        kidFriendly: false,
      );

      expect(parable.lengthBucket, StoryLengthBucket.full,
          reason:
              'Should fall back to minute-based mapping when storyLength is null');
    });

    test('JSON serialization includes storyLength', () {
      final parable = Parable(
        storyId: 'test_003',
        title: 'Test Story',
        mood: 'joyful',
        length: 5,
        storyLength: 'full',
        storytellingMode: 'creative',
        kidFriendly: false,
      );

      final json = parable.toJson();
      expect(json['storyLength'], 'full');
    });

    test('JSON deserialization reads storyLength', () {
      final json = {
        'storyId': 'test_004',
        'title': 'Test Story',
        'mood': 'joyful',
        'length': 5,
        'storyLength': 'long',
        'storytellingMode': 'creative',
        'kidFriendly': false,
      };

      final parable = Parable.fromJson(json);
      expect(parable.storyLength, 'long');
      expect(parable.lengthBucket, StoryLengthBucket.long);
    });

    test('copyWith preserves storyLength', () {
      final original = Parable(
        storyId: 'test_005',
        title: 'Original Title',
        mood: 'joyful',
        length: 5,
        storyLength: 'full',
        storytellingMode: 'creative',
        kidFriendly: false,
      );

      final copied = original.copyWith(title: 'New Title');

      expect(copied.storyLength, 'full',
          reason: 'copyWith should preserve storyLength');
      expect(copied.lengthBucket, StoryLengthBucket.full);
    });

    test('toJson generates storyLength from bucket if field is null', () {
      final parable = Parable(
        storyId: 'test_006',
        title: 'Test Story',
        mood: 'joyful',
        length: 20, // Maps to long
        // storyLength is null
        storytellingMode: 'creative',
        kidFriendly: false,
      );

      final json = parable.toJson();
      expect(json['storyLength'], 'long',
          reason:
              'toJson should compute storyLength from lengthBucket if null');
    });
  });

  group('CRITICAL: storyLength field values', () {
    test('only valid values are: short, full, long', () {
      final validValues = ['short', 'full', 'long'];

      for (final value in validValues) {
        final bucket = StoryLengthBucket.fromJson(value);
        expect(bucket.toJson(), value,
            reason: '$value should round-trip correctly');
      }
    });

    test('enum has exactly 3 values', () {
      expect(StoryLengthBucket.values.length, 3);
    });
  });
}
