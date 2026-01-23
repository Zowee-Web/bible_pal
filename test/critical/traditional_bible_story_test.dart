// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/models/parable.dart';

/// Critical tests for Traditional Mode = Real Bible Story invariant (ADR-010)
///
/// These tests enforce:
/// 1. Traditional stories MUST have bibleStoryKey
/// 2. Traditional stories MUST have bibleSourceRef
/// 3. Each mood has exactly ONE bibleStoryKey for Traditional stories
/// 4. Creative stories MUST NOT have bibleStoryKey
///
/// See: docs/INVARIANTS.md - Traditional Mode = Real Bible Story Invariant
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Parable> allParables;
  late List<Parable> traditionalParables;
  late List<Parable> creativeParables;

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

    creativeParables =
        allParables.where((p) => p.storytellingMode == 'creative').toList();

    print('Loaded ${allParables.length} total parables');
    print('  - ${traditionalParables.length} Traditional');
    print('  - ${creativeParables.length} Creative');
  });

  group('Traditional Bible Story Invariant (ADR-010)', () {
    test('CRITICAL: Traditional stories MUST have bibleStoryKey', () {
      final missingKey =
          traditionalParables.where((p) => !p.hasBibleStoryKey).toList();

      if (missingKey.isNotEmpty) {
        print('\n🚨 VIOLATION: Traditional stories missing bibleStoryKey:');
        for (final p in missingKey) {
          print('  - ${p.storyId} (${p.title})');
        }
      }

      expect(
        missingKey,
        isEmpty,
        reason: 'Traditional stories must have bibleStoryKey (ADR-010). '
            'Found ${missingKey.length} violations.',
      );
    });

    test('CRITICAL: Traditional stories MUST have bibleSourceRef', () {
      final missingRef =
          traditionalParables.where((p) => !p.hasBibleSourceRef).toList();

      if (missingRef.isNotEmpty) {
        print('\n🚨 VIOLATION: Traditional stories missing bibleSourceRef:');
        for (final p in missingRef) {
          print('  - ${p.storyId} (${p.title})');
        }
      }

      expect(
        missingRef,
        isEmpty,
        reason: 'Traditional stories must have bibleSourceRef (Contracts v2). '
            'Found ${missingRef.length} violations.',
      );
    });

    test('CRITICAL: Creative stories MUST NOT have bibleStoryKey', () {
      final hasKey = creativeParables.where((p) => p.hasBibleStoryKey).toList();

      if (hasKey.isNotEmpty) {
        print(
            '\n🚨 VIOLATION: Creative stories should not have bibleStoryKey:');
        for (final p in hasKey) {
          print('  - ${p.storyId} has bibleStoryKey: ${p.bibleStoryKey}');
        }
      }

      expect(
        hasKey,
        isEmpty,
        reason: 'Creative stories must not have bibleStoryKey. '
            'Found ${hasKey.length} violations.',
      );
    });

    test(
        'CRITICAL: Each mood has exactly ONE bibleStoryKey for Traditional (kid mode)',
        () {
      // Group Traditional kid stories by mood
      final kidTraditional =
          traditionalParables.where((p) => p.kidFriendly).toList();

      final moodToKeys = <String, Set<String>>{};

      for (final p in kidTraditional) {
        if (p.hasBibleStoryKey) {
          moodToKeys.putIfAbsent(p.mood, () => <String>{});
          moodToKeys[p.mood]!.add(p.bibleStoryKey!);
        }
      }

      final violations = <String>[];
      for (final entry in moodToKeys.entries) {
        if (entry.value.length > 1) {
          violations.add(
            'Mood "${entry.key}" has multiple bibleStoryKeys: ${entry.value.join(", ")}',
          );
        }
      }

      if (violations.isNotEmpty) {
        print('\n🚨 VIOLATION: Multiple bibleStoryKeys per mood (kid):');
        for (final v in violations) {
          print('  - $v');
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Each mood must map to exactly ONE bibleStoryKey for Traditional kid stories (ADR-010). '
            'Found ${violations.length} violations.',
      );
    });

    test(
        'CRITICAL: Each mood has exactly ONE bibleStoryKey for Traditional (adult mode)',
        () {
      // Group Traditional adult stories by mood
      final adultTraditional =
          traditionalParables.where((p) => !p.kidFriendly).toList();

      final moodToKeys = <String, Set<String>>{};

      for (final p in adultTraditional) {
        if (p.hasBibleStoryKey) {
          moodToKeys.putIfAbsent(p.mood, () => <String>{});
          moodToKeys[p.mood]!.add(p.bibleStoryKey!);
        }
      }

      final violations = <String>[];
      for (final entry in moodToKeys.entries) {
        if (entry.value.length > 1) {
          violations.add(
            'Mood "${entry.key}" has multiple bibleStoryKeys: ${entry.value.join(", ")}',
          );
        }
      }

      if (violations.isNotEmpty) {
        print('\n🚨 VIOLATION: Multiple bibleStoryKeys per mood (adult):');
        for (final v in violations) {
          print('  - $v');
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Each mood must map to exactly ONE bibleStoryKey for Traditional adult stories (ADR-010). '
            'Found ${violations.length} violations.',
      );
    });

    test('INFO: List all Traditional stories with their bibleStoryKey mapping',
        () {
      print('\n📚 Traditional stories by mood and bibleStoryKey:\n');

      // Group by mood, then by bibleStoryKey
      final moodGroups = <String, Map<String, List<Parable>>>{};

      for (final p in traditionalParables) {
        moodGroups.putIfAbsent(p.mood, () => {});
        final key = p.bibleStoryKey ?? '(missing)';
        moodGroups[p.mood]!.putIfAbsent(key, () => []);
        moodGroups[p.mood]![key]!.add(p);
      }

      for (final mood in moodGroups.keys.toList()..sort()) {
        print('Mood: $mood');
        for (final key in moodGroups[mood]!.keys) {
          final stories = moodGroups[mood]![key]!;
          print('  bibleStoryKey: $key');
          for (final p in stories) {
            final audience = p.kidFriendly ? 'kid' : 'adult';
            print('    - ${p.storyId} ($audience, ${p.lengthBucket.name})');
          }
        }
        print('');
      }

      // This test always passes - it's just for documentation
      expect(true, isTrue);
    });
  });

  group('bibleStoryKey Format Validation', () {
    test('bibleStoryKey should be snake_case format', () {
      final invalidFormat =
          traditionalParables.where((p) => p.hasBibleStoryKey).where((p) {
        final key = p.bibleStoryKey!;
        // Check for snake_case: lowercase letters, numbers, underscores only
        final snakeCaseRegex = RegExp(r'^[a-z][a-z0-9_]*$');
        return !snakeCaseRegex.hasMatch(key);
      }).toList();

      if (invalidFormat.isNotEmpty) {
        print('\n⚠️ bibleStoryKey format violations (should be snake_case):');
        for (final p in invalidFormat) {
          print('  - ${p.storyId}: "${p.bibleStoryKey}"');
        }
      }

      expect(
        invalidFormat,
        isEmpty,
        reason:
            'bibleStoryKey should be snake_case format (e.g., "lost_sheep", "david_and_goliath")',
      );
    });
  });

  group('Traditional Story Completeness', () {
    test('Traditional stories should have narratorVoiceKey', () {
      final missingVoice = traditionalParables
          .where(
              (p) => p.narratorVoiceKey == null || p.narratorVoiceKey!.isEmpty)
          .toList();

      if (missingVoice.isNotEmpty) {
        print('\n⚠️ Traditional stories missing narratorVoiceKey:');
        for (final p in missingVoice) {
          print('  - ${p.storyId}');
        }
      }

      expect(
        missingVoice,
        isEmpty,
        reason:
            'Traditional stories should have narratorVoiceKey for reflection voice matching',
      );
    });
  });
}
