import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/pal_memory/pal_memory_display_name_registry.dart';

/// Tests for the PAL memory display-name registry — Slice 2c.1 of the
/// PAL Memory Doctrine (docs/PAL_MEMORY_DOCTRINE.md).
///
/// The registry maps `bibleStoryKey` → spoken display name + clipId. It
/// is the editorial source of truth for what PAL says when referencing a
/// story in a memory line. These tests verify:
/// - structural integrity of the bundled registry (uniqueness, shape)
/// - cross-validation: every entry references a real anchor in
///   `assets/stories/scripture_anchor_registry.json`
/// - the constructor's failure modes (loud throws on bad data)
/// - the opt-out contract (`lookup` returns null for unknown keys)
void main() {
  late PalMemoryDisplayNameRegistry registry;
  late Set<String> validAnchorKeys;

  setUpAll(() {
    final registryFile =
        File('assets/pal/memory/display_name_registry.json');
    expect(registryFile.existsSync(), isTrue,
        reason: 'Registry asset must exist at the bundled path');
    registry = PalMemoryDisplayNameRegistry.fromJson(
        registryFile.readAsStringSync());

    final anchorFile =
        File('assets/stories/scripture_anchor_registry.json');
    expect(anchorFile.existsSync(), isTrue);
    final anchorData =
        jsonDecode(anchorFile.readAsStringSync()) as Map<String, dynamic>;
    final anchors = anchorData['anchors'] as List<dynamic>;
    validAnchorKeys = {
      for (final a in anchors)
        (a as Map<String, dynamic>)['bibleStoryKey'] as String
    };
  });

  group('bundled registry — structural integrity', () {
    test('loads with at least one entry', () {
      expect(registry.count, greaterThan(0));
      expect(registry.all, isNotEmpty);
    });

    test('all bibleStoryKeys are unique', () {
      final keys = registry.all.map((e) => e.bibleStoryKey).toList();
      expect(keys.length, keys.toSet().length,
          reason: 'duplicates: ${keys.where((k) => keys.where((kk) => kk == k).length > 1).toSet()}');
    });

    test('all clipIds are unique', () {
      final ids = registry.all.map((e) => e.clipId).toList();
      expect(ids.length, ids.toSet().length);
    });

    test('every entry has non-empty, whitespace-clean displayName', () {
      for (final e in registry.all) {
        expect(e.displayName, isNotEmpty);
        expect(e.displayName.trim(), e.displayName,
            reason: 'displayName has leading/trailing whitespace: "${e.displayName}"');
      }
    });

    test('every clipId is filesystem-safe', () {
      final safe = RegExp(r'^[a-z0-9_]+$');
      for (final e in registry.all) {
        expect(safe.hasMatch(e.clipId), isTrue,
            reason:
                'clipId "${e.clipId}" must be lowercase alphanumeric + underscores only '
                '(bibleStoryKey="${e.bibleStoryKey}")');
      }
    });
  });

  group('lookup contract', () {
    test('returns the entry for a known bibleStoryKey', () {
      final entry = registry.lookup('daniel_in_the_lions_den');
      expect(entry, isNotNull);
      expect(entry!.displayName, 'Daniel');
      expect(entry.clipId, 'name_daniel');
    });

    test('returns null for an unknown bibleStoryKey (opt-out path)', () {
      // The doctrine's silence floor depends on this returning null —
      // engine + resolver should treat null as "no memory line for this
      // story" rather than throwing or falling back to a generic phrase.
      expect(registry.lookup('definitely_not_a_real_anchor_key'), isNull);
    });

    test('the seed entries demonstrate the editorial discipline', () {
      // These exact phrasings encode the editorial taste — definite
      // articles, just-the-name vs. character-pair, etc. If any of these
      // change, it should be because Adam decided so, not because a test
      // grew lax.
      expect(registry.lookup('good_samaritan')?.displayName,
          'the Good Samaritan');
      expect(registry.lookup('prodigal_son')?.displayName, 'the lost son');
      expect(registry.lookup('jonah_in_fish')?.displayName, 'Jonah');
      expect(registry.lookup('david_and_goliath')?.displayName,
          'David and Goliath');
    });
  });

  group('cross-validation against scripture_anchor_registry', () {
    test('every bibleStoryKey in the registry exists in the anchor registry',
        () {
      final missing = registry.all
          .where((e) => !validAnchorKeys.contains(e.bibleStoryKey))
          .map((e) => e.bibleStoryKey)
          .toList();
      expect(missing, isEmpty,
          reason:
              'PAL memory display name registry references non-existent '
              'bibleStoryKey(s): $missing. Every entry must correspond to a '
              'real anchor in assets/stories/scripture_anchor_registry.json. '
              'Either add the missing anchor first or remove the registry entry.');
    });
  });

  group('constructor — loud failures on bad input', () {
    test('duplicate bibleStoryKey throws StateError', () {
      const dup = '''
{
  "version": 1,
  "entries": [
    {"bibleStoryKey": "x", "displayName": "X", "clipId": "name_x"},
    {"bibleStoryKey": "x", "displayName": "X-2", "clipId": "name_x_two"}
  ]
}
''';
      expect(() => PalMemoryDisplayNameRegistry.fromJson(dup),
          throwsStateError);
    });

    test('duplicate clipId throws StateError', () {
      const dup = '''
{
  "version": 1,
  "entries": [
    {"bibleStoryKey": "x", "displayName": "X",  "clipId": "name_shared"},
    {"bibleStoryKey": "y", "displayName": "Y",  "clipId": "name_shared"}
  ]
}
''';
      expect(() => PalMemoryDisplayNameRegistry.fromJson(dup),
          throwsStateError);
    });

    test('unsafe clipId throws StateError', () {
      const bad = '''
{
  "version": 1,
  "entries": [
    {"bibleStoryKey": "x", "displayName": "X", "clipId": "Name With Spaces"}
  ]
}
''';
      expect(() => PalMemoryDisplayNameRegistry.fromJson(bad),
          throwsStateError);
    });

    test('empty displayName throws StateError', () {
      const bad = '''
{
  "version": 1,
  "entries": [
    {"bibleStoryKey": "x", "displayName": "", "clipId": "name_x"}
  ]
}
''';
      expect(() => PalMemoryDisplayNameRegistry.fromJson(bad),
          throwsStateError);
    });

    test('whitespace-padded displayName throws StateError', () {
      const bad = '''
{
  "version": 1,
  "entries": [
    {"bibleStoryKey": "x", "displayName": " Daniel ", "clipId": "name_x"}
  ]
}
''';
      expect(() => PalMemoryDisplayNameRegistry.fromJson(bad),
          throwsStateError);
    });

    test('empty bibleStoryKey throws StateError', () {
      const bad = '''
{
  "version": 1,
  "entries": [
    {"bibleStoryKey": "", "displayName": "X", "clipId": "name_x"}
  ]
}
''';
      expect(() => PalMemoryDisplayNameRegistry.fromJson(bad),
          throwsStateError);
    });
  });
}
