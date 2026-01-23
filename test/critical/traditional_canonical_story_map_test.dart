// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/traditional_canonical_story_map.dart';
import 'package:bible_pal/models/parable.dart';

/// CRITICAL drift-prevention tests for Traditional Canonical Story Map
///
/// These tests enforce that the manifest.json stays aligned with the
/// canonical mapping in kTraditionalCanonicalStoryByMood.
///
/// If these tests fail, it means:
/// 1. A Traditional story was added with a bibleStoryKey that doesn't match
///    the canonical map, OR
/// 2. A new mood was added to Traditional without updating the canonical map, OR
/// 3. The canonical map contains a mood that has no Traditional stories.
///
/// See: lib/core/traditional_canonical_story_map.dart
/// See: docs/DECISIONS.md ADR-010
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Parable> allParables;
  late List<Parable> traditionalParables;
  late Map<String, Set<String>> manifestMoodToKeys;

  setUpAll(() async {
    // Load manifest from assets
    final jsonContent =
        await rootBundle.loadString('assets/stories/manifest.json');
    final manifestData = jsonDecode(jsonContent) as Map<String, dynamic>;
    final parablesList = manifestData['parables'] as List<dynamic>? ?? [];

    allParables = parablesList
        .map((json) => Parable.fromJson(json as Map<String, dynamic>))
        .toList();

    traditionalParables =
        allParables.where((p) => p.storytellingMode == 'traditional').toList();

    // Build mood -> Set<bibleStoryKey> from manifest
    manifestMoodToKeys = {};
    for (final p in traditionalParables) {
      if (p.hasBibleStoryKey) {
        manifestMoodToKeys.putIfAbsent(p.mood, () => <String>{});
        manifestMoodToKeys[p.mood]!.add(p.bibleStoryKey!);
      }
    }

    print('Loaded ${traditionalParables.length} Traditional parables');
    print(
        'Manifest moods with Traditional stories: ${manifestMoodToKeys.keys}');
    print(
        'Canonical map moods: ${kTraditionalCanonicalStoryByMood.keys.toList()}');
  });

  group('Traditional Canonical Story Map - Drift Prevention', () {
    test(
        'CRITICAL: Canonical map contains all moods from manifest Traditional stories',
        () {
      final manifestMoods = manifestMoodToKeys.keys.toSet();
      final canonicalMoods = kTraditionalCanonicalStoryByMood.keys.toSet();

      final missingFromCanonical = manifestMoods.difference(canonicalMoods);

      if (missingFromCanonical.isNotEmpty) {
        print(
            '\n🚨 DRIFT DETECTED: Moods in manifest but NOT in canonical map:');
        for (final mood in missingFromCanonical) {
          final keys = manifestMoodToKeys[mood]!;
          print('  - $mood -> $keys');
        }
        print('\nFIX: Add these moods to kTraditionalCanonicalStoryByMood in');
        print('     lib/core/traditional_canonical_story_map.dart');
      }

      expect(
        missingFromCanonical,
        isEmpty,
        reason: 'Canonical map must contain all moods that have Traditional '
            'stories in the manifest. Missing: $missingFromCanonical',
      );
    });

    test('CRITICAL: Canonical map contains no extra moods beyond manifest', () {
      final manifestMoods = manifestMoodToKeys.keys.toSet();
      final canonicalMoods = kTraditionalCanonicalStoryByMood.keys.toSet();

      final extraInCanonical = canonicalMoods.difference(manifestMoods);

      if (extraInCanonical.isNotEmpty) {
        print(
            '\n🚨 DRIFT DETECTED: Moods in canonical map but NOT in manifest:');
        for (final mood in extraInCanonical) {
          print('  - $mood -> ${kTraditionalCanonicalStoryByMood[mood]}');
        }
        print('\nFIX: Either:');
        print(
            '  a) Remove these moods from kTraditionalCanonicalStoryByMood, OR');
        print('  b) Add Traditional stories for these moods to manifest.json');
      }

      expect(
        extraInCanonical,
        isEmpty,
        reason: 'Canonical map must not contain moods that have no Traditional '
            'stories in the manifest. Extra: $extraInCanonical',
      );
    });

    test('CRITICAL: Each manifest mood has exactly ONE bibleStoryKey', () {
      final violations = <String>[];

      for (final entry in manifestMoodToKeys.entries) {
        if (entry.value.length != 1) {
          violations.add(
            'Mood "${entry.key}" has ${entry.value.length} bibleStoryKeys: '
            '${entry.value.join(", ")}',
          );
        }
      }

      if (violations.isNotEmpty) {
        print('\n🚨 VIOLATION: Multiple bibleStoryKeys per mood:');
        for (final v in violations) {
          print('  - $v');
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Each mood must have exactly ONE bibleStoryKey for Traditional '
            'stories. Found ${violations.length} violations.',
      );
    });

    test('CRITICAL: Manifest bibleStoryKeys match canonical map exactly', () {
      final mismatches = <String>[];

      for (final entry in manifestMoodToKeys.entries) {
        final mood = entry.key;
        final manifestKeys = entry.value;

        // Get canonical key for this mood
        final canonicalKey = kTraditionalCanonicalStoryByMood[mood];

        if (canonicalKey == null) {
          // Already covered by "contains all moods" test
          continue;
        }

        // Check if manifest has exactly this key
        if (manifestKeys.length == 1) {
          final manifestKey = manifestKeys.first;
          if (manifestKey != canonicalKey) {
            mismatches.add(
              'Mood "$mood": manifest has "$manifestKey", '
              'canonical expects "$canonicalKey"',
            );
          }
        }
      }

      if (mismatches.isNotEmpty) {
        print('\n🚨 DRIFT DETECTED: bibleStoryKey mismatches:');
        for (final m in mismatches) {
          print('  - $m');
        }
        print('\nFIX: Either:');
        print(
            '  a) Update manifest.json to use the canonical bibleStoryKey, OR');
        print(
            '  b) Update kTraditionalCanonicalStoryByMood if canonical changed');
      }

      expect(
        mismatches,
        isEmpty,
        reason: 'Manifest bibleStoryKeys must match canonical map exactly. '
            'Found ${mismatches.length} mismatches.',
      );
    });

    test('INFO: Report canonical mapping alignment', () {
      print('\n📚 Traditional Canonical Story Map Alignment Report:\n');

      print('Canonical Map (kTraditionalCanonicalStoryByMood):');
      for (final entry in kTraditionalCanonicalStoryByMood.entries) {
        print('  ${entry.key} -> ${entry.value}');
      }

      print('\nManifest Traditional Stories by Mood:');
      for (final entry in manifestMoodToKeys.entries) {
        final keys = entry.value.join(', ');
        final status = entry.value.length == 1 &&
                entry.value.first == kTraditionalCanonicalStoryByMood[entry.key]
            ? '✅'
            : '❌';
        print('  $status ${entry.key} -> $keys');
      }

      print('\nMoods WITHOUT Traditional coverage (Creative only):');
      for (final mood in kMoodsWithoutTraditionalCoverage) {
        print('  - $mood');
      }

      // This test always passes - it's just for documentation
      expect(true, isTrue);
    });
  });

  group('Canonical Map Integrity', () {
    test('Canonical map is not empty', () {
      expect(
        kTraditionalCanonicalStoryByMood.isNotEmpty,
        isTrue,
        reason: 'Canonical map must have at least one entry',
      );
    });

    test('All canonical bibleStoryKeys are snake_case', () {
      final invalidFormat = <String>[];
      final snakeCaseRegex = RegExp(r'^[a-z][a-z0-9_]*$');

      for (final entry in kTraditionalCanonicalStoryByMood.entries) {
        if (!snakeCaseRegex.hasMatch(entry.value)) {
          invalidFormat.add('${entry.key}: "${entry.value}"');
        }
      }

      if (invalidFormat.isNotEmpty) {
        print('\n⚠️ Invalid bibleStoryKey format (should be snake_case):');
        for (final f in invalidFormat) {
          print('  - $f');
        }
      }

      expect(
        invalidFormat,
        isEmpty,
        reason: 'All bibleStoryKeys must be snake_case format',
      );
    });

    test('All canonical moods are lowercase with underscores', () {
      final invalidFormat = <String>[];
      final moodRegex = RegExp(r'^[a-z][a-z0-9_]*$');

      for (final mood in kTraditionalCanonicalStoryByMood.keys) {
        if (!moodRegex.hasMatch(mood)) {
          invalidFormat.add(mood);
        }
      }

      expect(
        invalidFormat,
        isEmpty,
        reason: 'All moods must be lowercase with underscores',
      );
    });

    test('kMoodsWithoutTraditionalCoverage does not overlap with canonical map',
        () {
      final overlap = kMoodsWithoutTraditionalCoverage
          .intersection(kTraditionalCanonicalStoryByMood.keys.toSet());

      if (overlap.isNotEmpty) {
        print('\n🚨 Overlap between uncovered moods and canonical map:');
        for (final mood in overlap) {
          print('  - $mood');
        }
        print(
            '\nFIX: Remove these moods from kMoodsWithoutTraditionalCoverage');
      }

      expect(
        overlap,
        isEmpty,
        reason: 'kMoodsWithoutTraditionalCoverage should not overlap with '
            'kTraditionalCanonicalStoryByMood',
      );
    });
  });
}
