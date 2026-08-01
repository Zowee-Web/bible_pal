import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/features/paths/path_type.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/services/path_service.dart';

/// Narrow regression guard for the Genesis 14-19 chronology fix.
///
/// Before 2026-08-01 the adult Genesis Bible-order path emitted its
/// chapters as 14 -> 16 -> 18 -> 16 -> 17 -> 15 -> 18 -> 19, because
/// `bibleOrderIndex` had drifted: Genesis 15 sat at 30 (last of the
/// window) and Genesis 18:1-15 sat at 18 (ahead of Genesis 15, 16 and
/// 17). Four indices were corrected — 1241 -> 15, 1269 -> 16,
/// 1405 -> 17, 1020 -> 29 — restoring canonical order.
///
/// This test is deliberately NARROW. It is not a corpus-wide chronology
/// validator: it pins exactly the eight stories in the repaired window
/// and the one kid-lane index the repair had to leave alone. Genesis
/// ordering outside 14-19 is known to be imperfect (see
/// scratchpad/GENESIS_14_19_ORDER_AUDIT.md §4) and is deliberately not
/// asserted here.
void main() {
  /// The repaired window, in the order the adult Genesis path must emit
  /// them after PathService de-duplication.
  const expectedOrder = <String>[
    'story_1351_brave_courage_short_traditional', // Genesis 14:13-16 · 14
    'story_1241_calm_peaceful_short_traditional', // Genesis 15:1-21  · 15
    'story_1269_hurting_short_traditional', // Genesis 16:1-14  · 16
    'story_1405_anxious_short_traditional', // Genesis 16:6-9   · 17
    'story_1615_encouraging_short_traditional', // Genesis 17       · 28
    'story_1020_grateful_short_traditional', // Genesis 18:1-15  · 29
    'story_1487_anxious_short_traditional', // Genesis 18:16-33 · 33
    'story_1613_anxious_short_traditional', // Genesis 19:1-29  · 34
  ];

  late List<Parable> parables;

  setUpAll(() {
    final file = File('assets/stories/manifest.json');
    expect(file.existsSync(), isTrue,
        reason: 'assets/stories/manifest.json must exist');
    final manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    parables = (manifest['parables'] as List)
        .cast<Map<String, dynamic>>()
        .map(Parable.fromJson)
        .toList(growable: false);
  });

  test('adult Genesis path emits Genesis 14-19 in chronological order', () {
    final service = PathService(
      traditionalParables: parables,
      jesusLifeSequence: const <String>[],
      kidFriendlyOnly: false,
    );

    final emitted = service
        .getPathStories(PathType.bibleOrder, 'genesis')
        .map((p) => p.storyId)
        .toList();

    // Every expected story must survive filtering and de-duplication.
    for (final storyId in expectedOrder) {
      expect(emitted, contains(storyId),
          reason: '$storyId must be the surviving representative in the '
              'adult Genesis path');
    }

    // Relative order only — other Genesis stories legitimately interleave.
    final positions = [
      for (final storyId in expectedOrder) emitted.indexOf(storyId),
    ];
    final sorted = [...positions]..sort();
    expect(positions, sorted,
        reason: 'Genesis 14-19 must be emitted in this relative order:\n'
            '${expectedOrder.join('\n')}\n'
            'Actual positions: $positions\n'
            'A failure here means a bibleOrderIndex regressed — see '
            'scratchpad/GENESIS_14_19_ORDER_AUDIT.md');
  });

  test('kid-lane story 1028 retains bibleOrderIndex 19061', () {
    // 1028 is the kid counterpart of 1020 and shares its bibleStoryKey and
    // title, so the two de-duplicate together. 19061 belongs to the kid
    // numbering series (19061 / 33082 / 38061) where it is correctly
    // ordered, and it must NOT be dragged along by the adult repair.
    final kidEntries = parables
        .where((p) => p.storyId.startsWith('story_1028_'))
        .toList();

    expect(kidEntries, isNotEmpty,
        reason: 'story 1028 must exist in manifest.json');
    for (final entry in kidEntries) {
      expect(entry.bibleOrderIndex, 19061,
          reason: '${entry.storyId} must keep the kid-series index 19061; '
              'the Genesis 14-19 adult repair must not touch the kid lane');
      expect(entry.kidFriendly, isTrue,
          reason: '${entry.storyId} is the kid-lane counterpart of 1020');
    }
  });
}
