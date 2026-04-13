import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/services/completed_stories_store.dart';

/// Tests for PALs Paths completion persistence (SPEC Feature 50.4 + 50.11,
/// INVARIANTS Data Capacity Invariants — Completed Stories 1000 / Awarded
/// Badges 200, set semantics, write-once idempotent, FIFO eviction).
void main() {
  late StorageService storage;
  late CompletedStoriesStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    store = CompletedStoriesStore(storage);
  });

  group('CompletedStoriesStore — idempotent write-once semantics', () {
    test('markCompleted is idempotent for the same storyId', () async {
      await store.markCompleted('david_001');
      await store.markCompleted('david_001');
      await store.markCompleted('david_001');

      expect(await store.completedCount(), 1);
      expect(await store.isCompleted('david_001'), isTrue);
    });

    test('isCompleted returns false for unknown stories', () async {
      expect(await store.isCompleted('never_played'), isFalse);
      await store.markCompleted('moses_001');
      expect(await store.isCompleted('never_played'), isFalse);
      expect(await store.isCompleted('moses_001'), isTrue);
    });

    test('multiple stories tracked independently', () async {
      await store.markCompleted('david_001');
      await store.markCompleted('moses_001');
      await store.markCompleted('ruth_001');

      expect(await store.completedCount(), 3);
      expect(await store.isCompleted('david_001'), isTrue);
      expect(await store.isCompleted('moses_001'), isTrue);
      expect(await store.isCompleted('ruth_001'), isTrue);
    });

    test('all() returns insertion order', () async {
      await store.markCompleted('first');
      await store.markCompleted('second');
      await store.markCompleted('third');

      final all = await store.all();
      expect(all, <String>['first', 'second', 'third']);
    });
  });

  group('completedStories cap (1000, FIFO eviction)', () {
    test('addCompletedStory drops oldest beyond 1000', () async {
      // Add 1005 unique storyIds. Oldest 5 should be evicted.
      for (int i = 0; i < 1005; i++) {
        await storage.addCompletedStory('s_$i');
      }
      final list = await storage.getCompletedStories();
      expect(list.length, 1000);
      // Oldest 5 (s_0..s_4) evicted, s_5..s_1004 retained.
      expect(list.first, 's_5');
      expect(list.last, 's_1004');
    });

    test('validateAndHealInvariants heals oversized legacy data', () async {
      // Simulate legacy data with 1200 entries written before the cap existed.
      final prefs = await SharedPreferences.getInstance();
      final bloated = List.generate(1200, (i) => 's_$i');
      await prefs.setString('completed_stories', jsonEncode(bloated));

      final report = await storage.validateAndHealInvariants();
      expect(report['completed_stories_trimmed'], 200);

      final list = await storage.getCompletedStories();
      expect(list.length, 1000);
      // FIFO trim: oldest 200 dropped, so s_200..s_1199 survive.
      expect(list.first, 's_200');
      expect(list.last, 's_1199');
    });
  });

  group('awardedBadges cap (200, FIFO eviction)', () {
    test('addAwardedBadge is idempotent', () async {
      await storage.addAwardedBadge('life_of_jesus_complete');
      await storage.addAwardedBadge('life_of_jesus_complete');

      final list = await storage.getAwardedBadges();
      expect(list.length, 1);
    });

    test('addAwardedBadge drops oldest beyond 200', () async {
      for (int i = 0; i < 210; i++) {
        await storage.addAwardedBadge('badge_$i');
      }
      final list = await storage.getAwardedBadges();
      expect(list.length, 200);
      expect(list.first, 'badge_10');
      expect(list.last, 'badge_209');
    });

    test('validateAndHealInvariants heals oversized badges', () async {
      final prefs = await SharedPreferences.getInstance();
      final bloated = List.generate(250, (i) => 'b_$i');
      await prefs.setString('awarded_badges', jsonEncode(bloated));

      final report = await storage.validateAndHealInvariants();
      expect(report['awarded_badges_trimmed'], 50);

      final list = await storage.getAwardedBadges();
      expect(list.length, 200);
      expect(list.first, 'b_50');
      expect(list.last, 'b_249');
    });
  });

  group('persistence across restarts', () {
    test('completed stories survive a fresh StorageService instance',
        () async {
      await store.markCompleted('persistent_001');
      await store.markCompleted('persistent_002');

      // Simulate app restart: reuse the underlying SharedPreferences
      // (which is mock-backed but the data persists for the test).
      final prefs = await SharedPreferences.getInstance();
      final freshStorage = StorageService(prefs);
      final freshStore = CompletedStoriesStore(freshStorage);

      expect(await freshStore.isCompleted('persistent_001'), isTrue);
      expect(await freshStore.isCompleted('persistent_002'), isTrue);
      expect(await freshStore.completedCount(), 2);
    });
  });

  group('healing does not touch data within cap', () {
    test('1000 exactly is preserved, no eviction', () async {
      for (int i = 0; i < 1000; i++) {
        await storage.addCompletedStory('s_$i');
      }
      final report = await storage.validateAndHealInvariants();
      expect(report['completed_stories_trimmed'], isNull);

      final list = await storage.getCompletedStories();
      expect(list.length, 1000);
      expect(list.first, 's_0');
      expect(list.last, 's_999');
    });
  });
}
