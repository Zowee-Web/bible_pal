// Unit tests for Kid Bedtime Validator
// Tests word count validation for different story lengths
// See docs/prompts/kid_bedtime_contract.txt for specification

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/safety/kid_bedtime_validator.dart';

void main() {
  group('KidBedtimeValidator', () {
    group('Word Count Range Constants', () {
      test('3-minute story requires 270-400 words', () {
        final range = getWordCountRange(3);
        expect(range, isNotNull);
        expect(range!.$1, 270); // min
        expect(range.$2, 400); // max
      });

      test('5-minute story requires 540-720 words', () {
        final range = getWordCountRange(5);
        expect(range, isNotNull);
        expect(range!.$1, 540); // min
        expect(range.$2, 720); // max
      });

      test('10-minute story requires 900-1200 words', () {
        final range = getWordCountRange(10);
        expect(range, isNotNull);
        expect(range!.$1, 900); // min
        expect(range.$2, 1200); // max
      });

      test('15-minute story requires 1350-1800 words', () {
        final range = getWordCountRange(15);
        expect(range, isNotNull);
        expect(range!.$1, 1350); // min
        expect(range.$2, 1800); // max
      });

      test('20-minute story requires 1800-2400 words', () {
        final range = getWordCountRange(20);
        expect(range, isNotNull);
        expect(range!.$1, 1800); // min
        expect(range.$2, 2400); // max
      });

      test('unsupported length returns null', () {
        expect(getWordCountRange(7), isNull);
        expect(getWordCountRange(12), isNull);
        expect(getWordCountRange(25), isNull);
      });
    });

    group('Word Count Validation', () {
      late KidBedtimeValidator validator;

      setUp(() {
        // Create validator with minimal forbidden patterns for testing
        validator = KidBedtimeValidator.withPatterns(['roar', 'terror']);
      });

      test('CRITICAL: 353-word story FAILS for 5-minute target', () {
        validator.targetLengthMinutes = 5;

        // Generate a ~353 word story (the actual sample that failed)
        final shortStory = _generateStoryWithWordCount(353);

        final result = validator.validate(shortStory);

        expect(result.isValid, false);
        expect(result.structureViolations, isNotEmpty);
        expect(
          result.structureViolations.any((v) => v.contains('too short')),
          true,
          reason: 'Should detect story is too short for 5-minute target',
        );
      });

      test('CRITICAL: 600-word story PASSES for 5-minute target', () {
        validator.targetLengthMinutes = 5;

        // Generate a ~600 word story (within 540-720 range)
        final validStory = _generateStoryWithWordCount(600);

        final result = validator.validate(validStory);

        // Check no word-count violations (may have other violations like missing bedtime signals)
        expect(
          result.structureViolations.any((v) => v.contains('too short')),
          false,
          reason: 'Should not flag 600-word story as too short',
        );
        expect(
          result.structureViolations.any((v) => v.contains('too long')),
          false,
          reason: 'Should not flag 600-word story as too long',
        );
      });

      test('750-word story FAILS for 5-minute target (too long)', () {
        validator.targetLengthMinutes = 5;

        final longStory = _generateStoryWithWordCount(750);

        final result = validator.validate(longStory);

        expect(
          result.structureViolations.any((v) => v.contains('too long')),
          true,
          reason: 'Should detect story is too long for 5-minute target',
        );
      });

      test('270-word story PASSES for 3-minute target', () {
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

      test('200-word story FAILS for 3-minute target', () {
        validator.targetLengthMinutes = 3;

        final shortStory = _generateStoryWithWordCount(200);

        final result = validator.validate(shortStory);

        expect(
          result.structureViolations.any((v) => v.contains('too short')),
          true,
        );
      });

      test('no target length uses 200-word minimum', () {
        validator.targetLengthMinutes = null;

        final shortStory = _generateStoryWithWordCount(150);

        final result = validator.validate(shortStory);

        expect(
          result.structureViolations.any((v) => v.contains('too short')),
          true,
        );
        expect(
          result.structureViolations.any((v) => v.contains('minimum 200')),
          true,
        );
      });

      test('unknown length bucket uses 200-word minimum', () {
        validator.targetLengthMinutes = 7; // Not a defined bucket

        final shortStory = _generateStoryWithWordCount(150);

        final result = validator.validate(shortStory);

        expect(
          result.structureViolations.any((v) => v.contains('minimum 200')),
          true,
        );
      });
    });

    group('Repair Instructions', () {
      test('word count violation generates helpful repair instruction', () {
        final validator = KidBedtimeValidator.withPatterns([]);
        validator.targetLengthMinutes = 5;

        final shortStory = _generateStoryWithWordCount(350);
        final result = validator.validate(shortStory);

        expect(result.isValid, false);
        expect(result.repairInstruction, contains('STRUCTURE PROBLEMS'));
        expect(result.repairInstruction, contains('too short'));
        expect(result.repairInstruction, contains('540-720'));
      });
    });

    group('Harness Regeneration Loop', () {
      test('harness retries when word count too low', () {
        final validator = KidBedtimeValidator.withPatterns([]);
        validator.targetLengthMinutes = 5;

        final harness = KidBedtimeHarness(
          validator: validator,
          maxAttempts: 3,
        );

        var attemptCount = 0;
        final result = harness.run(
          storyText: _generateStoryWithWordCount(350), // Too short
          regenerate: (repairInstruction) {
            attemptCount++;
            // Simulate regeneration that eventually succeeds
            if (attemptCount >= 2) {
              return _generateStoryWithWordCount(600); // Valid length
            }
            return _generateStoryWithWordCount(400); // Still too short
          },
        );

        expect(result.isKidSafe, true);
        expect(result.attemptCount, 3); // Initial + 2 retries
        expect(attemptCount, 2); // regenerate called twice
      });

      test('harness gives up after max attempts', () {
        final validator = KidBedtimeValidator.withPatterns([]);
        validator.targetLengthMinutes = 5;

        final harness = KidBedtimeHarness(
          validator: validator,
          maxAttempts: 3,
        );

        final result = harness.run(
          storyText: _generateStoryWithWordCount(350),
          regenerate: (_) => _generateStoryWithWordCount(350), // Always too short
        );

        expect(result.isKidSafe, false);
        expect(result.attemptCount, 3);
        expect(result.finalViolations, isNotEmpty);
      });
    });
  });
}

/// Generate a story with approximately the target word count.
/// The story has proper structure (paragraphs) and bedtime signals.
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

  // Add bedtime closing with sleep signals
  buffer.writeln(closingParagraph);

  return buffer.toString();
}
