// Unit tests for Kid Bedtime Validator
// Tests word count validation for different story lengths
// See docs/prompts/kid_bedtime_contract.txt for specification
//
// LOCKED SPEC Word Count Ranges:
// - short: 250-600 words
// - full: 601-1200 words
// - long: 1201-2000 words
//
// Legacy minute mappings (for backwards compatibility):
// - 3 min: 270-400 (special case, not mapped to bucket)
// - 5 min, 10 min → short bucket (250-600)
// - 15 min → full bucket (601-1200)
// - 20 min → long bucket (1201-2000)

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/safety/kid_bedtime_validator.dart';
import 'package:bible_pal/core/story_length_bucket.dart';

void main() {
  group('KidBedtimeValidator', () {
    group('LOCKED SPEC: Bucket-Based Word Count Ranges', () {
      test('short bucket requires 250-600 words', () {
        final range = getWordCountRangeForBucket(StoryLengthBucket.short);
        expect(range.$1, 250); // min
        expect(range.$2, 600); // max
      });

      test('full bucket requires 601-1200 words', () {
        final range = getWordCountRangeForBucket(StoryLengthBucket.full);
        expect(range.$1, 601); // min
        expect(range.$2, 1200); // max
      });

      test('long bucket requires 1201-2000 words', () {
        final range = getWordCountRangeForBucket(StoryLengthBucket.long);
        expect(range.$1, 1201); // min
        expect(range.$2, 2000); // max
      });

      test('all three buckets have word count ranges', () {
        // Word count ranges are now derived from StoryLengthBucket.wordCountRange
        expect(StoryLengthBucket.values.length, 3);
        expect(getWordCountRangeForBucket(StoryLengthBucket.short), isNotNull);
        expect(getWordCountRangeForBucket(StoryLengthBucket.full), isNotNull);
        expect(getWordCountRangeForBucket(StoryLengthBucket.long), isNotNull);
      });
    });

    group('Legacy Minute-Based Word Count Ranges', () {
      test('3-minute story requires 270-400 words (special case)', () {
        final range = getWordCountRange(3);
        expect(range, isNotNull);
        expect(range!.$1, 270); // min
        expect(range.$2, 400); // max
      });

      test('5-minute story maps to short bucket (250-600)', () {
        final range = getWordCountRange(5);
        expect(range, isNotNull);
        expect(range!.$1, 250); // min (LOCKED SPEC short bucket)
        expect(range.$2, 600); // max
      });

      test('10-minute story maps to short bucket (250-600)', () {
        final range = getWordCountRange(10);
        expect(range, isNotNull);
        expect(range!.$1, 250); // min
        expect(range.$2, 600); // max
      });

      test('15-minute story maps to full bucket (601-1200)', () {
        final range = getWordCountRange(15);
        expect(range, isNotNull);
        expect(range!.$1, 601); // min
        expect(range.$2, 1200); // max
      });

      test('20-minute story maps to long bucket (1201-2000)', () {
        final range = getWordCountRange(20);
        expect(range, isNotNull);
        expect(range!.$1, 1201); // min
        expect(range.$2, 2000); // max
      });

      test('unknown minute values map to buckets via lengthMinutesToBucket',
          () {
        // All minute values now map to bucket ranges via lengthMinutesToBucket
        // 7 min → short (because <= 10)
        expect(getWordCountRange(7), (250, 600));
        // 12 min → full (because > 10 and <= 15)
        expect(getWordCountRange(12), (601, 1200));
        // 25 min → long (because > 15)
        expect(getWordCountRange(25), (1201, 2000));
      });
    });

    group('Bucket-Based Validation (PRIMARY)', () {
      late KidBedtimeValidator validator;

      setUp(() {
        validator = KidBedtimeValidator.withPatterns(['roar', 'terror']);
      });

      test('short bucket: 200-word story FAILS (below 250 minimum)', () {
        validator.targetLengthBucket = StoryLengthBucket.short;

        final shortStory = _generateStoryWithWordCount(200);
        final result = validator.validate(shortStory);

        expect(result.isValid, false);
        expect(
          result.structureViolations.any((v) => v.contains('too short')),
          true,
          reason: 'Should detect story is too short for short bucket',
        );
      });

      test('short bucket: 400-word story PASSES (within 250-600)', () {
        validator.targetLengthBucket = StoryLengthBucket.short;

        final validStory = _generateStoryWithWordCount(400);
        final result = validator.validate(validStory);

        expect(
          result.structureViolations.any((v) => v.contains('too short')),
          false,
          reason: 'Should not flag 400-word story as too short',
        );
        expect(
          result.structureViolations.any((v) => v.contains('too long')),
          false,
          reason: 'Should not flag 400-word story as too long',
        );
      });

      test('short bucket: 650-word story FAILS (above 600 maximum)', () {
        validator.targetLengthBucket = StoryLengthBucket.short;

        final longStory = _generateStoryWithWordCount(650);
        final result = validator.validate(longStory);

        expect(
          result.structureViolations.any((v) => v.contains('too long')),
          true,
          reason: 'Should detect story is too long for short bucket',
        );
      });

      test('full bucket: 800-word story PASSES (within 601-1200)', () {
        validator.targetLengthBucket = StoryLengthBucket.full;

        final validStory = _generateStoryWithWordCount(800);
        final result = validator.validate(validStory);

        expect(
          result.structureViolations.any((v) => v.contains('too short')),
          false,
        );
        expect(
          result.structureViolations.any((v) => v.contains('too long')),
          false,
        );
      });

      test('long bucket: 1500-word story PASSES (within 1201-2000)', () {
        validator.targetLengthBucket = StoryLengthBucket.long;

        final validStory = _generateStoryWithWordCount(1500);
        final result = validator.validate(validStory);

        expect(
          result.structureViolations.any((v) => v.contains('too short')),
          false,
        );
        expect(
          result.structureViolations.any((v) => v.contains('too long')),
          false,
        );
      });
    });

    group('Legacy Minute-Based Validation (FALLBACK)', () {
      late KidBedtimeValidator validator;

      setUp(() {
        validator = KidBedtimeValidator.withPatterns(['roar', 'terror']);
      });

      test('5-minute target: 200-word story FAILS (below 250)', () {
        validator.targetLengthMinutes = 5;

        final shortStory = _generateStoryWithWordCount(200);
        final result = validator.validate(shortStory);

        expect(result.isValid, false);
        expect(
          result.structureViolations.any((v) => v.contains('too short')),
          true,
        );
      });

      test('5-minute target: 400-word story PASSES (within 250-600)', () {
        validator.targetLengthMinutes = 5;

        final validStory = _generateStoryWithWordCount(400);
        final result = validator.validate(validStory);

        expect(
          result.structureViolations.any((v) => v.contains('too short')),
          false,
        );
        expect(
          result.structureViolations.any((v) => v.contains('too long')),
          false,
        );
      });

      test('3-minute target: 270-word story PASSES (within 270-400)', () {
        validator.targetLengthMinutes = 3;

        final validStory = _generateStoryWithWordCount(270);
        final result = validator.validate(validStory);

        expect(
          result.structureViolations.any((v) => v.contains('too short')),
          false,
        );
        expect(
          result.structureViolations.any((v) => v.contains('too long')),
          false,
        );
      });

      test('3-minute target: 200-word story FAILS (below 270)', () {
        validator.targetLengthMinutes = 3;

        final shortStory = _generateStoryWithWordCount(200);
        final result = validator.validate(shortStory);

        expect(
          result.structureViolations.any((v) => v.contains('too short')),
          true,
        );
      });

      test('no target length uses short bucket minimum (250 words)', () {
        validator.targetLengthMinutes = null;
        validator.targetLengthBucket = null;

        final shortStory = _generateStoryWithWordCount(150);
        final result = validator.validate(shortStory);

        expect(
          result.structureViolations.any((v) => v.contains('too short')),
          true,
        );
        // Default minimum is derived from StoryLengthBucket.short.wordCountRange
        expect(
          result.structureViolations.any((v) => v.contains('minimum 250')),
          true,
        );
      });

      test('unknown minute values map to buckets via lengthMinutesToBucket',
          () {
        validator.targetLengthMinutes =
            7; // Maps to short bucket via lengthMinutesToBucket

        final shortStory = _generateStoryWithWordCount(150);
        final result = validator.validate(shortStory);

        // 7 min maps to short bucket (250-600 words)
        expect(
          result.structureViolations.any((v) => v.contains('need 250-600')),
          true,
        );
      });
    });

    group('Bucket Takes Priority Over Minutes', () {
      test('bucket is used when both bucket and minutes are set', () {
        final validator = KidBedtimeValidator.withPatterns([]);
        validator.targetLengthBucket = StoryLengthBucket.short;
        validator.targetLengthMinutes = 20; // Would be long bucket

        // 500 words is valid for short but invalid for long
        final story = _generateStoryWithWordCount(500);
        final result = validator.validate(story);

        expect(
          result.structureViolations.any((v) => v.contains('too short')),
          false,
          reason: 'Should use short bucket (250-600), not long bucket',
        );
      });
    });

    group('Repair Instructions', () {
      test('bucket-based violation generates helpful repair instruction', () {
        final validator = KidBedtimeValidator.withPatterns([]);
        validator.targetLengthBucket = StoryLengthBucket.short;

        final shortStory = _generateStoryWithWordCount(150);
        final result = validator.validate(shortStory);

        expect(result.isValid, false);
        expect(result.repairInstruction, contains('STRUCTURE PROBLEMS'));
        expect(result.repairInstruction, contains('too short'));
        expect(result.repairInstruction, contains('Short Story'));
      });
    });

    group('Harness Regeneration Loop', () {
      test('harness retries when word count too low', () {
        final validator = KidBedtimeValidator.withPatterns([]);
        validator.targetLengthBucket = StoryLengthBucket.short;

        final harness = KidBedtimeHarness(
          validator: validator,
          maxAttempts: 3,
        );

        var attemptCount = 0;
        final result = harness.run(
          storyText: _generateStoryWithWordCount(150), // Too short
          regenerate: (repairInstruction) {
            attemptCount++;
            // Simulate regeneration that eventually succeeds
            if (attemptCount >= 2) {
              return _generateStoryWithWordCount(400); // Valid length
            }
            return _generateStoryWithWordCount(200); // Still too short
          },
        );

        expect(result.isKidSafe, true);
        expect(result.attemptCount, 3); // Initial + 2 retries
        expect(attemptCount, 2); // regenerate called twice
      });

      test('harness gives up after max attempts', () {
        final validator = KidBedtimeValidator.withPatterns([]);
        validator.targetLengthBucket = StoryLengthBucket.short;

        final harness = KidBedtimeHarness(
          validator: validator,
          maxAttempts: 3,
        );

        final result = harness.run(
          storyText: _generateStoryWithWordCount(150),
          regenerate: (_) =>
              _generateStoryWithWordCount(150), // Always too short
        );

        expect(result.isKidSafe, false);
        expect(result.attemptCount, 3);
        expect(result.finalViolations, isNotEmpty);
      });
    });
  });
}

