import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/features/pals_parables/pals_parables_screen.dart';
import 'package:bible_pal/core/story_length_bucket.dart';

void main() {
  test('PalsParablesScreen class exists and can be instantiated', () {
    // Simple test to verify the screen class is valid
    const screen = PalsParablesScreen();
    expect(screen, isNotNull);
    expect(screen, isA<PalsParablesScreen>());
  });

  group('StoryLengthBucket', () {
    test('UI shows exactly 3 length buckets: Short Story, Full Story, Long Story', () {
      // Verify the enum has exactly 3 values
      expect(StoryLengthBucket.values.length, 3);

      // Verify the exact values
      expect(StoryLengthBucket.values, contains(StoryLengthBucket.short));
      expect(StoryLengthBucket.values, contains(StoryLengthBucket.full));
      expect(StoryLengthBucket.values, contains(StoryLengthBucket.long));
    });

    test('display labels are user-friendly', () {
      expect(StoryLengthBucket.short.displayLabel, 'Short Story');
      expect(StoryLengthBucket.full.displayLabel, 'Full Story');
      expect(StoryLengthBucket.long.displayLabel, 'Long Story');
    });

    test('word count ranges are defined correctly per SPEC.md', () {
      // Short: 300-700 words
      expect(StoryLengthBucket.short.wordCountRange, (300, 700));

      // Full: 900-1400 words
      expect(StoryLengthBucket.full.wordCountRange, (900, 1400));

      // Long: 1700-2600 words
      expect(StoryLengthBucket.long.wordCountRange, (1700, 2600));
    });
  });

  group('Compatibility mapping (minute → bucket)', () {
    test('5 min maps to short', () {
      expect(lengthMinutesToBucket(5), StoryLengthBucket.short);
    });

    test('10 min maps to short', () {
      expect(lengthMinutesToBucket(10), StoryLengthBucket.short);
    });

    test('15 min maps to full', () {
      expect(lengthMinutesToBucket(15), StoryLengthBucket.full);
    });

    test('20 min maps to long', () {
      expect(lengthMinutesToBucket(20), StoryLengthBucket.long);
    });

    test('fallback behavior for unexpected values', () {
      // Values <= 10 → short
      expect(lengthMinutesToBucket(3), StoryLengthBucket.short);
      expect(lengthMinutesToBucket(7), StoryLengthBucket.short);

      // Values 11-15 → full
      expect(lengthMinutesToBucket(12), StoryLengthBucket.full);

      // Values > 15 → long
      expect(lengthMinutesToBucket(25), StoryLengthBucket.long);
      expect(lengthMinutesToBucket(30), StoryLengthBucket.long);
    });
  });

  group('StoryLengthBucket serialization', () {
    test('toJson returns enum name', () {
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
    });
  });
}
