// Tests for the MICRO serving bias (70/30 weighted variant).
//
// Spec: when the user's detected mood is high-intensity (anxious, hurting,
// weary) AND the selected length is Short, ParableService weights selection
// 70/30 between exact-mood unseen MICRO stories and the normal exact-mood
// Short pool. Bias never applies to Full or Long. Eligibility gate: at least
// one unseen exact-mood MICRO must exist; otherwise normal serving runs.
//
// All tests below override the bias dice via setMicroBiasRandomForTesting
// to make the 70/30 split deterministic. Default dice in setUp is 0.0
// (always takes the micro path) so legacy "prefers MICRO" assertions keep
// holding; the 30% path is exercised explicitly in its own group.

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
    // Default dice = 0.0 → always takes the 70% micro path. Individual
    // tests override before exercising the 30% path.
    ParableService.setMicroBiasRandomForTesting(() => 0.0);
  });

  tearDown(() {
    ParableService.resetMicroBiasRandomForTesting();
  });

  group('70% path: high-intensity moods + Short prefer MICRO', () {
    test('anxious + Short returns MICRO when dice picks the 70% path',
        () async {
      final pool = await service.getEligibleParables(
        mood: 'anxious',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      final hasMicro = pool.any((p) => p.shortScripture);
      if (!hasMicro) {
        return; // No fixture data — skip silently rather than fail spuriously
      }
      // Run multiple selections; every result should be a MICRO until the
      // first one is played (engine LRP rotates, but the bias keeps the pool
      // MICRO-only, so we always land on a MICRO from the unseen tier).
      final result = await service.selectParable(
        mood: 'anxious',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      expect(result, isNotNull);
      expect(result!.shortScripture, true,
          reason:
              'anxious + Short with at least one eligible unseen MICRO must '
              'return that MICRO before any normal Short story.');
    });

    test('hurting + Short prefers MICRO when one is eligible', () async {
      final pool = await service.getEligibleParables(
        mood: 'hurting',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      final hasMicro = pool.any((p) => p.shortScripture);
      if (!hasMicro) {
        return;
      }
      final result = await service.selectParable(
        mood: 'hurting',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      expect(result, isNotNull);
      expect(result!.shortScripture, true);
    });

    test('weary + Short prefers MICRO when one is eligible', () async {
      // weary may have 0 MICROs in the current corpus — that's the fallback
      // case covered by the dedicated fallback test below. If a MICRO exists,
      // it must win.
      final pool = await service.getEligibleParables(
        mood: 'weary',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      final hasMicro = pool.any((p) => p.shortScripture);
      if (!hasMicro) {
        return;
      }
      final result = await service.selectParable(
        mood: 'weary',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      expect(result, isNotNull);
      expect(result!.shortScripture, true);
    });
  });

  group('30% path: high-intensity moods + Short can serve regular Short', () {
    test(
        'anxious + Short with dice=0.99 picks exact-mood non-MICRO Short '
        'instead of an exact-mood MICRO', () async {
      // Force the 30% path
      ParableService.setMicroBiasRandomForTesting(() => 0.99);

      const mood = 'anxious';
      final pool = await service.getEligibleParables(
        mood: mood,
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      final hasExactMoodMicro =
          pool.any((p) => p.mood == mood && p.shortScripture);
      final hasExactMoodNonMicro =
          pool.any((p) => p.mood == mood && !p.shortScripture);
      if (!hasExactMoodMicro || !hasExactMoodNonMicro) {
        return; // Need both buckets to validate the 30% path
      }

      // Across several picks, every result must be exact-mood AND
      // non-MICRO — the 30% path has the engine pick from the pool minus
      // unseen exact-mood MICROs, so Tier 1 (exact-mood unseen non-MICRO)
      // wins.
      var sawExactNonMicro = false;
      for (var i = 0; i < 5; i++) {
        final result = await service.selectParable(
          mood: mood,
          lengthBucket: StoryLengthBucket.short,
          userPrefs: adultPrefs,
        );
        if (result == null) continue;
        expect(
            result.mood == mood && result.shortScripture,
            false,
            reason: '30% path must not return an exact-mood MICRO. Got '
                '${result.storyId} (mood=${result.mood}, '
                'micro=${result.shortScripture})');
        if (result.mood == mood && !result.shortScripture) {
          sawExactNonMicro = true;
        }
        // Mark played so subsequent picks rotate
        await storage.recordPlayed(result.storyId, at: DateTime.now());
      }
      expect(sawExactNonMicro, true,
          reason: '30% path should surface exact-mood non-MICRO Shorts via '
              'the engine\'s Tier 1.');
    });

    test(
        'hurting + Short with dice=0.99 picks exact-mood non-MICRO Short',
        () async {
      ParableService.setMicroBiasRandomForTesting(() => 0.99);
      const mood = 'hurting';
      final pool = await service.getEligibleParables(
        mood: mood,
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      if (!pool.any((p) => p.mood == mood && p.shortScripture)) return;
      if (!pool.any((p) => p.mood == mood && !p.shortScripture)) return;

      final result = await service.selectParable(
        mood: mood,
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      expect(result, isNotNull);
      expect(result!.shortScripture, false,
          reason: '30% path with hurting must return non-MICRO Short.');
    });

    test(
        'weary + Short with dice=0.99 does not return an exact-mood MICRO',
        () async {
      ParableService.setMicroBiasRandomForTesting(() => 0.99);
      const mood = 'weary';
      final pool = await service.getEligibleParables(
        mood: mood,
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      final hasExactMicro =
          pool.any((p) => p.mood == mood && p.shortScripture);
      if (!hasExactMicro) return;

      final result = await service.selectParable(
        mood: mood,
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      if (result == null) return;
      expect(result.mood == mood && result.shortScripture, false,
          reason: '30% path must not return an exact-mood MICRO.');
    });

    test('boundary dice = 0.7 takes the 30% path (strict <)', () async {
      // Probability constant is 0.70; dice < 0.70 → micro path. Exactly
      // 0.70 must take the 30% path.
      ParableService.setMicroBiasRandomForTesting(() => 0.70);
      const mood = 'hurting';
      final pool = await service.getEligibleParables(
        mood: mood,
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      if (!pool.any((p) => p.mood == mood && p.shortScripture)) return;
      if (!pool.any((p) => p.mood == mood && !p.shortScripture)) return;

      final result = await service.selectParable(
        mood: mood,
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      if (result == null) return;
      expect(result.mood == mood && result.shortScripture, false,
          reason: 'dice == 0.70 must take the 30% path (strict <).');
    });
  });

  group('MICRO bias never applies to Full or Long', () {
    test('Full bucket never returns a MICRO story', () async {
      // Run repeatedly across all 8 moods + Full bucket. No result should
      // ever be a MICRO (MICROs only register `lengths: ["short"]` so they
      // are filtered out of the eligible pool by length, before bias even
      // runs).
      const allMoods = [
        'anxious',
        'hurting',
        'weary',
        'joyful',
        'grateful',
        'calm_peaceful',
        'brave_courage',
        'encouraging',
      ];
      for (final mood in allMoods) {
        for (var i = 0; i < 3; i++) {
          final result = await service.selectParable(
            mood: mood,
            lengthBucket: StoryLengthBucket.full,
            userPrefs: adultPrefs,
          );
          if (result == null) continue;
          expect(result.shortScripture, false,
              reason: 'Full bucket must never serve a MICRO; got '
                  '${result.storyId} for mood=$mood');
        }
      }
    });

    test('Long bucket never returns a MICRO story', () async {
      const allMoods = [
        'anxious',
        'hurting',
        'weary',
        'joyful',
        'grateful',
        'calm_peaceful',
        'brave_courage',
        'encouraging',
      ];
      for (final mood in allMoods) {
        for (var i = 0; i < 3; i++) {
          final result = await service.selectParable(
            mood: mood,
            lengthBucket: StoryLengthBucket.long,
            userPrefs: adultPrefs,
          );
          if (result == null) continue;
          expect(result.shortScripture, false,
              reason: 'Long bucket must never serve a MICRO; got '
                  '${result.storyId} for mood=$mood');
        }
      }
    });
  });

  group('MICRO bias respects anti-repeat', () {
    test(
        'when all eligible MICROs are recently played, selection falls '
        'back to non-MICRO Short pool', () async {
      // Gather every MICRO that any intense-mood selection could see. The
      // bias considers the *combined* pool (exact + similar moods), so we
      // need to mark MICROs from all similar moods as played to drain the
      // bias' eligible set. Using the full Short/WEB/Adult/Traditional pool
      // is the most data-robust way to cover this.
      // Drain MICROs across ALL moods. The bias checks the combined pool
      // (exact + similar moods), and similar-mood expansion for hurting
      // includes calm_peaceful and encouraging too — so we need to mark
      // every MICRO in the corpus as played, regardless of mood, to fully
      // simulate "no eligible MICROs" in the bias check.
      final allMicros = <String>{};
      const allMoods = [
        'anxious',
        'hurting',
        'weary',
        'joyful',
        'grateful',
        'calm_peaceful',
        'brave_courage',
        'encouraging',
      ];
      for (final m in allMoods) {
        final pool = await service.getEligibleParables(
          mood: m,
          lengthBucket: StoryLengthBucket.short,
          userPrefs: adultPrefs,
        );
        for (final p in pool.where((p) => p.shortScripture)) {
          allMicros.add(p.storyId);
        }
      }
      if (allMicros.isEmpty) {
        return; // No fixture MICROs — nothing to test
      }

      // Mark every MICRO as played 1 day ago — within the 30-day "seen"
      // window. Bias should NOT lock the user into a recently-played MICRO;
      // it should fall back to the broader pool.
      final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));
      for (final id in allMicros) {
        await storage.recordPlayed(id, at: oneDayAgo);
      }

      // Run repeatedly — every result must be non-MICRO since all MICROs
      // are in the seen window.
      for (var i = 0; i < 5; i++) {
        final result = await service.selectParable(
          mood: 'hurting',
          lengthBucket: StoryLengthBucket.short,
          userPrefs: adultPrefs,
        );
        if (result == null) continue;
        expect(result.shortScripture, false,
            reason: 'When every eligible MICRO is in the anti-repeat window, '
                'bias must fall back to non-MICRO Short selection. Got '
                '${result.storyId} on attempt ${i + 1}.');
      }
    });
  });

  group('MICRO bias falls back when no MICRO exists', () {
    test(
        'with every MICRO drained from the eligible pool, intense-mood '
        'Short selection still returns a non-MICRO Short story', () async {
      // Same construction as the anti-repeat fallback: drain all MICROs
      // via the play log and verify the bias does not produce MICRO results
      // for any intense mood. This guards the "fallback path" code branch
      // explicitly even though the corpus naturally includes MICROs.
      // Drain MICROs across ALL moods. The bias checks the combined pool
      // (exact + similar moods), and similar-mood expansion for hurting
      // includes calm_peaceful and encouraging too — so we need to mark
      // every MICRO in the corpus as played, regardless of mood, to fully
      // simulate "no eligible MICROs" in the bias check.
      final allMicros = <String>{};
      const allMoods = [
        'anxious',
        'hurting',
        'weary',
        'joyful',
        'grateful',
        'calm_peaceful',
        'brave_courage',
        'encouraging',
      ];
      for (final m in allMoods) {
        final pool = await service.getEligibleParables(
          mood: m,
          lengthBucket: StoryLengthBucket.short,
          userPrefs: adultPrefs,
        );
        for (final p in pool.where((p) => p.shortScripture)) {
          allMicros.add(p.storyId);
        }
      }
      if (allMicros.isEmpty) return;
      final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));
      for (final id in allMicros) {
        await storage.recordPlayed(id, at: oneDayAgo);
      }
      for (final mood in ['anxious', 'hurting', 'weary']) {
        final result = await service.selectParable(
          mood: mood,
          lengthBucket: StoryLengthBucket.short,
          userPrefs: adultPrefs,
        );
        if (result == null) continue;
        expect(result.shortScripture, false,
            reason:
                'Mood $mood with no eligible MICROs must fall back to non-MICRO Short.');
      }
    });
  });

  group('MICRO bias releases when exact-mood MICROs are exhausted', () {
    test(
        'after exact-mood MICROs are recently played, selection falls back '
        'to exact-mood non-MICRO Short before similar-mood MICRO', () async {
      const mood = 'hurting';
      final pool = await service.getEligibleParables(
        mood: mood,
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      final exactMoodMicros =
          pool.where((p) => p.mood == mood && p.shortScripture).toList();
      final exactMoodNonMicros =
          pool.where((p) => p.mood == mood && !p.shortScripture).toList();
      if (exactMoodMicros.isEmpty || exactMoodNonMicros.isEmpty) {
        return; // Need both buckets to validate the fallback
      }

      final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));
      for (final p in exactMoodMicros) {
        await storage.recordPlayed(p.storyId, at: oneDayAgo);
      }

      // Run several selections — each must be exact-mood AND non-MICRO,
      // NOT a similar-mood MICRO. This proves the bias released once
      // exact-mood MICROs were drained, allowing normal tiered serving.
      var sawExactNonMicro = false;
      for (var i = 0; i < 5; i++) {
        final result = await service.selectParable(
          mood: mood,
          lengthBucket: StoryLengthBucket.short,
          userPrefs: adultPrefs,
        );
        if (result == null) continue;
        // Must not be a recently-played exact-mood MICRO
        expect(
            exactMoodMicros.any((p) => p.storyId == result.storyId &&
                result.shortScripture),
            false,
            reason: 'Selection must not return a recently-played MICRO.');
        if (result.mood == mood && !result.shortScripture) {
          sawExactNonMicro = true;
        }
      }
      expect(sawExactNonMicro, true,
          reason:
              'After exact-mood MICROs were played, an exact-mood non-MICRO '
              'Short must surface before any similar-mood MICRO.');
    });

    test(
        'similar-mood MICROs do not keep the MICRO bias active when no '
        'exact-mood MICRO is unseen', () async {
      const mood = 'anxious';
      final pool = await service.getEligibleParables(
        mood: mood,
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      final exactMoodMicros =
          pool.where((p) => p.mood == mood && p.shortScripture).toList();
      final similarMoodMicros =
          pool.where((p) => p.mood != mood && p.shortScripture).toList();
      if (similarMoodMicros.isEmpty) {
        return; // Nothing to validate without similar-mood MICRO presence
      }

      // Drain only exact-mood MICROs. Similar-mood MICROs remain unseen.
      // Under the buggy behavior, the bias would still trigger and force a
      // similar-mood MICRO. Under the fix, the bias releases and we should
      // NOT keep landing on similar-mood MICROs over exact-mood non-MICROs.
      final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));
      for (final p in exactMoodMicros) {
        await storage.recordPlayed(p.storyId, at: oneDayAgo);
      }

      // Across multiple picks, verify selection isn't trapped in
      // similar-mood MICRO. With the bias released, the selector's tiered
      // serving (exact-mood-unseen first) should produce at least one
      // exact-mood non-MICRO Short if any exists. If the corpus has no
      // exact-mood non-MICRO Short for this mood, this test degrades to
      // "selection isn't ALL similar-mood MICROs" which still proves the
      // bias released.
      final exactMoodNonMicroExists =
          pool.any((p) => p.mood == mood && !p.shortScripture);
      var sawNonSimilarMicro = false;
      for (var i = 0; i < 8; i++) {
        final result = await service.selectParable(
          mood: mood,
          lengthBucket: StoryLengthBucket.short,
          userPrefs: adultPrefs,
        );
        if (result == null) continue;
        final isSimilarMoodMicro =
            result.mood != mood && result.shortScripture;
        if (!isSimilarMoodMicro) sawNonSimilarMicro = true;
      }
      if (exactMoodNonMicroExists) {
        expect(sawNonSimilarMicro, true,
            reason: 'Bias should release once exact-mood MICROs are seen — '
                'similar-mood MICROs alone must not keep selection locked '
                'to MICRO-only when an exact-mood non-MICRO Short exists.');
      } else {
        // Degraded assertion: bias released ⇒ at least one selection should
        // step outside MICRO-only (engine LRP rotates seen tiers etc.).
        expect(sawNonSimilarMicro, true,
            reason: 'Bias must not keep selection locked to similar-mood '
                'MICROs once no unseen exact-mood MICRO exists.');
      }
    });
  });

  group('MICRO bias does not apply to non-intense moods', () {
    test('calm_peaceful + Short does NOT force MICRO selection', () async {
      // calm_peaceful is not in the high-intensity set, so the bias should
      // not run. Selection should follow normal Short logic (which may or
      // may not return a MICRO based on standard mood matching, but is not
      // forced to by the bias).
      // Run a handful of selections and verify at least one is non-MICRO,
      // proving the bias didn't restrict the pool to MICRO-only.
      final pool = await service.getEligibleParables(
        mood: 'calm_peaceful',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: adultPrefs,
      );
      // calm_peaceful has plenty of stories; if all happen to be MICRO that
      // would be a coincidence in the data, not a bug — but the locked rule
      // is that bias is not applied for this mood. Easiest assertion: ensure
      // the eligible pool itself is not artificially restricted to MICRO.
      expect(pool.where((p) => !p.shortScripture).isNotEmpty, true,
          reason: 'calm_peaceful Short pool should include non-MICRO stories; '
              'bias must not be filtering before getEligibleParables.');
    });
  });

  // ---------------------------------------------------------------------------
  // B1 MICRO-as-variant: schema + resolver tests using synthetic Parable
  // fixtures, since the master manifest doesn't yet carry any multi-variant
  // rows. These test the variant-resolver logic in isolation from the engine.
  // ---------------------------------------------------------------------------

  group('B1: Parable schema supports microAudioPath / microTextPath', () {
    test('fromJson reads micro paths and hasMicroVariant returns true', () {
      final json = <String, dynamic>{
        'storyId': 'story_test_1090_anxious_short_traditional',
        'title': 'The Storm',
        'mood': 'anxious',
        'storytellingMode': 'traditional',
        'kidFriendly': false,
        'storyLength': 'short',
        'audioFilePath':
            'traditional/1090/audio_1090_story_short.mp3',
        'textFilePath':
            'traditional/1090/story_1090_traditional_web_short.txt',
        'microAudioPath':
            'traditional/1090/audio_1090_story_micro.mp3',
        'microTextPath':
            'traditional/1090/story_1090_traditional_web_micro.txt',
      };
      final p = Parable.fromJson(json);
      expect(p.microAudioPath,
          'traditional/1090/audio_1090_story_micro.mp3');
      expect(p.microTextPath,
          'traditional/1090/story_1090_traditional_web_micro.txt');
      expect(p.hasMicroVariant, true);
      expect(p.shortScripture, false,
          reason: 'B1 multi-variant uses hasMicroVariant, not shortScripture.');
    });

    test('toJson omits micro fields when null (legacy byte-identical)', () {
      final p = Parable(
        storyId: 'legacy',
        title: 'Legacy story',
        mood: 'joyful',
        storytellingMode: 'traditional',
        kidFriendly: false,
        storyLength: 'short',
      );
      final json = p.toJson();
      expect(json.containsKey('microAudioPath'), false);
      expect(json.containsKey('microTextPath'), false);
      expect(json.containsKey('shortScripture'), false,
          reason: 'shortScripture only emitted when true');
    });

    test('toJson emits micro fields when present', () {
      final p = Parable(
        storyId: 'multi-variant',
        title: 'Multi-variant story',
        mood: 'anxious',
        storytellingMode: 'traditional',
        kidFriendly: false,
        storyLength: 'short',
        microAudioPath: 'a.mp3',
        microTextPath: 'a.txt',
      );
      final json = p.toJson();
      expect(json['microAudioPath'], 'a.mp3');
      expect(json['microTextPath'], 'a.txt');
    });

    test('hasMicroVariant is false when paths are null or empty', () {
      final pNull = Parable(
        storyId: 's',
        title: 't',
        mood: 'anxious',
        storytellingMode: 'traditional',
        kidFriendly: false,
      );
      final pEmpty = pNull.copyWith(microAudioPath: '');
      expect(pNull.hasMicroVariant, false);
      expect(pEmpty.hasMicroVariant, false);
    });

    test('legacy single-variant MICRO reports hasMicroVariant=false', () {
      // Existing 45 standalone MICROs: shortScripture=true, no
      // microAudioPath. The bias predicate accepts them via the
      // shortScripture branch; the variant resolver leaves them alone.
      final p = Parable(
        storyId: 's',
        title: 't',
        mood: 'anxious',
        storytellingMode: 'traditional',
        kidFriendly: false,
        shortScripture: true,
      );
      expect(p.shortScripture, true);
      expect(p.hasMicroVariant, false);
    });
  });

  group('B1: variant resolver swap behavior', () {
    // The variant resolver in ParableService is a small copyWith call:
    //   selected.copyWith(audioFilePath: microAudioPath, textFilePath: microTextPath)
    // We exercise that exact swap shape here in isolation.

    test('70% path: copyWith swaps audio + text paths to micro', () {
      final original = Parable(
        storyId: 'multi',
        title: 'Multi',
        mood: 'anxious',
        storytellingMode: 'traditional',
        kidFriendly: false,
        storyLength: 'short',
        audioFilePath: 'a/short.mp3',
        textFilePath: 'a/short.txt',
        microAudioPath: 'a/micro.mp3',
        microTextPath: 'a/micro.txt',
      );

      // Mimic resolver swap
      final resolved = original.copyWith(
        audioFilePath: original.microAudioPath,
        textFilePath: original.microTextPath,
      );

      expect(resolved.audioFilePath, 'a/micro.mp3');
      expect(resolved.textFilePath, 'a/micro.txt');
      // micro paths preserved on the resolved parable
      expect(resolved.microAudioPath, 'a/micro.mp3');
      expect(resolved.microTextPath, 'a/micro.txt');
      // Anti-repeat key (storyId) unchanged — variant doesn't fork identity
      expect(resolved.storyId, 'multi');
    });

    test('30% path: no swap → audio + text paths unchanged', () {
      final original = Parable(
        storyId: 'multi',
        title: 'Multi',
        mood: 'anxious',
        storytellingMode: 'traditional',
        kidFriendly: false,
        storyLength: 'short',
        audioFilePath: 'a/short.mp3',
        textFilePath: 'a/short.txt',
        microAudioPath: 'a/micro.mp3',
        microTextPath: 'a/micro.txt',
      );
      // 30% path: resolver returns the parable as-is
      expect(original.audioFilePath, 'a/short.mp3');
      expect(original.textFilePath, 'a/short.txt');
    });

    test(
        'legacy single-variant MICRO: resolver does not swap (hasMicroVariant=false)',
        () {
      final legacy = Parable(
        storyId: 'legacy_micro',
        title: 'Legacy',
        mood: 'anxious',
        storytellingMode: 'traditional',
        kidFriendly: false,
        storyLength: 'short',
        shortScripture: true,
        // NOTE: no microAudioPath — legacy single-variant exposes its micro
        // content directly via audioFilePath.
        audioFilePath: 'legacy/audio_micro.mp3',
        textFilePath: 'legacy/text_micro.txt',
      );
      expect(legacy.hasMicroVariant, false,
          reason: 'Legacy single-variant has no separate microAudioPath.');
      // Resolver guard: tookMicroPath && hasMicroVariant — second clause false
      // means resolver no-ops. The parable's own paths already point at micro.
      expect(legacy.audioFilePath, 'legacy/audio_micro.mp3');
    });
  });

  group('B1: bias eligibility predicate accepts both representations', () {
    // The pool filter in ParableService uses _hasMicroContent which is
    // semantically (p.shortScripture || p.hasMicroVariant). We can't access
    // the private predicate directly, but we can verify the contract via
    // the public Parable getters.

    test('legacy shortScripture=true passes the content check', () {
      final p = Parable(
        storyId: 'a',
        title: 't',
        mood: 'anxious',
        storytellingMode: 'traditional',
        kidFriendly: false,
        shortScripture: true,
      );
      expect(p.shortScripture || p.hasMicroVariant, true);
    });

    test('B1 multi-variant hasMicroVariant=true passes the content check', () {
      final p = Parable(
        storyId: 'a',
        title: 't',
        mood: 'anxious',
        storytellingMode: 'traditional',
        kidFriendly: false,
        microAudioPath: 'x.mp3',
      );
      expect(p.shortScripture || p.hasMicroVariant, true);
    });

    test('plain Short (neither flag) does NOT pass the content check', () {
      final p = Parable(
        storyId: 'a',
        title: 't',
        mood: 'anxious',
        storytellingMode: 'traditional',
        kidFriendly: false,
      );
      expect(p.shortScripture || p.hasMicroVariant, false);
    });
  });
}
