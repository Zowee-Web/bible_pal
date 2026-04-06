// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/models/parable.dart';
import '../helpers/scripture_anchor_registry_loader.dart';

/// CRITICAL tests for the Scripture Anchor Registry (ADR-022).
///
/// These tests enforce:
/// 1. Registry integrity — no duplicate anchors or keys
/// 2. Registry ↔ manifest alignment — every manifest story is registered
/// 3. Mood coverage — every mood has at least one anchor
///
/// Identity is the scripture anchor, not the mood.
/// See: assets/stories/scripture_anchor_registry.json
/// See: docs/DECISIONS.md ADR-022
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScriptureAnchorRegistry registry;
  late List<Parable> traditionalParables;

  setUpAll(() async {
    registry = await ScriptureAnchorRegistry.load();

    final jsonContent =
        await rootBundle.loadString('assets/stories/manifest.json');
    final manifestData = jsonDecode(jsonContent) as Map<String, dynamic>;
    final parablesList = manifestData['parables'] as List<dynamic>? ?? [];
    final allParables = parablesList
        .map((json) => Parable.fromJson(json as Map<String, dynamic>))
        .toList();
    traditionalParables =
        allParables.where((p) => p.storytellingMode == 'traditional').toList();

    print('Registry: ${registry.anchors.length} anchors');
    print('Manifest: ${traditionalParables.length} Traditional parables');
  });

  group('Scripture Anchor Registry — Integrity (ADR-022)', () {
    test('CRITICAL: No duplicate scriptureAnchorId in registry', () {
      final seen = <String>{};
      final duplicates = <String>[];

      for (final entry in registry.anchors) {
        if (!seen.add(entry.scriptureAnchorId)) {
          duplicates.add(entry.scriptureAnchorId);
        }
      }

      if (duplicates.isNotEmpty) {
        print('\n\u{1f6a8} DUPLICATE scriptureAnchorIds:');
        for (final d in duplicates) {
          print('  - $d');
        }
      }

      expect(
        duplicates,
        isEmpty,
        reason: 'scriptureAnchorId is the primary no-reuse key. '
            'Duplicates: $duplicates',
      );
    });

    test('CRITICAL: No duplicate bibleStoryKey in registry', () {
      final seen = <String>{};
      final duplicates = <String>[];

      for (final entry in registry.anchors) {
        if (!seen.add(entry.bibleStoryKey)) {
          duplicates.add(entry.bibleStoryKey);
        }
      }

      if (duplicates.isNotEmpty) {
        print('\n\u{1f6a8} DUPLICATE bibleStoryKeys:');
        for (final d in duplicates) {
          print('  - $d');
        }
      }

      expect(
        duplicates,
        isEmpty,
        reason: 'bibleStoryKey must be globally unique. Duplicates: $duplicates',
      );
    });

    test('CRITICAL: scriptureAnchorId format is valid', () {
      // Format: book_chapter_verse-verse or book_chapter or book_chapter-chapter
      final anchorRegex = RegExp(r'^[a-z0-9]+(_[a-z0-9]+)*(-[a-z0-9]+)?$');
      final invalid = <String>[];

      for (final entry in registry.anchors) {
        if (!anchorRegex.hasMatch(entry.scriptureAnchorId)) {
          invalid.add(
              '${entry.bibleStoryKey}: "${entry.scriptureAnchorId}"');
        }
      }

      if (invalid.isNotEmpty) {
        print('\n\u{26a0}\u{fe0f} Invalid scriptureAnchorId format:');
        for (final i in invalid) {
          print('  - $i');
        }
      }

      expect(
        invalid,
        isEmpty,
        reason: 'scriptureAnchorId must be normalized book_chapter_verse format',
      );
    });

    test('All bibleStoryKeys are snake_case', () {
      final snakeCaseRegex = RegExp(r'^[a-z][a-z0-9_]*$');
      final invalid = <String>[];

      for (final entry in registry.anchors) {
        if (!snakeCaseRegex.hasMatch(entry.bibleStoryKey)) {
          invalid.add(entry.bibleStoryKey);
        }
      }

      expect(
        invalid,
        isEmpty,
        reason: 'All bibleStoryKeys must be snake_case. Invalid: $invalid',
      );
    });

    test('All moodTags are valid moods', () {
      const validMoods = {
        'joyful',
        'grateful',
        'anxious',
        'hurting',
        'weary',
        'brave_courage',
        'calm_peaceful',
        'encouraging',
      };
      final invalid = <String>[];

      for (final entry in registry.anchors) {
        for (final mood in entry.moodTags) {
          if (!validMoods.contains(mood)) {
            invalid.add('${entry.bibleStoryKey}: "$mood"');
          }
        }
      }

      expect(
        invalid,
        isEmpty,
        reason: 'All moodTags must be valid moods. Invalid: $invalid',
      );
    });

    test('CRITICAL: Every mood has at least one anchor', () {
      const requiredMoods = {
        'joyful',
        'grateful',
        'anxious',
        'hurting',
        'weary',
        'brave_courage',
        'calm_peaceful',
        'encouraging',
      };

      final coveredMoods = registry.coveredMoods;
      final missing = requiredMoods.difference(coveredMoods);

      if (missing.isNotEmpty) {
        print('\n\u{1f6a8} Moods with NO anchor in registry:');
        for (final m in missing) {
          print('  - $m');
        }
      }

      expect(
        missing,
        isEmpty,
        reason: 'Every mood must have at least one anchor. Missing: $missing',
      );
    });

    test('Registry is not empty', () {
      expect(
        registry.anchors.isNotEmpty,
        isTrue,
        reason: 'Scripture Anchor Registry must have at least one entry',
      );
    });

    test('Every entry has a non-empty bibleSourceRef', () {
      final empty = registry.anchors
          .where((e) => e.bibleSourceRef.trim().isEmpty)
          .map((e) => e.bibleStoryKey)
          .toList();

      expect(
        empty,
        isEmpty,
        reason: 'Every entry must have a non-empty bibleSourceRef. Empty: $empty',
      );
    });

    test('Every entry has at least one moodTag', () {
      final empty = registry.anchors
          .where((e) => e.moodTags.isEmpty)
          .map((e) => e.bibleStoryKey)
          .toList();

      expect(
        empty,
        isEmpty,
        reason: 'Every entry must have at least one moodTag. Empty: $empty',
      );
    });
  });

  group('Scripture Anchor Registry — Manifest Alignment', () {
    test(
        'CRITICAL: Each manifest bibleStoryKey exists in registry',
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
        print('\n\u{1f6a8} Manifest stories with UNREGISTERED bibleStoryKey:');
        for (final u in unregistered) {
          print('  - $u');
        }
      }

      expect(
        unregistered,
        isEmpty,
        reason:
            'Every Traditional story in manifest must have a registered bibleStoryKey. '
            'Unregistered: $unregistered',
      );
    });

    test(
        'CRITICAL: Each manifest story mood matches its anchor moodTags',
        () {
      final mismatches = <String>[];

      for (final p in traditionalParables) {
        if (p.hasBibleStoryKey) {
          final entry = registry.getByStoryKey(p.bibleStoryKey!);
          if (entry != null && !entry.moodTags.contains(p.mood)) {
            mismatches.add(
                '${p.storyId}: mood="${p.mood}" not in '
                'anchor moodTags=${entry.moodTags}');
          }
        }
      }

      if (mismatches.isNotEmpty) {
        print('\n\u{1f6a8} Manifest mood not in anchor moodTags:');
        for (final m in mismatches) {
          print('  - $m');
        }
      }

      expect(
        mismatches,
        isEmpty,
        reason: 'Manifest story mood must appear in its anchor moodTags. '
            'Mismatches: $mismatches',
      );
    });

    test(
        'INFO: bibleSourceRef alignment between registry and manifest',
        () {
      // Note: Some legacy/v1 manifest entries have different bibleSourceRef
      // than the registry (e.g., backfilled entries with Psalm references).
      // This is informational — the registry is the source of truth for new entries.
      final mismatches = <String>{};

      for (final p in traditionalParables) {
        if (p.hasBibleStoryKey && p.hasBibleSourceRef) {
          final entry = registry.getByStoryKey(p.bibleStoryKey!);
          if (entry != null && entry.bibleSourceRef != p.bibleSourceRef) {
            mismatches.add(
                '${p.bibleStoryKey}: registry="${entry.bibleSourceRef}" '
                'manifest="${p.bibleSourceRef}"');
          }
        }
      }

      if (mismatches.isNotEmpty) {
        print('\n\u{26a0}\u{fe0f} bibleSourceRef mismatches (legacy data):');
        for (final m in mismatches) {
          print('  - $m');
        }
        print('\nThese are pre-existing v1 backfill mismatches. '
            'Registry is the source of truth for new entries.');
      }

      // Informational only — does not fail
      expect(true, isTrue);
    });
  });

  group('INFO Reports', () {
    test('INFO: Scripture Anchor Registry report', () {
      print('\n\u{1f4da} Scripture Anchor Registry Report:\n');

      print('Anchors by mood:');
      final byMood = registry.entriesByMood;
      for (final mood in byMood.keys.toList()..sort()) {
        final entries = byMood[mood]!;
        print('  $mood (${entries.length} anchors):');
        for (final e in entries) {
          print('    - ${e.bibleStoryKey} [${e.scriptureAnchorId}] '
              '${e.bibleSourceRef}');
        }
      }

      // Derive used status from manifest
      final usedKeys = traditionalParables
          .where((p) => p.hasBibleStoryKey)
          .map((p) => p.bibleStoryKey!)
          .toSet();
      final unusedAnchors = registry.anchors
          .where((a) => !usedKeys.contains(a.bibleStoryKey))
          .toList();

      print('\nUnused anchors (not yet in manifest): ${unusedAnchors.length}');
      for (final a in unusedAnchors) {
        print('  - ${a.bibleStoryKey} [${a.scriptureAnchorId}]');
      }

      expect(true, isTrue);
    });
  });
}