/// Generate a story with approximately the target word count.
/// The story has proper structure (paragraphs) and gentle ending.
String _generateStoryWithWordCount(int targetWords) {
  final buffer = StringBuffer();

  // Opening paragraph (~25 words)
  buffer.writeln('## A Peaceful Story');
  buffer.writeln();
  buffer.writeln(
    'Once upon a time in a quiet village, there lived a kind shepherd. '
    'The gentle breeze carried the scent of wildflowers across the meadow.',
  );
  buffer.writeln();

  // Closing paragraph (~55 words)
  const closingParagraph =
      'As the stars began to twinkle in the evening sky, the shepherd '
      'led the sheep back to their safe pen. The moon cast a soft glow '
      'over the peaceful valley. Feeling warm and safe, everyone closed '
      'their eyes and drifted into peaceful sleep. Goodnight.';

  // Each filler paragraph is ~35 words
  const fillerParagraph =
      'The shepherd watched over the sheep with care and love. '
      'Each day brought new blessings and peaceful moments. '
      'The sun warmed the hillside as the flock grazed quietly. '
      'Birds sang sweetly in the trees nearby.';

  // Calculate how many filler paragraphs we need
  // Opening: ~25 words, Closing: ~55 words, Filler: ~35 words each
  const openingWords = 25;
  const closingWords = 55;
  const fillerWords = 35;

  final neededFillerWords = targetWords - openingWords - closingWords;
  final paragraphsNeeded =
      neededFillerWords > 0 ? (neededFillerWords / fillerWords).ceil() : 0;

  for (var i = 0; i < paragraphsNeeded; i++) {
    buffer.writeln(fillerParagraph);
    buffer.writeln();
  }

  // Add gentle closing
  buffer.writeln(closingParagraph);

  return buffer.toString();
}
