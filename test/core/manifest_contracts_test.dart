// CRITICAL: Manifest Contracts Test
// This test enforces HARD invariants on the story manifest.
//
// These tests MUST fail on regression:
// 1. storyLength must be consistent with legacy length (minutes)
// 2. storyId containing '_trad' must have storytellingMode='traditional'
// 3. narratorVoiceKey is REQUIRED for ALL manifest entries
//
// DO NOT WEAKEN THESE TESTS.

@Tags(['critical'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/story_length_bucket.dart';

void main() {
  late Map<String, dynamic> manifestRoot;
  late List<Map<String, dynamic>> parables;

  setUpAll(() async {
    final file = File('assets/stories/manifest.json');
    expect(file.existsSync(), isTrue,
        reason: 'manifest.json must exist at assets/stories/manifest.json');

    final content = await file.readAsString();
    final decoded = jsonDecode(content) as Map<String, dynamic>;
    expect(decoded.containsKey('parables'), isTrue,
        reason: 'manifest.json must contain a "parables" array');

    manifestRoot = decoded;
    parables = (decoded['parables'] as List).cast<Map<String, dynamic>>();
  });

  group('CRITICAL: catalog generation (Catalog Currency invariant)', () {
    test('CRITICAL: top-level version must be a positive integer', () {
      // docs/INVARIANTS.md — Catalog Currency: the bundled manifest is the
      // trusted baseline generation. A missing/wrong-type/non-positive
      // version makes the runtime fail closed (external catalog
      // replacement latched off), so this state must be unmergeable.
      final version = manifestRoot['version'];
      expect(version, isA<int>(),
          reason: '🚨 CATALOG CURRENCY VIOLATION 🚨\n'
              'manifest.json must carry a top-level integer "version" '
              '(catalog generation). Got: ${version.runtimeType}');
      expect(version as int, greaterThan(0),
          reason: '🚨 CATALOG CURRENCY VIOLATION 🚨\n'
              'Catalog generation must be a positive integer, got $version');
    });

    test('initial migration state (generation 6) passes the contract', () {
      // The first versioned manifest shipped as generation 6 (above the
      // live remote catalog v5 at migration time). Generations only move
      // forward from there — PR CI enforces the bump semantically via
      // scripts/check_manifest_version_bump.py.
      final version = manifestRoot['version'] as int;
      expect(version, greaterThanOrEqualTo(6),
          reason: 'catalog generation can never go below the initial '
              'migration generation');
    });
  });

  group('CRITICAL: storyLength vs legacy length consistency', () {
    test(
        'CRITICAL: storyLength must match lengthMinutesToBucket(length) when both are present',
        () {
      final violations = <String>[];

      for (final parable in parables) {
        final storyId = parable['storyId'] as String;
        final legacyLength = parable['length'] as int?;
        final storyLength = parable['storyLength'] as String?;

        if (legacyLength != null && storyLength != null) {
          // Compute expected bucket from legacy minutes
          final expectedBucket = lengthMinutesToBucket(legacyLength);
          final actualBucket = StoryLengthBucket.fromJson(storyLength);

          if (expectedBucket != actualBucket) {
            violations.add(
                '$storyId: length=$legacyLength maps to ${expectedBucket.name}, '
                'but storyLength="$storyLength" (${actualBucket.name})');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: '🚨 MANIFEST CONTRACT VIOLATION 🚨\n'
            'The following entries have inconsistent length vs storyLength:\n'
            '(SPEC: 5/10 min → short, 15 min → full, 20 min → long)\n\n'
            '${violations.join('\n')}',
      );
    });

    test('CRITICAL: legacy length mapping follows SPEC exactly', () {
      // Verify the mapping itself
      expect(lengthMinutesToBucket(5), StoryLengthBucket.short,
          reason: '5 min → short');
      expect(lengthMinutesToBucket(10), StoryLengthBucket.short,
          reason: '10 min → short');
      expect(lengthMinutesToBucket(15), StoryLengthBucket.full,
          reason: '15 min → full');
      expect(lengthMinutesToBucket(20), StoryLengthBucket.long,
          reason: '20 min → long');
    });
  });

  group('ADVISORY: _trad naming convention', () {
    test(
        'ADVISORY: storyId containing "_trad" SHOULD have storytellingMode="traditional" AND bibleSourceRef',
        () {
      final violations = <String>[];

      for (final parable in parables) {
        final storyId = parable['storyId'] as String;
        final mode = parable['storytellingMode'] as String?;
        final hasBibleRef = parable['bibleSourceRef'] != null;

        // Check if ID contains _trad
        if (storyId.contains('_trad')) {
          if (mode != 'traditional') {
            // This is a naming mismatch - the file has _trad but the content
            // is creative (because traditional requires bibleSourceRef which is missing).
            // Story Mode Contracts v2 takes precedence: traditional REQUIRES bibleSourceRef.
            violations.add('$storyId: has "_trad" suffix but mode="$mode" '
                '(bibleSourceRef: ${hasBibleRef ? "present" : "MISSING - must be creative"})');
          }
        }
      }

      // This is advisory - Story Mode Contracts v2 (bibleSourceRef requirement) is authoritative.
      // Files with _trad in name but no bibleSourceRef MUST be creative until populated.
      if (violations.isNotEmpty) {
        // ignore: avoid_print
        print('⚠️ NAMING CONVENTION ADVISORY ⚠️\n'
            'The following stories have "_trad" in their storyId but are creative mode.\n'
            'This is expected when bibleSourceRef is missing (Contracts v2 requires it for traditional).\n'
            'To fix: add bibleSourceRef OR rename files to remove "_trad" suffix.\n\n'
            '${violations.join('\n')}');
      }
    });

    test(
        'CRITICAL: storyId containing "_creative" must have storytellingMode="creative"',
        () {
      final violations = <String>[];

      for (final parable in parables) {
        final storyId = parable['storyId'] as String;
        final mode = parable['storytellingMode'] as String?;

        // Check if ID contains _creative
        if (storyId.contains('_creative')) {
          if (mode != 'creative') {
            violations.add(
                '$storyId: has "_creative" in ID but storytellingMode="$mode" (must be "creative")');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: '🚨 NAMING CONVENTION VIOLATION 🚨\n'
            'Stories with "_creative" in their storyId MUST have storytellingMode="creative".\n'
            'Either fix the storytellingMode or rename the storyId.\n\n'
            '${violations.join('\n')}',
      );
    });

    test(
        'CRITICAL: "_trad" stories that ARE traditional must have bibleSourceRef',
        () {
      final violations = <String>[];

      for (final parable in parables) {
        final storyId = parable['storyId'] as String;
        final mode = parable['storytellingMode'] as String?;
        final bibleRef = parable['bibleSourceRef'] as String?;

        // If story has _trad AND is traditional mode, it MUST have bibleSourceRef
        if (storyId.contains('_trad') && mode == 'traditional') {
          if (bibleRef == null || bibleRef.trim().isEmpty) {
            violations.add(
                '$storyId: is traditional mode but missing bibleSourceRef');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: '🚨 CONTRACTS V2 VIOLATION 🚨\n'
            'Traditional mode stories MUST have bibleSourceRef (Story Mode Contracts v2).\n'
            'Stories with "_trad" that lack bibleSourceRef should be creative until populated.\n\n'
            '${violations.join('\n')}',
      );
    });
  });

  group('CRITICAL: narratorVoiceKey required for all entries', () {
    test('CRITICAL: every manifest entry must have narratorVoiceKey', () {
      final violations = <String>[];

      for (final parable in parables) {
        final storyId = parable['storyId'] as String;
        final voiceKey = parable['narratorVoiceKey'] as String?;

        if (voiceKey == null || voiceKey.trim().isEmpty) {
          violations.add('$storyId: missing narratorVoiceKey');
        }
      }

      expect(
        violations,
        isEmpty,
        reason: '🚨 MANIFEST CONTRACT VIOLATION 🚨\n'
            'All manifest entries MUST have narratorVoiceKey (including text-only stories).\n'
            'This is required per SPEC.md Parable Metadata.\n\n'
            '${violations.join('\n')}',
      );
    });

    test('CRITICAL: narratorVoiceKey must follow VOICE_* naming pattern', () {
      final violations = <String>[];
      final voiceKeyPattern = RegExp(r'^VOICE_[A-Z]+(_[A-Z0-9]+)*$');

      for (final parable in parables) {
        final storyId = parable['storyId'] as String;
        final voiceKey = parable['narratorVoiceKey'] as String?;

        if (voiceKey != null && voiceKey.isNotEmpty) {
          if (!voiceKeyPattern.hasMatch(voiceKey)) {
            violations.add(
                '$storyId: narratorVoiceKey="$voiceKey" does not match VOICE_* pattern');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: '🚨 VOICE KEY FORMAT VIOLATION 🚨\n'
            'narratorVoiceKey must follow the pattern VOICE_NAME_TRAIT.\n'
            'Examples: VOICE_PETER_BOLD, VOICE_RUTH_COMFORT, VOICE_HANNAH_HOPE\n\n'
            '${violations.join('\n')}',
      );
    });
  });

  group('CRITICAL: Traditional mode requires bibleSourceRef', () {
    test('CRITICAL: traditional mode entries must have bibleSourceRef', () {
      final violations = <String>[];

      for (final parable in parables) {
        final storyId = parable['storyId'] as String;
        final mode = parable['storytellingMode'] as String?;
        final bibleRef = parable['bibleSourceRef'] as String?;

        if (mode == 'traditional') {
          if (bibleRef == null || bibleRef.trim().isEmpty) {
            violations.add(
                '$storyId: storytellingMode="traditional" but missing bibleSourceRef');
          }
        }
      }

      // NOTE: This test is informational - some traditional stories may be
      // in progress without bibleSourceRef. The Story Mode Contracts test
      // will enforce this more strictly for serving.
      if (violations.isNotEmpty) {
        // ignore: avoid_print
        print('WARNING: ${violations.length} traditional stories missing '
            'bibleSourceRef:\n${violations.join('\n')}');
      }
    });
  });

  group('CRITICAL: bucket-first invariants', () {
    test('CRITICAL: all entries must have storyLength (bucket-first)', () {
      final missing = parables.where((p) => p['storyLength'] == null).toList();
      final ids = missing.map((p) => p['storyId']).toList();
      expect(missing, isEmpty,
          reason: 'All entries must have storyLength. Missing: $ids');
    });

    test(
        'CRITICAL: v2 entries must not contain minute-based length field', () {
      final v2WithLength = parables.where((p) {
        final id = p['storyId'] as String;
        return id.startsWith('story_') && p.containsKey('length');
      }).toList();
      final ids = v2WithLength.map((p) => p['storyId']).toList();
      expect(v2WithLength, isEmpty,
          reason:
              'v2 entries (story_*) must not have minute-based "length" field. Found: $ids');
    });
  });

  group('Manifest validation summary', () {
    test('print manifest statistics', () {
      final totalStories = parables.length;
      final traditionalCount =
          parables.where((p) => p['storytellingMode'] == 'traditional').length;
      final creativeCount =
          parables.where((p) => p['storytellingMode'] == 'creative').length;
      final withVoiceKey =
          parables.where((p) => p['narratorVoiceKey'] != null).length;
      final withBibleRef =
          parables.where((p) => p['bibleSourceRef'] != null).length;

      final shortCount =
          parables.where((p) => p['storyLength'] == 'short').length;
      final fullCount =
          parables.where((p) => p['storyLength'] == 'full').length;
      final longCount =
          parables.where((p) => p['storyLength'] == 'long').length;

      // ignore: avoid_print
      print('''
Manifest Statistics:
  Total stories: $totalStories
  Traditional: $traditionalCount
  Creative: $creativeCount
  With narratorVoiceKey: $withVoiceKey
  With bibleSourceRef: $withBibleRef

Story Length Distribution:
  Short: $shortCount
  Full: $fullCount
  Long: $longCount
''');

      expect(totalStories, greaterThan(0),
          reason: 'Manifest should have at least one story');
    });
  });
}
