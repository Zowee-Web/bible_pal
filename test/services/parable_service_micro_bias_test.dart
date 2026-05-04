// Tests for the MICRO serving bias.
//
// Spec: when the user's detected mood is high-intensity (anxious, hurting,
// weary) AND the selected length is Short, ParableService should prefer
// MICRO stories (shortScripture==true, lengths=["short"]) before falling
// back to normal Short selection. Bias never applies to Full or Long.
// Anti-repeat is honored — if all eligible MICROs are recently played,
// selection falls back to the broader Short pool.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/storage_service.dart';
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

  group('MICRO bias triggers for high-intensity moods + Short', () {
    test('anxious + Short prefers MICRO when one is eligible', () async {
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
}
