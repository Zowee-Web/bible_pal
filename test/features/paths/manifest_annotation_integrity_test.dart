import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/timeline_era.dart';
import 'package:bible_pal/features/paths/theme_vocabulary.dart';

/// Phase 2 Slice 2 integrity scan.
///
/// Reads `assets/stories/manifest.json` directly from disk and verifies
/// that every PALs Paths annotation (the 8 optional fields introduced in
/// Phase 1) conforms to the locked vocabularies from Phase 1 and this
/// phase:
///
/// - `primaryCharacterId` must be a registered character ID (LOCKED in
///   `assets/stories/character_registry.json`). `jesus` is allowed here
///   because the registry treats it as a reserved ID — the Characters
///   path list exclusion is enforced elsewhere.
/// - `timelineEra` must be one of the 9 canonical eras from SPEC 50.2.
/// - Every entry in `themeTags[]` must be in the locked 8-tag vocabulary
///   from SPEC 50.
/// - Manifest must contain zero Creative entries (Creative retirement
///   2026-05-13 — see docs/archive/CREATIVE_RETIREMENT_2026_05_13.md).
/// - `bibleOrderIndex` and `characterPathOrder` must be non-negative
///   integers when present.
/// - The Phase 2 seed batch must contain at least 10 annotated stories.
void main() {
  late Map<String, dynamic> manifest;
  late List<Map<String, dynamic>> entries;
  late Set<String> validCharacterIds;

  setUpAll(() async {
    // Read manifest.json directly — this is a file-integrity scan,
    // not a service-level test.
    final manifestFile = File('assets/stories/manifest.json');
    expect(manifestFile.existsSync(), isTrue,
        reason: 'assets/stories/manifest.json must exist');
    manifest = jsonDecode(await manifestFile.readAsString())
        as Map<String, dynamic>;
    final rawEntries = manifest['parables'] as List<dynamic>;
    entries = rawEntries.cast<Map<String, dynamic>>();

    // Load character registry the same way (directly from disk).
    final registryFile =
        File('assets/stories/character_registry.json');
    expect(registryFile.existsSync(), isTrue);
    final registry = jsonDecode(await registryFile.readAsString())
        as Map<String, dynamic>;
    final characters = registry['characters'] as Map<String, dynamic>;
    validCharacterIds = characters.keys.toSet();
  });

  /// List of parables that carry at least one PALs Paths annotation
  /// field. Used for both positive (integrity) and negative
  /// (Creative-never-annotated) scans.
  List<Map<String, dynamic>> annotated() {
    // A story is a genuine PALs Paths annotation only when it carries a
    // Paths-SPECIFIC field. `themeTags`/`primaryCharacterDisplayName` are NOT
    // sufficient triggers: themeTags was backfilled corpus-wide as editorial
    // metadata, and dedicated kid-lane stories carry it in a different style.
    return entries
        .where((e) =>
            e.containsKey('primaryCharacterId') ||
            e.containsKey('characterIds') ||
            e.containsKey('bibleOrderIndex') ||
            e.containsKey('timelineEra') ||
            e.containsKey('characterPathOrder'))
        .toList();
  }

  group('Phase 2 seed batch size', () {
    test('at least 10 annotated stories exist in the manifest', () {
      expect(annotated().length, greaterThanOrEqualTo(10),
          reason:
              'Phase 2 Slice 2 should land a 10-story annotation batch');
    });
  });

  group('primaryCharacterId integrity', () {
    test('every annotated story has a primaryCharacterId in the registry',
        () {
      final violations = <String>[];
      for (final entry in annotated()) {
        final primary = entry['primaryCharacterId'] as String?;
        final storyId = entry['storyId'] as String? ?? '<unknown>';
        if (primary == null || primary.isEmpty) {
          violations.add(
              '$storyId: annotated but missing primaryCharacterId');
          continue;
        }
        if (!validCharacterIds.contains(primary)) {
          violations.add(
              '$storyId: primaryCharacterId "$primary" not in character registry');
        }
      }
      expect(violations, isEmpty,
          reason: violations.join('\n'));
    });

    test('primaryCharacterDisplayName is present when primaryCharacterId is',
        () {
      final violations = <String>[];
      for (final entry in annotated()) {
        final primary = entry['primaryCharacterId'] as String?;
        final displayName =
            entry['primaryCharacterDisplayName'] as String?;
        final storyId = entry['storyId'] as String? ?? '<unknown>';
        if (primary != null &&
            (displayName == null || displayName.isEmpty)) {
          violations.add(
              '$storyId: primaryCharacterId="$primary" but primaryCharacterDisplayName missing');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  group('timelineEra integrity', () {
    final validEraWireIds = TimelineEra.values.map((e) => e.wireId).toSet();

    test('every timelineEra is one of the 9 locked eras', () {
      final violations = <String>[];
      for (final entry in annotated()) {
        final era = entry['timelineEra'] as String?;
        final storyId = entry['storyId'] as String? ?? '<unknown>';
        if (era != null && !validEraWireIds.contains(era)) {
          violations.add(
              '$storyId: timelineEra "$era" not in locked 9-era list '
              '(${validEraWireIds.join(", ")})');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  group('themeTags integrity', () {
    test('every theme tag is in the locked 8-tag vocabulary', () {
      final validTags = ThemeTagParse.allWireIds;
      final violations = <String>[];
      for (final entry in annotated()) {
        final tags = entry['themeTags'] as List<dynamic>?;
        final storyId = entry['storyId'] as String? ?? '<unknown>';
        if (tags == null) continue;
        for (final tag in tags) {
          if (tag is! String) {
            violations.add('$storyId: themeTags contains non-string value');
            continue;
          }
          if (!validTags.contains(tag)) {
            violations.add(
                '$storyId: theme tag "$tag" not in locked vocabulary '
                '(${validTags.join(", ")})');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('annotated stories use a non-empty themeTags list when present', () {
      final violations = <String>[];
      for (final entry in annotated()) {
        final tags = entry['themeTags'] as List<dynamic>?;
        final storyId = entry['storyId'] as String? ?? '<unknown>';
        if (tags != null && tags.isEmpty) {
          violations.add('$storyId: themeTags is present but empty');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  group('bibleOrderIndex and characterPathOrder types', () {
    test('bibleOrderIndex is a non-negative int when present', () {
      final violations = <String>[];
      for (final entry in annotated()) {
        final idx = entry['bibleOrderIndex'];
        final storyId = entry['storyId'] as String? ?? '<unknown>';
        if (idx == null) continue;
        if (idx is! int || idx < 0) {
          violations.add(
              '$storyId: bibleOrderIndex must be non-negative int, got $idx');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('characterPathOrder is a non-negative int when present', () {
      final violations = <String>[];
      for (final entry in annotated()) {
        final order = entry['characterPathOrder'];
        final storyId = entry['storyId'] as String? ?? '<unknown>';
        if (order == null) continue;
        if (order is! int || order < 0) {
          violations.add(
              '$storyId: characterPathOrder must be non-negative int, got $order');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  group('Creative retirement (2026-05-13)', () {
    test('manifest contains zero Creative entries', () {
      final creativeStoryIds = entries
          .where((e) => e['storytellingMode'] == 'creative')
          .map((e) => e['storyId'] as String? ?? '<unknown>')
          .toList();
      expect(creativeStoryIds, isEmpty,
          reason: 'Creative entries have been retired. See '
              'docs/archive/CREATIVE_RETIREMENT_2026_05_13.md. '
              'Found ${creativeStoryIds.length} Creative entries: '
              '${creativeStoryIds.take(5).join(", ")}');
    });
  });

  group('Phase 2 coverage criteria met', () {
    test('at least 2 distinct characters have >=2 annotated stories each',
        () {
      final counts = <String, int>{};
      for (final entry in annotated()) {
        final primary = entry['primaryCharacterId'] as String?;
        if (primary == null) continue;
        counts[primary] = (counts[primary] ?? 0) + 1;
      }
      final multiStoryChars =
          counts.entries.where((e) => e.value >= 2).map((e) => e.key).toList();
      // Jesus and at least one other character must reach >=2 stories
      expect(multiStoryChars.length, greaterThanOrEqualTo(2),
          reason:
              'Phase 2 coverage: at least 2 characters need >=2 stories. '
              'Got: $counts');
    });

    test('at least 2 distinct timeline eras are present', () {
      final eras = <String>{};
      for (final entry in annotated()) {
        final era = entry['timelineEra'] as String?;
        if (era != null) eras.add(era);
      }
      expect(eras.length, greaterThanOrEqualTo(2),
          reason: 'Phase 2 coverage: at least 2 timeline eras. Got: $eras');
    });

    test('at least 2 distinct theme tags are used', () {
      final themes = <String>{};
      for (final entry in annotated()) {
        final tags = entry['themeTags'] as List<dynamic>?;
        if (tags == null) continue;
        for (final t in tags) {
          if (t is String) themes.add(t);
        }
      }
      expect(themes.length, greaterThanOrEqualTo(2),
          reason: 'Phase 2 coverage: at least 2 theme tags. Got: $themes');
    });

    test('at least 3 jesus-centric stories are annotated for jesus_life seed',
        () {
      final jesusCount = annotated()
          .where((e) => e['primaryCharacterId'] == 'jesus')
          .length;
      expect(jesusCount, greaterThanOrEqualTo(3),
          reason:
              'Phase 2 coverage: at least 3 jesus-centric stories for the '
              'jesus_life seed. Got: $jesusCount');
    });
  });

  group('jesus_life_index.json integrity', () {
    test('curated sequence references real annotated jesus stories', () async {
      final indexFile = File('assets/stories/jesus_life_index.json');
      expect(indexFile.existsSync(), isTrue);
      final indexJson = jsonDecode(await indexFile.readAsString())
          as Map<String, dynamic>;
      final sequence = (indexJson['sequence'] as List<dynamic>)
          .map((e) => e as String)
          .toList();

      // Build lookup of annotated jesus stories.
      final annotatedJesusIds = annotated()
          .where((e) => e['primaryCharacterId'] == 'jesus')
          .map((e) => e['storyId'] as String)
          .toSet();

      final violations = <String>[];
      for (final storyId in sequence) {
        if (!annotatedJesusIds.contains(storyId)) {
          violations.add(
              'jesus_life sequence entry "$storyId" is not an annotated '
              'jesus-centric story');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('curated sequence is non-empty for Phase 2', () async {
      final indexFile = File('assets/stories/jesus_life_index.json');
      final indexJson = jsonDecode(await indexFile.readAsString())
          as Map<String, dynamic>;
      final sequence = indexJson['sequence'] as List<dynamic>;
      expect(sequence.length, greaterThanOrEqualTo(3),
          reason: 'Phase 2 seeds >=3 entries in jesus_life_index.json');
    });
  });
}
