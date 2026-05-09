// Tests SPEC.md Feature #11 (anti-repeat note): selection-time anti-repeat
// memory uses the play log (cap=1000, 30-day "seen" window), not the
// 20-entry user-facing History. See INVARIANTS.md for the History invariant.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/models/history_entry.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/core/story_length_bucket.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late ParableService service;

  // A mood/bucket combination that the manifest carries plenty of variants
  // for. Using a non-kid-friendly traditional WEB pool (17 stories at last
  // count) keeps these tests robust to small content edits.
  const testMood = 'hurting';
  const testBucket = StoryLengthBucket.short;
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

  test('baseline: selectParable returns a story for the test mood', () async {
    final result = await service.selectParable(
      mood: testMood,
      lengthBucket: testBucket,
      userPrefs: adultPrefs,
    );
    expect(result, isNotNull,
        reason: 'Sanity check — manifest must yield a story for $testMood');
  });

  test(
      'selectParable consults play log, not user-facing History '
      '(History entries do NOT block re-selection)', () async {
    // Find all candidate stories for this mood/bucket/prefs.
    final pool = await service.getEligibleParables(
      mood: testMood,
      lengthBucket: testBucket,
      userPrefs: adultPrefs,
    );
    expect(pool.length, greaterThan(2),
        reason: 'Test requires multiple eligible stories');

    // Stuff every eligible storyId into the user-facing History but leave
    // the play log empty. If selectParable were (incorrectly) reading from
    // History, every story would be "seen" and Tier 1 would be empty.
    final now = DateTime.now();
    for (final p in pool) {
      await storage.addToHistory(HistoryEntry(
        storyId: p.storyId,
        title: p.title,
        mood: p.mood,
        length: 5,
        timestamp: now,
      ));
    }
    expect((await storage.getHistory()).isNotEmpty, true);
    expect(await storage.getPlayLog(), isEmpty,
        reason: 'Play log must remain empty for this test');

    // selectParable should still treat every story as unseen (Tier 1) and
    // return one of them — i.e., it ignored History.
    final result = await service.selectParable(
      mood: testMood,
      lengthBucket: testBucket,
      userPrefs: adultPrefs,
    );
    expect(result, isNotNull,
        reason: 'Selection must come from Tier 1 unseen — proves play '
            'log (not History) drives the seen set');
    expect(pool.any((p) => p.storyId == result!.storyId), true);
  });

  test(
      'stories played within 30 days are excluded from the unseen tier '
      '(Tier 1)', () async {
    final pool = await service.getEligibleParables(
      mood: testMood,
      lengthBucket: testBucket,
      userPrefs: adultPrefs,
    );
    expect(pool.length, greaterThan(2));

    // Mark every story BUT ONE as played 1 day ago.
    final survivor = pool.first;
    final recentlyPlayed = pool.skip(1).toList();
    final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));
    for (final p in recentlyPlayed) {
      await storage.recordPlayed(p.storyId, at: oneDayAgo);
    }
    // The MICRO serving bias (added separately) pulls MICROs from similar-mood
    // pools into the eligible set when the mood is high-intensity (anxious /
    // hurting / weary) at Short length. To keep this test focused on the
    // exact-mood anti-repeat behavior, also mark every MICRO from similar
    // moods as played — that way `survivor` is the only unseen candidate
    // across the entire combined pool the bias would consider.
    const similarMoodsForTest = ['anxious', 'weary', 'encouraging', 'calm_peaceful', 'brave_courage'];
    for (final m in similarMoodsForTest) {
      final similarPool = await service.getEligibleParables(
        mood: m,
        lengthBucket: testBucket,
        userPrefs: adultPrefs,
      );
      // Drain micro-content stories (legacy shortScripture=true OR B1
      // multi-variant hasMicroVariant=true) so the bias eligibility gate
      // fails for similar moods and Tier 1 isolation holds.
      for (final p in similarPool
          .where((p) => p.shortScripture || p.hasMicroVariant)) {
        if (p.storyId == survivor.storyId) continue;
        await storage.recordPlayed(p.storyId, at: oneDayAgo);
      }
    }

    // Tier 1 = exact mood + unseen — should contain only `survivor` from
    // the exact pool. (Similar moods may also contribute, but Tier 1 prefers
    // exact-mood unseen, so the survivor must win when called repeatedly.)
    for (var i = 0; i < 5; i++) {
      final result = await service.selectParable(
        mood: testMood,
        lengthBucket: testBucket,
        userPrefs: adultPrefs,
      );
      expect(result?.storyId, survivor.storyId,
          reason: 'Recently-played stories must not surface as Tier 1 '
              'while an unplayed exact-mood candidate exists');
    }
  });

  test(
      'stories played more than 30 days ago become eligible again '
      '(treated as unseen)', () async {
    final pool = await service.getEligibleParables(
      mood: testMood,
      lengthBucket: testBucket,
      userPrefs: adultPrefs,
    );
    expect(pool.length, greaterThan(2));

    // Mark every story as played 31 days ago — outside the 30-day window.
    final longAgo = DateTime.now().subtract(const Duration(days: 31));
    for (final p in pool) {
      await storage.recordPlayed(p.storyId, at: longAgo);
    }

    // Now mark ONE story as recently played (1 day ago). This story alone
    // should be excluded from Tier 1; the others should all be eligible.
    final blocked = pool.first;
    await storage.recordPlayed(blocked.storyId,
        at: DateTime.now().subtract(const Duration(days: 1)));

    // selectParable must NOT return `blocked` — even though every story is
    // technically in the play log, only `blocked` is within the 30-day
    // "seen" window. The rest are eligible Tier 1 picks again.
    for (var i = 0; i < 8; i++) {
      final result = await service.selectParable(
        mood: testMood,
        lengthBucket: testBucket,
        userPrefs: adultPrefs,
      );
      expect(result, isNotNull);
      expect(result!.storyId, isNot(blocked.storyId),
          reason: 'A story played within the 30-day window must stay '
              'excluded from Tier 1 even when older entries exist');
    }
  });
}
