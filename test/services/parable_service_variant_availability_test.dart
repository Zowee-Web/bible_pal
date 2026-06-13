// Tests `ParableService.getAvailableVariants` enforces the bundled-audio
// availability filter (Layer 1 + Layer 2a): a variant is reported as
// available only when its manifest entry has a non-empty audioFilePath
// AND that path is in the provided bundledAudioPaths set.

import 'package:bible_pal/core/story_length_bucket.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late ParableService service;

  final adultPrefs = UserPreferences(
    kidFriendlyOnly: false,
    bibleTranslation: 'WEB',
    storytellingMode: 'traditional',
    languageStyle: 'WEB',
  );

  // Walk a small list of canonical moods to pick a real, manifest-backed
  // pool. Keeps the tests robust to small content edits in any one mood.
  Future<List<Parable>> loadPool() async {
    const moods = ['hurting', 'joyful', 'weary', 'grateful', 'peaceful'];
    for (final m in moods) {
      final pool = await service.getEligibleParables(
        mood: m,
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      if (pool.isNotEmpty) return pool;
    }
    throw StateError('No eligible parables found in bundled manifest');
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.create();
    // testMode=true → ParableService loads the real bundled manifest.
    service = ParableService(storage, null, true);
  });

  test('returns empty map when bundledAudioPaths is empty', () async {
    final pool = await loadPool();
    final withKey = pool.firstWhere((p) => p.hasBibleStoryKey);
    final result = await service.getAvailableVariants(withKey, <String>{});
    expect(result, isEmpty,
        reason: 'No bundled paths means no variants should be reported');
  });

  test(
      'reports the parable\'s own variant when its audioFilePath is in the '
      'bundled set', () async {
    final pool = await loadPool();
    final withKey = pool.firstWhere(
      (p) =>
          p.hasBibleStoryKey &&
          p.audioFilePath != null &&
          p.audioFilePath!.isNotEmpty &&
          p.storyLength != null,
    );
    final result = await service
        .getAvailableVariants(withKey, <String>{withKey.audioFilePath!});
    expect(result.containsKey(withKey.storyLength!), isTrue);
    expect(result[withKey.storyLength!], contains(withKey.languageStyle));
  });

  test(
      'excludes sibling variants whose audioFilePath is missing from '
      'bundledAudioPaths', () async {
    final pool = await loadPool();
    // Find a parable that actually has at least one sibling variant in
    // the manifest with a distinct audioFilePath.
    Parable? probe;
    for (final p in pool) {
      if (!p.hasBibleStoryKey ||
          p.audioFilePath == null ||
          p.audioFilePath!.isEmpty ||
          p.storyLength == null) {
        continue;
      }
      final hasSiblingWithDistinctPath = pool.any((q) =>
          q.bibleStoryKey == p.bibleStoryKey &&
          q.storytellingMode == p.storytellingMode &&
          q.kidFriendly == p.kidFriendly &&
          q.audioFilePath != null &&
          q.audioFilePath!.isNotEmpty &&
          q.audioFilePath != p.audioFilePath);
      if (hasSiblingWithDistinctPath) {
        probe = p;
        break;
      }
    }
    if (probe == null) {
      // Fixture not present in this slice of the manifest — non-failure
      // since the filter still applies if/when such siblings exist.
      return;
    }

    final result = await service
        .getAvailableVariants(probe, <String>{probe.audioFilePath!});

    // Result must include the probe's own (length, lang).
    expect(result[probe.storyLength!], contains(probe.languageStyle));

    // For every sibling with a different audioFilePath, its (length, lang)
    // must not appear in the result unless that same (length, lang) is
    // also the probe's. With only the probe's path bundled, only the
    // probe's (length, lang) should be reported.
    final siblings = pool.where((q) =>
        q.bibleStoryKey == probe!.bibleStoryKey &&
        q.storytellingMode == probe.storytellingMode &&
        q.kidFriendly == probe.kidFriendly &&
        q.audioFilePath != probe.audioFilePath);
    for (final sib in siblings) {
      if (sib.storyLength == probe.storyLength &&
          sib.languageStyle == probe.languageStyle) {
        // Same (length, lang) as the probe — fine to share.
        continue;
      }
      final reportedLangs = result[sib.storyLength] ?? <String>{};
      expect(reportedLangs.contains(sib.languageStyle), isFalse,
          reason:
              'Unbundled sibling ${sib.storyId} should not appear in result');
    }
  });

  test('filters out manifest entries with null or empty audioFilePath',
      () async {
    final pool = await loadPool();
    // Find a probe whose family includes both a non-empty path entry AND
    // at least one empty / null path entry.
    Parable? probe;
    Set<String> allNonEmptyPaths = {};
    for (final p in pool) {
      if (!p.hasBibleStoryKey || p.storyLength == null) continue;
      final family = pool.where((q) =>
          q.bibleStoryKey == p.bibleStoryKey &&
          q.storytellingMode == p.storytellingMode &&
          q.kidFriendly == p.kidFriendly);
      final hasEmpty = family
          .any((q) => q.audioFilePath == null || q.audioFilePath!.isEmpty);
      final hasNonEmpty = family
          .any((q) => q.audioFilePath != null && q.audioFilePath!.isNotEmpty);
      if (hasEmpty && hasNonEmpty) {
        probe = p;
        allNonEmptyPaths = family
            .where((q) =>
                q.audioFilePath != null && q.audioFilePath!.isNotEmpty)
            .map((q) => q.audioFilePath!)
            .toSet();
        break;
      }
    }
    if (probe == null) {
      // Fixture not present — defensive no-op.
      return;
    }

    // Generously bundle every non-empty sibling path. The empty-path
    // entries must still be filtered out by the audioFilePath check.
    final result = await service.getAvailableVariants(probe, allNonEmptyPaths);

    // For each (length, lang) reported, there must be at least one
    // sibling in the manifest with a non-empty audioFilePath backing it.
    final family = pool.where((q) =>
        q.bibleStoryKey == probe!.bibleStoryKey &&
        q.storytellingMode == probe.storytellingMode &&
        q.kidFriendly == probe.kidFriendly);
    for (final entry in result.entries) {
      for (final lang in entry.value) {
        final backing = family.where((q) =>
            q.storyLength == entry.key &&
            q.languageStyle == lang &&
            q.audioFilePath != null &&
            q.audioFilePath!.isNotEmpty);
        expect(backing, isNotEmpty,
            reason:
                'Variant ${entry.key}/$lang has no non-empty-path backer');
      }
    }
  });
}
