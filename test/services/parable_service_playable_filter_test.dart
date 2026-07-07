import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/core/story_length_bucket.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Playable-audio availability gate (2026-07-06 streaming fix).
///
/// A streaming (slim) build bundles no story audio; playability comes from
/// the union of asset-bundled paths and R2-verified paths
/// (assets/stories/r2_verified_paths.json). These tests pin:
///   1. the default (no injected set) keeps legacy unfiltered behavior, so
///      every pre-existing selection test stays valid;
///   2. an injected playable set filters getEligibleParables to exactly the
///      variants whose audio the build can play;
///   3. previewBibleStoryKey honors the same gate (no preview/selection
///      mismatch — framing story A, playing story B);
///   4. the shipped r2_verified_paths.json asset is structurally sound.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ParableService service;
  late StorageService storage;

  final adultPrefs = UserPreferences(
    kidFriendlyOnly: false,
    bibleTranslation: 'WEB',
    storytellingMode: 'traditional',
  );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.create();
    service = ParableService(storage, null, true); // testMode
  });

  tearDown(() {
    service.playablePathsForTesting = null;
  });

  group('playable-audio gate — getEligibleParables', () {
    test('no injected set → legacy unfiltered behavior', () async {
      service.playablePathsForTesting = null;
      final eligible = await service.getEligibleParables(
        mood: 'anxious',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      expect(eligible, isNotEmpty,
          reason: 'default (null) playable set must not filter anything');
    });

    test('injected set filters pool to playable variants only', () async {
      // Baseline: unfiltered pool for this mood/length.
      final unfiltered = await service.getEligibleParables(
        mood: 'anxious',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      expect(unfiltered.length, greaterThan(1),
          reason: 'need >1 candidates for a meaningful filter test');

      // Inject a playable set containing exactly ONE candidate's audio path.
      final keep = unfiltered.firstWhere(
          (p) => p.audioFilePath != null && p.audioFilePath!.isNotEmpty);
      service.playablePathsForTesting = {keep.audioFilePath!};

      final filtered = await service.getEligibleParables(
        mood: 'anxious',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      expect(filtered.map((p) => p.storyId), [keep.storyId],
          reason: 'only the story whose audio is playable may survive');
    });

    test('empty-audioFilePath entries are excluded when gate active',
        () async {
      // With ANY non-null set, entries that have no audio registered can
      // never play and must be excluded.
      service.playablePathsForTesting = {'nonexistent/path.mp3'};
      final filtered = await service.getEligibleParables(
        mood: 'anxious',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      expect(filtered, isEmpty,
          reason: 'no manifest entry matches the injected playable set');
    });
  });

  group('playable-audio gate — previewBibleStoryKey', () {
    test('preview only names stories the selector can play', () async {
      final unfiltered = await service.getEligibleParables(
        mood: 'anxious',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      final keep = unfiltered.firstWhere((p) =>
          p.audioFilePath != null &&
          p.audioFilePath!.isNotEmpty &&
          p.bibleStoryKey != null);
      service.playablePathsForTesting = {keep.audioFilePath!};

      final key = await service.previewBibleStoryKey(
        mood: 'anxious',
        userPrefs: adultPrefs,
      );
      expect(key, keep.bibleStoryKey,
          reason: 'preview must resolve to the one playable story');
    });
  });

  group('getRegisteredVariants — hybrid chip data', () {
    test('registered ⊇ playable: includes variants regardless of set',
        () async {
      final unfiltered = await service.getEligibleParables(
        mood: 'anxious',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      final sample = unfiltered.firstWhere((p) =>
          p.audioFilePath != null && p.audioFilePath!.isNotEmpty);

      final registered = await service.getRegisteredVariants(sample);
      expect(registered, isNotEmpty,
          reason: 'a story with audio must have >=1 registered variant');

      // Playable with an EMPTY set must be empty…
      final playableEmpty =
          await service.getAvailableVariants(sample, const <String>{});
      expect(playableEmpty, isEmpty);
      // …while registered ignores playability entirely — this is exactly
      // the hidden-vs-greyed split the hybrid chips depend on.
      final playableAll = await service.getAvailableVariants(
          sample, {sample.audioFilePath!});
      for (final entry in playableAll.entries) {
        expect(registered[entry.key], containsAll(entry.value),
            reason: 'every playable variant must also be registered');
      }
    });
  });

  group('r2_verified_paths.json asset', () {
    test('loads, is well-formed, and matches its own count', () async {
      final raw =
          await rootBundle.loadString('assets/stories/r2_verified_paths.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final paths = (decoded['paths'] as List<dynamic>).cast<String>();
      expect(paths, isNotEmpty);
      expect(decoded['count'], paths.length,
          reason: 'count field must match paths length');
      for (final p in paths) {
        expect(p.endsWith('.mp3'), true, reason: 'non-mp3 path: $p');
        expect(p.startsWith('traditional/') || p.startsWith('kids/'), true,
            reason: 'unexpected path root: $p');
        expect(p.contains('..'), false, reason: 'path traversal: $p');
      }
      expect(paths.toSet().length, paths.length,
          reason: 'duplicate paths in r2_verified_paths.json');
    });

    test('every verified path is referenced by a story manifest', () async {
      final raw =
          await rootBundle.loadString('assets/stories/r2_verified_paths.json');
      final verified =
          ((jsonDecode(raw) as Map<String, dynamic>)['paths'] as List<dynamic>)
              .cast<String>()
              .toSet();

      // Collect referenced audio paths from BOTH manifests — the kid lane
      // references some paths (reflections, Longs) only via
      // kids_manifest.json, mirroring what the R2 drift audit collects.
      final referenced = <String>{};
      final manifestRaw =
          await rootBundle.loadString('assets/stories/manifest.json');
      final manifest = jsonDecode(manifestRaw) as Map<String, dynamic>;
      for (final p in manifest['parables'] as List<dynamic>) {
        final m = p as Map<String, dynamic>;
        final a = m['audioFilePath'] as String?;
        final r = m['reflectionAudioPath'] as String?;
        if (a != null && a.isNotEmpty) referenced.add(a);
        if (r != null && r.isNotEmpty) referenced.add(r);
      }
      // kids_manifest.json is not a declared rootBundle asset — read it
      // from the repo checkout (tests run from the project root).
      final kidsRaw =
          File('assets/stories/kids_manifest.json').readAsStringSync();
      final kids = jsonDecode(kidsRaw) as Map<String, dynamic>;
      for (final p in (kids['stories'] as List<dynamic>)) {
        for (final v in (p as Map<String, dynamic>).values) {
          if (v is String && v.endsWith('.mp3')) referenced.add(v);
        }
      }

      final orphans = verified.difference(referenced);
      expect(orphans, isEmpty,
          reason: 'r2_verified_paths.json lists paths no manifest entry '
              'references — regenerate it after manifest changes: '
              '${orphans.take(5).toList()}');
    });
  });
}
