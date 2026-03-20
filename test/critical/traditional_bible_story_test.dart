// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/models/parable.dart';
import '../helpers/scripture_anchor_registry_loader.dart';

/// Critical tests for Traditional Mode = Real Bible Story invariant (ADR-010 + ADR-022)
///
/// These tests enforce:
/// 1. Traditional stories MUST have bibleStoryKey
/// 2. Traditional stories MUST have bibleSourceRef
/// 3. Creative stories MUST NOT have bibleStoryKey
/// 4. Every Traditional story's bibleStoryKey is registered in the Scripture Anchor Registry
/// 5. Every Traditional story's mood matches its anchor's moodTags
///
/// See: docs/INVARIANTS.md - Traditional Mode = Real Bible Story Invariant
/// See: docs/DECISIONS.md ADR-022 - Scripture Anchor Registry
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Parable> allParables;
  late List<Parable> traditionalParables;
  late List<Parable> creativeParables;
  late ScriptureAnchorRegistry registry;

  setUpAll(() async {
    registry = await ScriptureAnchorRegistry.load();

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
    print('Registry: ${registry.anchors.length} anchors');
  });

  group('Traditional Bible Story Invariant (ADR-010 + ADR-022)', () {
    test('CRITICAL: Traditional stories MUST have bibleStoryKey', () {
      final missingKey =
          traditionalParables.where((p) => !p.hasBibleStoryKey).toList();

      if (missingKey.isNotEmpty) {
        print('\n\u{1f6a8} VIOLATION: Traditional stories missing bibleStoryKey:');
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
        print('\n\u{1f6a8} VIOLATION: Traditional stories missing bibleSourceRef:');
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
            '\n\u{1f6a8} VIOLATION: Creative stories should not have bibleStoryKey:');
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
        'CRITICAL: Every Traditional story bibleStoryKey is registered (ADR-022)',
        () {
      final unregistered = <String>[];

      for (final p in traditionalParables) {
        if (p.hasBibleStoryKey) {
          final entry = registry.getByStoryKey(p.bibleStoryKey!);
          if (entry == null) {
            unregistered.add(
                '${p.storyId}: bibleStoryKey="${p.bibleStoryKey}"');
          }
        }
      }

      if (unregistered.isNotEmpty) {
        print(
            '\n\u{1f6a8} VIOLATION: Traditional stories with unregistered bibleStoryKey:');
        for (final u in unregistered) {
          print('  - $u');
        }
      }

      expect(
        unregistered,
        isEmpty,
        reason:
            'Every Traditional story bibleStoryKey must exist in the '
            'Scripture Anchor Registry (ADR-022). '
            'Unregistered: $unregistered',
      );
    });

    test(
        'CRITICAL: Every Traditional story mood matches its anchor moodTags',
        () {
      final mismatches = <String>[];

      for (final p in traditionalParables) {
        if (p.hasBibleStoryKey) {
          final entry = registry.getByStoryKey(p.bibleStoryKey!);
          if (entry != null && !entry.moodTags.contains(p.mood)) {
            mismatches.add(
                '${p.storyId}: mood="${p.mood}" not in '
                'anchor "${entry.bibleStoryKey}" moodTags=${entry.moodTags}');
          }
        }
      }

      if (mismatches.isNotEmpty) {
        print('\n\u{1f6a8} VIOLATION: Manifest mood not in anchor moodTags:');
        for (final m in mismatches) {
          print('  - $m');
        }
      }

      expect(
        mismatches,
        isEmpty,
        reason:
            'Each Traditional story mood must appear in its anchor moodTags (ADR-022). '
            'Mismatches: $mismatches',
      );
    });

    test('INFO: List all Traditional stories with their bibleStoryKey mapping',
        () {
      print('\n\u{1f4da} Traditional stories by mood and bibleStoryKey:\n');

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

      expect(true, isTrue);
    });
  });

  group('bibleStoryKey Format Validation', () {
    test('bibleStoryKey should be snake_case format', () {
      final invalidFormat =
          traditionalParables.where((p) => p.hasBibleStoryKey).where((p) {
        final key = p.bibleStoryKey!;
        final snakeCaseRegex = RegExp(r'^[a-z][a-z0-9_]*$');
        return !snakeCaseRegex.hasMatch(key);
      }).toList();

      if (invalidFormat.isNotEmpty) {
        print('\n\u{26a0}\u{fe0f} bibleStoryKey format violations (should be snake_case):');
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
        print('\n\u{26a0}\u{fe0f} Traditional stories missing narratorVoiceKey:');
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
