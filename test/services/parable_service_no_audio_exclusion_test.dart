// Tests for the audio-availability safety guard in mood flow.
//
// Background:
// Manifest entries can carry an empty audioFilePath when a story's
// metadata is committed before its audio is generated. Mood selection
// must NOT serve those stories — the player would call getAudioFile,
// the resolver would silently fail through cache → asset → R2 with an
// empty path, and the user would see a misleading "needs internet"
// SnackBar with no story content.
//
// These tests pin the contract:
//   1. getEligibleParables NEVER returns an entry whose audioFilePath
//      is empty or null.
//   2. selectParable NEVER returns an entry whose audioFilePath is
//      empty or null (even with mood expansion).
//   3. getAudioFile treats null and empty-string the same.
//   4. previewBibleStoryKey does NOT consider empty-audio entries
//      (so the post-preview hint cannot constrain selectParable into
//      a no-audio variant).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/core/story_length_bucket.dart';

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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.create();
    service = ParableService(storage, null, true);
  });

  group('Audio-availability safety guard', () {
    // Run the eligibility assertion across every allowed mood and both
    // length buckets that mood flow uses. The bundled manifest contains
    // entries with empty audioFilePath in the 1121-1247 range; this test
    // ensures none of them leak into the eligibility pool.
    const allowedMoods = [
      'joyful', 'grateful', 'weary', 'anxious', 'hurting',
      'brave_courage', 'calm_peaceful', 'encouraging',
    ];

    for (final mood in allowedMoods) {
      for (final bucket in const [
        StoryLengthBucket.short,
        StoryLengthBucket.full,
      ]) {
        test(
            'getEligibleParables(mood: $mood, bucket: ${bucket.name}) '
            'never returns an entry with empty audioFilePath', () async {
          final eligible = await service.getEligibleParables(
            mood: mood,
            lengthBucket: bucket,
            userPrefs: adultPrefs,
          );

          for (final p in eligible) {
            final path = p.audioFilePath ?? '';
            expect(path.isNotEmpty, true,
                reason: 'Eligibility leak: ${p.storyId} "${p.title}" '
                    '(mood=${p.mood}, bucket=${bucket.name}) has '
                    'audioFilePath="$path". Mood flow must exclude '
                    'entries without audio so the player does not '
                    'surface a misleading load error.');
          }
        });
      }
    }

    test(
        'selectParable returns null OR an entry with non-empty '
        'audioFilePath for every allowed mood', () async {
      for (final mood in allowedMoods) {
        for (final bucket in const [
          StoryLengthBucket.short,
          StoryLengthBucket.full,
        ]) {
          final selected = await service.selectParable(
            mood: mood,
            lengthBucket: bucket,
            userPrefs: adultPrefs,
          );
          if (selected == null) continue;
          final path = selected.audioFilePath ?? '';
          expect(path.isNotEmpty, true,
              reason: 'selectParable(mood: $mood, bucket: ${bucket.name}) '
                  'returned ${selected.storyId} "${selected.title}" with '
                  'empty audioFilePath. Mood-expansion engine must not '
                  'pick no-audio stories.');
        }
      }
    });

    test(
        'previewBibleStoryKey does not key off entries with empty '
        'audioFilePath', () async {
      // Build the set of bibleStoryKeys that ONLY have no-audio variants.
      // If previewBibleStoryKey returns one of those, it means the empty-
      // audio guard is missing from the preview path.
      final all = await service.getAllTraditionalParables();

      final byKey = <String, List<Parable>>{};
      for (final p in all) {
        final k = p.bibleStoryKey;
        if (k == null) continue;
        byKey.putIfAbsent(k, () => []).add(p);
      }
      final noAudioOnlyKeys = <String>{
        for (final entry in byKey.entries)
          if (entry.value.every((p) => (p.audioFilePath ?? '').isEmpty))
            entry.key,
      };

      for (final mood in allowedMoods) {
        final preview = await service.previewBibleStoryKey(
          mood: mood,
          userPrefs: adultPrefs,
        );
        if (preview == null) continue;
        expect(noAudioOnlyKeys, isNot(contains(preview)),
            reason: 'previewBibleStoryKey($mood) returned $preview, but '
                'every variant of that key has empty audioFilePath. '
                'The preview path must respect the same audio-availability '
                'guard as eligibility selection.');
      }
    });

    test('getAudioFile returns null for empty audioFilePath', () async {
      final emptyAudio = Parable(
        storyId: 'synth_empty',
        title: 'Synthetic',
        mood: 'joyful',
        length: 5,
        storytellingMode: 'traditional',
        kidFriendly: false,
        bibleSourceRef: 'Luke 1:1-4',
        audioFilePath: '',
      );
      final result = await service.getAudioFile(emptyAudio);
      expect(result, isNull,
          reason: 'getAudioFile must treat empty audioFilePath as missing '
              '(parity with the null check). Without this guard, the '
              'three-tier resolver attempts a malformed path lookup and '
              'surfaces a misleading offline-cache error.');
    });

    test('getAudioFile returns null for null audioFilePath (regression)',
        () async {
      final nullAudio = Parable(
        storyId: 'synth_null',
        title: 'Synthetic Null',
        mood: 'joyful',
        length: 5,
        storytellingMode: 'traditional',
        kidFriendly: false,
        bibleSourceRef: 'Luke 1:1-4',
        // audioFilePath omitted -> null
      );
      final result = await service.getAudioFile(nullAudio);
      expect(result, isNull,
          reason: 'getAudioFile must continue to short-circuit on null '
              'audioFilePath (pre-existing behavior; test guards against '
              'regression while we tighten the empty-string check).');
    });
  });
}
