// CRITICAL: Manifest storyLength Validation Test
// This test ensures the manifest.json has valid storyLength for all entries.
//
// LOCKED SPEC requirements:
// - Every manifest entry MUST have storyLength field
// - storyLength MUST be one of: "short", "full", "long"
//
// DO NOT WEAKEN THESE TESTS.

@Tags(['critical'])
library;

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/story_length_bucket.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CRITICAL: Manifest storyLength validation', () {
    late List<Map<String, dynamic>> parables;

    setUpAll(() async {
      final jsonContent =
          await rootBundle.loadString('assets/stories/manifest.json');
      final manifestData = jsonDecode(jsonContent) as Map<String, dynamic>;
      parables = (manifestData['parables'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    });

    test('manifest has parables', () {
      expect(parables.isNotEmpty, true,
          reason: 'Manifest should have at least one parable');
    });

    test('every entry has storyLength field', () {
      final missingStoryLength = <String>[];

      for (final parable in parables) {
        final storyId = parable['storyId'] as String;
        final storyLength = parable['storyLength'];

        if (storyLength == null) {
          missingStoryLength.add(storyId);
        }
      }

      expect(missingStoryLength, isEmpty,
          reason: 'The following entries are MISSING storyLength field '
              '(REQUIRED by LOCKED SPEC):\n'
              '${missingStoryLength.join('\n')}');
    });

    test('storyLength values are valid (short, full, or long)', () {
      final invalidEntries = <String>[];
      const validValues = {'short', 'full', 'long'};

      for (final parable in parables) {
        final storyId = parable['storyId'] as String;
        final storyLength = parable['storyLength'] as String?;

        if (storyLength != null && !validValues.contains(storyLength)) {
          invalidEntries.add('$storyId: "$storyLength"');
        }
      }

      expect(invalidEntries, isEmpty,
          reason: 'The following entries have INVALID storyLength values '
              '(must be: short, full, or long):\n'
              '${invalidEntries.join('\n')}');
    });

    test('storyLength can be parsed by StoryLengthBucket.fromJson', () {
      for (final parable in parables) {
        final storyId = parable['storyId'] as String;
        final storyLength = parable['storyLength'] as String?;

        if (storyLength != null) {
          final bucket = StoryLengthBucket.fromJson(storyLength);
          expect(bucket.toJson(), storyLength,
              reason: '$storyId: storyLength should round-trip correctly');
        }
      }
    });
  });

  group('Manifest storyLength distribution', () {
    late List<Map<String, dynamic>> parables;

    setUpAll(() async {
      final jsonContent =
          await rootBundle.loadString('assets/stories/manifest.json');
      final manifestData = jsonDecode(jsonContent) as Map<String, dynamic>;
      parables = (manifestData['parables'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    });

    test('manifest has stories of each length type', () {
      final hasShort = parables.any((p) => p['storyLength'] == 'short');
      final hasFull = parables.any((p) => p['storyLength'] == 'full');
      final hasLong = parables.any((p) => p['storyLength'] == 'long');

      // At least one of each type should exist for a good story library
      // This is a soft check - may not have all types during development
      if (!hasShort || !hasFull || !hasLong) {
        // Just print a warning, don't fail
        final missing = <String>[];
        if (!hasShort) missing.add('short');
        if (!hasFull) missing.add('full');
        if (!hasLong) missing.add('long');
        // ignore: avoid_print
        print('WARNING: Manifest is missing stories with storyLength: '
            '${missing.join(", ")}');
      }
    });
  });
}
