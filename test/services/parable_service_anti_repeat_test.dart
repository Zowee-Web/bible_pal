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

  test(
      'previewBibleStoryKey rotates away from a recently-played key '
      'when alternatives exist (fixes "same story for same mood text")',
      () async {
    const previewMood = 'weary';
    const userText = 'I feel weary';

    // Baseline: with no play log, repeat calls return the same top key.
    final firstKey = await service.previewBibleStoryKey(
      mood: previewMood,
      userPrefs: adultPrefs,
      userText: userText,
    );
    expect(firstKey, isNotNull,
        reason: 'Sanity — manifest must yield a key for $previewMood');

    final repeatKey = await service.previewBibleStoryKey(
      mood: previewMood,
      userPrefs: adultPrefs,
      userText: userText,
    );
    expect(repeatKey, firstKey,
        reason: 'Without a play log, identical text must produce the '
            'same top-ranked key (deterministic baseline)');

    // Find every story whose bibleStoryKey == firstKey and mark them all
    // as recently played. Without the fix, the next preview call would
    // still return firstKey (same relatability ranking).
    final pool = await service.getEligibleParables(
      mood: previewMood,
      lengthBucket: testBucket,
      userPrefs: adultPrefs,
    );
    final variantsOfFirst =
        pool.where((p) => p.bibleStoryKey == firstKey).toList();
    expect(variantsOfFirst, isNotEmpty,
        reason: 'Pool must contain at least one variant of the first key');

    final now = DateTime.now();
    for (final p in variantsOfFirst) {
      await storage.recordPlayed(p.storyId, at: now);
    }

    // Now the preview must rotate to a different bibleStoryKey, since
    // alternatives exist for this mood.
    final rotated = await service.previewBibleStoryKey(
      mood: previewMood,
      userPrefs: adultPrefs,
      userText: userText,
    );
    expect(rotated, isNotNull);
    expect(rotated, isNot(firstKey),
        reason: 'A recently-played key must yield to a fresh alternative '
            'when the mood pool offers other bibleStoryKeys');
  });

  test(
      'same-bibleStoryKey variants rotate via play-log LRP '
      'when multiple variants share a (mood,length,lang,kid,mode) bucket',
      () async {
    // The manifest contains exactly two variants of `fiery_furnace` for
    // mood=brave_courage, length=short, lang=WEB, kid=false, mode=traditional
    // (story_1002_* and story_1091_*). This bucket is the canonical place
    // to lock in the same-key rotation guarantee — the only behavior PAL can
    // honor without crossing user-selected length / translation / mode / kid
    // boundaries (see SPEC Feature #15).
    const sameKeyMood = 'brave_courage';
    const sameKeyKey = 'fiery_furnace';

    // Confirm the bucket has at least two variants; if the content team
    // collapses it to a single variant later, this test will fail loudly
    // and signal the assumption to revisit.
    final pool = await service.getEligibleParables(
      mood: sameKeyMood,
      lengthBucket: testBucket,
      userPrefs: adultPrefs,
    );
    final variants = pool.where((p) => p.bibleStoryKey == sameKeyKey).toList();
    expect(variants.length, greaterThanOrEqualTo(2),
        reason: 'Test bucket must carry ≥2 variants of $sameKeyKey for '
            'rotation to be observable');

    // First call with empty play log → either variant is acceptable (Tier 1
    // unseen, stable storyId tiebreak). Capture whichever the engine picks.
    final first = await service.selectParable(
      mood: sameKeyMood,
      lengthBucket: testBucket,
      userPrefs: adultPrefs,
      bibleStoryKey: sameKeyKey,
    );
    expect(first, isNotNull);
    expect(first!.bibleStoryKey, sameKeyKey);

    // Record the first pick and call again. With one variant in the play
    // log within the 30-day window and one still unseen, Tier 1 must pick
    // the OTHER variant — not repeat the same storyId.
    await storage.recordPlayed(first.storyId,
        at: DateTime.now().subtract(const Duration(minutes: 1)));

    final second = await service.selectParable(
      mood: sameKeyMood,
      lengthBucket: testBucket,
      userPrefs: adultPrefs,
      bibleStoryKey: sameKeyKey,
    );
    expect(second, isNotNull);
    expect(second!.bibleStoryKey, sameKeyKey,
        reason: 'Selection must remain inside the requested bibleStoryKey');
    expect(second.storyId, isNot(first.storyId),
        reason: 'Tier 1 unseen must rotate to the other variant in the '
            'same bucket rather than repeat the most-recent storyId');

    // Now both variants are recently played — Tier 1 is empty, so Tier 3
    // (LRP) takes over. Record the second pick with a more recent stamp,
    // then verify the next call returns the first storyId again (it is now
    // the least-recently-played of the two).
    await storage.recordPlayed(second.storyId, at: DateTime.now());

    final third = await service.selectParable(
      mood: sameKeyMood,
      lengthBucket: testBucket,
      userPrefs: adultPrefs,
      bibleStoryKey: sameKeyKey,
    );
    expect(third, isNotNull);
    expect(third!.storyId, first.storyId,
        reason: 'When all same-key variants are recently played, Tier 3 '
            'must rotate to the least-recently-played variant');
  });
}
