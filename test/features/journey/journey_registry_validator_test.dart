import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schema + content validator for the Journey registry JSON files.
///
/// Journey Doctrine v0 (see docs/JOURNEY_DOCTRINE.md), Slice 2 prep.
/// This is a pure structure test — it walks the filesystem and parses
/// JSON, without depending on any runtime Dart models. Catches drift
/// at CI time so a bad authoring edit fails build, not runtime.
///
/// Coverage:
///   - Every JSON file in assets/stories/journeys/ parses.
///   - Each carries the required top-level fields with sane values.
///   - Each story sub-entry carries required fields.
///   - journeyType is one of the doctrine's 5 enum values.
///   - lane is adult or kid.
///   - status is one of held / draft / ready.
///   - Kid journeys obey the doctrine's Kid-Lane Appendix:
///       - journeyType ∈ {narrative, character, practice} (NO theme, NO teaching).
///       - 3 ≤ stories.length ≤ 5.
///   - Adult journeys ≤ 7 stories (sanity ceiling for v0).
///   - journeyId is globally unique across files.
///   - "ready" journeys cross-check against the live manifest:
///       - Each storyNumber resolves to at least one manifest entry.
///       - nameRegistryKey (if set) resolves to display_name_registry.
void main() {
  const journeysDir = 'assets/stories/journeys';

  const allowedTypes = {
    'narrative',
    'character',
    'theme',
    'teaching',
    'practice',
  };
  const allowedLanes = {'adult', 'kid'};
  const allowedStatuses = {'held', 'draft', 'ready'};
  const kidAllowedTypes = {'narrative', 'character', 'practice'};

  late List<File> journeyFiles;
  late List<Map<String, dynamic>> journeys;

  setUpAll(() {
    final dir = Directory(journeysDir);
    if (!dir.existsSync()) {
      // The dir is allowed to be empty pre-Slice-2 — tests skip in that case.
      journeyFiles = const [];
      journeys = const [];
      return;
    }
    journeyFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    journeys = journeyFiles
        .map((f) => jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)
        .toList();
  });

  test('journeys/ directory exists when the registry has files', () {
    // Soft check — if the dir is missing entirely, the rest of the
    // tests skip. Once Slice 2 lands at least one file, this stays
    // truthy forever.
    if (journeyFiles.isEmpty) {
      markTestSkipped(
          'No assets/stories/journeys/*.json files — Journey registry not '
          'yet populated. This test activates as soon as any journey JSON '
          'is authored.');
      return;
    }
    expect(journeyFiles, isNotEmpty);
  });

  group('per-journey structural invariants', () {
    test('every journey has required top-level fields', () {
      if (journeys.isEmpty) {
        markTestSkipped('No journeys to validate');
        return;
      }
      for (var i = 0; i < journeys.length; i++) {
        final j = journeys[i];
        final path = journeyFiles[i].path;
        expect(j['journeyId'], isA<String>(),
            reason: '$path: missing/wrong-type journeyId');
        expect(j['journeyType'], isA<String>(),
            reason: '$path: missing/wrong-type journeyType');
        expect(j['lane'], isA<String>(),
            reason: '$path: missing/wrong-type lane');
        expect(j['status'], isA<String>(),
            reason: '$path: missing/wrong-type status');
        expect(j['stories'], isA<List<dynamic>>(),
            reason: '$path: missing/wrong-type stories');
        expect((j['stories'] as List).isNotEmpty, isTrue,
            reason: '$path: stories[] cannot be empty');
      }
    });

    test('journeyType, lane, status all use allowed enums', () {
      if (journeys.isEmpty) {
        markTestSkipped('No journeys to validate');
        return;
      }
      for (var i = 0; i < journeys.length; i++) {
        final j = journeys[i];
        final path = journeyFiles[i].path;
        expect(allowedTypes, contains(j['journeyType']),
            reason: '$path: journeyType="${j['journeyType']}" not in $allowedTypes');
        expect(allowedLanes, contains(j['lane']),
            reason: '$path: lane="${j['lane']}" not in $allowedLanes');
        expect(allowedStatuses, contains(j['status']),
            reason: '$path: status="${j['status']}" not in $allowedStatuses');
      }
    });

    test('every story sub-entry has required identifying fields', () {
      if (journeys.isEmpty) {
        markTestSkipped('No journeys to validate');
        return;
      }
      for (var i = 0; i < journeys.length; i++) {
        final j = journeys[i];
        final path = journeyFiles[i].path;
        final stories = (j['stories'] as List).cast<Map<String, dynamic>>();
        for (var k = 0; k < stories.length; k++) {
          final s = stories[k];
          final hasNumber =
              s.containsKey('storyNumber') || s.containsKey('productionId');
          final hasAnchor =
              s.containsKey('scriptureAnchorId') || s.containsKey('anchorId');
          expect(hasNumber, isTrue,
              reason:
                  '$path: stories[$k] missing storyNumber/productionId');
          expect(hasAnchor, isTrue,
              reason:
                  '$path: stories[$k] missing scriptureAnchorId/anchorId');
          expect(s['label'], isA<String>(),
              reason: '$path: stories[$k] missing label');
        }
      }
    });
  });

  group('kid-lane appendix invariants', () {
    test('kid journeys allow only narrative/character/practice types', () {
      if (journeys.isEmpty) {
        markTestSkipped('No journeys to validate');
        return;
      }
      for (var i = 0; i < journeys.length; i++) {
        final j = journeys[i];
        if (j['lane'] != 'kid') continue;
        final path = journeyFiles[i].path;
        expect(kidAllowedTypes, contains(j['journeyType']),
            reason:
                '$path: kid journey type="${j['journeyType']}" not in $kidAllowedTypes — doctrine forbids theme/teaching for kids');
      }
    });

    test('kid journeys are 3-5 stories', () {
      if (journeys.isEmpty) {
        markTestSkipped('No journeys to validate');
        return;
      }
      for (var i = 0; i < journeys.length; i++) {
        final j = journeys[i];
        if (j['lane'] != 'kid') continue;
        final path = journeyFiles[i].path;
        final count = (j['stories'] as List).length;
        expect(count, inInclusiveRange(3, 5),
            reason:
                '$path: kid journey has $count stories — doctrine caps at 3-5');
      }
    });
  });

  group('adult-lane sanity', () {
    test('adult journeys are at most 7 stories (v0 sanity ceiling)', () {
      if (journeys.isEmpty) {
        markTestSkipped('No journeys to validate');
        return;
      }
      for (var i = 0; i < journeys.length; i++) {
        final j = journeys[i];
        if (j['lane'] != 'adult') continue;
        final path = journeyFiles[i].path;
        final count = (j['stories'] as List).length;
        expect(count, lessThanOrEqualTo(7),
            reason:
                '$path: adult journey has $count stories — v0 sanity ceiling is 7');
      }
    });
  });

  test('journeyId is globally unique across all files', () {
    if (journeys.isEmpty) {
      markTestSkipped('No journeys to validate');
      return;
    }
    final seen = <String, String>{};
    for (var i = 0; i < journeys.length; i++) {
      final id = journeys[i]['journeyId'] as String;
      final path = journeyFiles[i].path;
      if (seen.containsKey(id)) {
        fail('Duplicate journeyId "$id" in $path AND ${seen[id]}');
      }
      seen[id] = path;
    }
  });

  group('ready-journey live cross-checks (only for status=ready)', () {
    late Map<String, Map<String, dynamic>> manifestByNumber;
    late Set<String> displayNameRegistryKeys;

    setUpAll(() {
      // Build a {storyNumber: any-variant-entry} map from the adult
      // manifest so we can verify ready journeys reference real
      // stories. Pulls the leading numeric ID out of sid forms like
      // story_1486_*, kidstory_*, etc.
      manifestByNumber = {};
      final manifestRaw = File('assets/stories/manifest.json').readAsStringSync();
      final manifest = jsonDecode(manifestRaw) as dynamic;
      Iterable<Map<String, dynamic>> entries;
      // manifest.json wraps entries under "parables" (current shape).
      // "entries" + bare-list fallbacks kept defensively for forward
      // compat in case the shape evolves.
      if (manifest is Map<String, dynamic> && manifest['parables'] is List) {
        entries =
            (manifest['parables'] as List).cast<Map<String, dynamic>>();
      } else if (manifest is Map<String, dynamic> && manifest['entries'] is List) {
        entries =
            (manifest['entries'] as List).cast<Map<String, dynamic>>();
      } else if (manifest is List) {
        entries = manifest.cast<Map<String, dynamic>>();
      } else {
        entries = const [];
      }
      for (final e in entries) {
        final sid = e['storyId']?.toString() ?? e['id']?.toString() ?? '';
        // story_<N>_*  →  N
        final m = RegExp(r'^story_(\d+)_').firstMatch(sid);
        if (m != null) {
          manifestByNumber.putIfAbsent(m.group(1)!, () => e);
        }
        // kidstory_kid_<anchor>_<length>  →  anchor key
        final mk = RegExp(r'^kidstory_kid_([a-z_]+?)_(short|full|long)$')
            .firstMatch(sid);
        if (mk != null) {
          manifestByNumber.putIfAbsent('kid:${mk.group(1)}', () => e);
        }
      }

      // Load display_name_registry keys for nameRegistryKey cross-check.
      final regRaw = File('assets/pal/memory/display_name_registry.json')
          .readAsStringSync();
      final reg = jsonDecode(regRaw) as Map<String, dynamic>;
      final regEntries =
          (reg['entries'] as List).cast<Map<String, dynamic>>();
      displayNameRegistryKeys =
          regEntries.map((e) => e['bibleStoryKey'] as String).toSet();
    });

    test('every ready-journey story resolves to a manifest entry', () {
      if (journeys.isEmpty) {
        markTestSkipped('No journeys to validate');
        return;
      }
      for (var i = 0; i < journeys.length; i++) {
        final j = journeys[i];
        if (j['status'] != 'ready') continue;
        final path = journeyFiles[i].path;
        final stories = (j['stories'] as List).cast<Map<String, dynamic>>();
        for (var k = 0; k < stories.length; k++) {
          final s = stories[k];
          String lookupKey;
          if (j['lane'] == 'kid') {
            // Kid lane lookup by anchor.
            lookupKey = 'kid:${s['anchorId']}';
          } else {
            lookupKey = (s['storyNumber'] ?? s['productionId']).toString();
          }
          expect(manifestByNumber.containsKey(lookupKey), isTrue,
              reason:
                  '$path: ready journey references story "$lookupKey" '
                  '(stories[$k]: ${s['label']}) but no manifest entry resolves to it. '
                  'Journey cannot ship as-is.');
        }
      }
    });

    test('nameRegistryKey (if set, ready-only) resolves in display_name_registry',
        () {
      if (journeys.isEmpty) {
        markTestSkipped('No journeys to validate');
        return;
      }
      for (var i = 0; i < journeys.length; i++) {
        final j = journeys[i];
        if (j['status'] != 'ready') continue;
        final key = j['nameRegistryKey'];
        if (key == null) continue;
        final path = journeyFiles[i].path;
        expect(displayNameRegistryKeys, contains(key),
            reason:
                '$path: nameRegistryKey="$key" not found in '
                'assets/pal/memory/display_name_registry.json — the '
                'compositional offer audio cannot resolve');
      }
    });
  });
}
