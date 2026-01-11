import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/relatability_tags.dart';

/// Tests to ensure story manifest emotionalTags comply with the allowed vocabulary.
/// These tests fail fast if:
/// - A story has an emotionalTag not in the allowed vocabulary
/// - A story has more than 3 emotionalTags
/// - Less than 50% of stories have at least 1 emotionalTag
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<dynamic> parables;
  late Set<String> allowedTags;

  setUpAll(() async {
    // Load manifest
    final jsonContent = await rootBundle.loadString('assets/stories/manifest.json');
    final manifestData = jsonDecode(jsonContent) as Map<String, dynamic>;
    parables = manifestData['parables'] as List<dynamic>;

    // Get allowed vocabulary from tagOrder
    allowedTags = tagOrder.toSet();
  });

  group('Relatability Tag Vocabulary Compliance', () {
    test('all emotionalTags must be in allowed vocabulary', () {
      final violations = <String>[];

      for (final parable in parables) {
        final storyId = parable['storyId'] as String;
        final tags = (parable['emotionalTags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [];

        for (final tag in tags) {
          if (!allowedTags.contains(tag)) {
            violations.add('$storyId has invalid tag: "$tag"');
          }
        }
      }

      if (violations.isNotEmpty) {
        fail(
          'Found ${violations.length} invalid emotionalTags:\n'
          '${violations.join('\n')}\n\n'
          'Allowed tags: ${allowedTags.join(', ')}',
        );
      }
    });

    test('no story has more than 3 emotionalTags', () {
      final violations = <String>[];

      for (final parable in parables) {
        final storyId = parable['storyId'] as String;
        final tags = (parable['emotionalTags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [];

        if (tags.length > 3) {
          violations.add('$storyId has ${tags.length} tags (max 3): ${tags.join(', ')}');
        }
      }

      if (violations.isNotEmpty) {
        fail(
          'Found ${violations.length} stories with >3 emotionalTags:\n'
          '${violations.join('\n')}',
        );
      }
    });

    test('at least 50% of stories have 1+ emotionalTag', () {
      int storiesWithTags = 0;

      for (final parable in parables) {
        final tags = (parable['emotionalTags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [];

        if (tags.isNotEmpty) {
          storiesWithTags++;
        }
      }

      final totalStories = parables.length;
      final coverage = storiesWithTags / totalStories;

      // Print coverage report
      // ignore: avoid_print
      print('Tag coverage: $storiesWithTags / $totalStories (${(coverage * 100).toStringAsFixed(1)}%)');

      expect(
        coverage,
        greaterThanOrEqualTo(0.5),
        reason: 'At least 50% of stories should have emotionalTags. '
            'Current coverage: ${(coverage * 100).toStringAsFixed(1)}%',
      );
    });

    test('no duplicate tags within a single story', () {
      final violations = <String>[];

      for (final parable in parables) {
        final storyId = parable['storyId'] as String;
        final tags = (parable['emotionalTags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [];

        final uniqueTags = tags.toSet();
        if (uniqueTags.length != tags.length) {
          violations.add('$storyId has duplicate tags: ${tags.join(', ')}');
        }
      }

      if (violations.isNotEmpty) {
        fail(
          'Found ${violations.length} stories with duplicate emotionalTags:\n'
          '${violations.join('\n')}',
        );
      }
    });
  });

  group('Tag Distribution Report', () {
    test('print tag usage statistics', () {
      final tagCounts = <String, int>{};

      for (final parable in parables) {
        final tags = (parable['emotionalTags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [];

        for (final tag in tags) {
          tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
        }
      }

      // Sort by count descending
      final sortedTags = tagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // ignore: avoid_print
      print('\n=== Tag Distribution ===');
      for (final entry in sortedTags) {
        // ignore: avoid_print
        print('${entry.key}: ${entry.value}');
      }

      // Check for unused tags
      final usedTags = tagCounts.keys.toSet();
      final unusedTags = allowedTags.difference(usedTags);
      if (unusedTags.isNotEmpty) {
        // NOTE: This is informational only.
        // Indicates allowed relatability tags that currently have no story coverage.
        // ignore: avoid_print
        print('\nUnused tags: ${unusedTags.join(', ')}');
      }

      // This test always passes; it's just for reporting
      expect(true, isTrue);
    });
  });
}
