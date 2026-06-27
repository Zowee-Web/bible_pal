import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_pal/features/pal_memory/pal_session.dart';
import 'package:bible_pal/features/pal_memory/pal_session_store.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/services/storage_service.dart';

/// Tests for PAL Memory Doctrine Slice 1 — session persistence.
/// See docs/PAL_MEMORY_DOCTRINE.md.
///
/// Slice 1 is intentionally narrow: completed-session writes from the
/// player hook, a most-recent reader for future Level 2 templates, a
/// trust-protective clear(), and the cap/heal parity with the play log.
/// No UI consumer yet.
void main() {
  late StorageService storage;
  late PalSessionStore store;

  Parable buildParable({
    String storyId = '1007',
    String mood = 'anxious',
    String? bibleSourceRef = 'Jonah 1:1-17',
    String? bibleStoryKey = 'jonah_storm',
    List<String>? themeTags = const ['surrender', 'storm'],
    List<String> emotionalTags = const ['anxious', 'overwhelmed'],
    String? storyLength = 'short',
    String languageStyle = 'WEB',
  }) {
    return Parable(
      storyId: storyId,
      title: 'Jonah and the Storm',
      mood: mood,
      emotionalTags: emotionalTags,
      themeTags: themeTags,
      storyLength: storyLength,
      storytellingMode: 'traditional',
      languageStyle: languageStyle,
      bibleSourceRef: bibleSourceRef,
      bibleStoryKey: bibleStoryKey,
      kidFriendly: false,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    store = PalSessionStore(storage);
  });

  group('recordCompletion — snapshot semantics', () {
    test('snapshots every memory-relevant field from the parable', () async {
      final at = DateTime.utc(2026, 6, 18, 21, 0);
      await store.recordCompletion(buildParable(), mood: 'anxious', at: at);

      final all = await store.all();
      expect(all, hasLength(1));
      final s = all.single;
      expect(s.storyId, '1007');
      expect(s.completedAt, at);
      expect(s.mood, 'anxious');
      expect(s.themeTags, ['surrender', 'storm']);
      expect(s.emotionalTags, ['anxious', 'overwhelmed']);
      expect(s.scriptureAnchor, 'Jonah 1:1-17');
      expect(s.bibleStoryKey, 'jonah_storm');
      expect(s.storyLength, 'short');
      expect(s.languageStyle, 'WEB');
    });

    test('null mood is allowed (path / favorite / history entry points)',
        () async {
      await store.recordCompletion(buildParable(), at: DateTime.utc(2026, 6, 18));
      final s = (await store.all()).single;
      expect(s.mood, isNull);
    });

    test('null themeTags on the parable becomes empty list on the session',
        () async {
      await store.recordCompletion(
        buildParable(themeTags: null),
        at: DateTime.utc(2026, 6, 18),
      );
      expect((await store.all()).single.themeTags, isEmpty);
    });

    test('re-listening to the same story appends a fresh record', () async {
      await store.recordCompletion(buildParable(),
          at: DateTime.utc(2026, 6, 17));
      await store.recordCompletion(buildParable(),
          at: DateTime.utc(2026, 6, 18));

      final all = await store.all();
      expect(all, hasLength(2));
      expect(all.first.completedAt, DateTime.utc(2026, 6, 17));
      expect(all.last.completedAt, DateTime.utc(2026, 6, 18));
    });
  });

  group('getMostRecentCompleted — window + ordering', () {
    test('returns null when no sessions exist', () async {
      expect(await store.getMostRecentCompleted(), isNull);
    });

    test('returns the newest session in append order', () async {
      await store.recordCompletion(buildParable(storyId: 'a'),
          at: DateTime.now().subtract(const Duration(days: 2)));
      await store.recordCompletion(buildParable(storyId: 'b'),
          at: DateTime.now().subtract(const Duration(days: 1)));
      await store.recordCompletion(buildParable(storyId: 'c'),
          at: DateTime.now().subtract(const Duration(hours: 1)));

      final s = await store.getMostRecentCompleted();
      expect(s!.storyId, 'c');
    });

    test('respects the within window — older sessions excluded', () async {
      await store.recordCompletion(buildParable(storyId: 'old'),
          at: DateTime.now().subtract(const Duration(days: 30)));

      // Default 14-day window excludes the 30-day-old session.
      expect(await store.getMostRecentCompleted(), isNull);

      // Wider window picks it up.
      final s = await store.getMostRecentCompleted(
        within: const Duration(days: 60),
      );
      expect(s!.storyId, 'old');
    });

    test('walks past out-of-window sessions to find an in-window one',
        () async {
      // Append order has an old session first, then a recent one — the
      // reader must skip past the old to surface the recent.
      await store.recordCompletion(buildParable(storyId: 'old'),
          at: DateTime.now().subtract(const Duration(days: 30)));
      await store.recordCompletion(buildParable(storyId: 'recent'),
          at: DateTime.now().subtract(const Duration(days: 1)));

      final s = await store.getMostRecentCompleted();
      expect(s!.storyId, 'recent');
    });
  });

  group('clear() — trust-protective wipe', () {
    test('removes every persisted session', () async {
      await store.recordCompletion(buildParable(storyId: 'a'));
      await store.recordCompletion(buildParable(storyId: 'b'));
      expect((await store.all()).length, 2);

      await store.clear();
      expect(await store.all(), isEmpty);
      expect(await store.getMostRecentCompleted(), isNull);
    });

    test('subsequent recordCompletion writes start from a clean log',
        () async {
      await store.recordCompletion(buildParable(storyId: 'a'));
      await store.clear();
      await store.recordCompletion(buildParable(storyId: 'b'),
          at: DateTime.utc(2026, 6, 18));

      final all = await store.all();
      expect(all, hasLength(1));
      expect(all.single.storyId, 'b');
    });
  });

  group('cap (1000, FIFO by completedAt)', () {
    test('addPalSession evicts oldest beyond 1000', () async {
      // Add 1005 sessions with strictly increasing timestamps.
      for (var i = 0; i < 1005; i++) {
        await storage.addPalSession(PalSession(
          storyId: 's_$i',
          completedAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
          languageStyle: 'WEB',
        ));
      }
      final list = await storage.getPalSessions();
      expect(list.length, 1000);
      // Oldest 5 dropped, s_5..s_1004 retained in append order.
      expect(list.first.storyId, 's_5');
      expect(list.last.storyId, 's_1004');
    });

    test('validateAndHealInvariants trims oversized legacy data', () async {
      // Simulate legacy data written before the cap existed: 1200 entries.
      final prefs = await SharedPreferences.getInstance();
      final bloated = List.generate(
        1200,
        (i) => PalSession(
          storyId: 's_$i',
          completedAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
          languageStyle: 'WEB',
        ).toJson(),
      );
      await prefs.setString('pal_sessions_v1', jsonEncode(bloated));

      final report = await storage.validateAndHealInvariants();
      expect(report['pal_sessions_trimmed'], 200);

      final list = await storage.getPalSessions();
      expect(list.length, 1000);
      expect(list.first.storyId, 's_200');
      expect(list.last.storyId, 's_1199');
    });

    test('healing leaves data at exactly the cap alone', () async {
      for (var i = 0; i < 1000; i++) {
        await storage.addPalSession(PalSession(
          storyId: 's_$i',
          completedAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
          languageStyle: 'WEB',
        ));
      }
      final report = await storage.validateAndHealInvariants();
      expect(report['pal_sessions_trimmed'], isNull);
      expect((await storage.getPalSessions()).length, 1000);
    });
  });

  group('persistence across StorageService instances', () {
    test('sessions survive a fresh StorageService instance', () async {
      await store.recordCompletion(buildParable(storyId: 'persistent_001'),
          mood: 'anxious', at: DateTime.utc(2026, 6, 18));

      // Simulate app restart — fresh StorageService over the same prefs.
      final prefs = await SharedPreferences.getInstance();
      final freshStorage = StorageService(prefs);
      final freshStore = PalSessionStore(freshStorage);

      final all = await freshStore.all();
      expect(all, hasLength(1));
      expect(all.single.storyId, 'persistent_001');
      expect(all.single.mood, 'anxious');
    });
  });

  group('JSON round-trip', () {
    test('PalSession.toJson then fromJson preserves every field', () {
      final original = PalSession(
        storyId: '1007',
        completedAt: DateTime.utc(2026, 6, 18, 21, 0),
        mood: 'anxious',
        themeTags: const ['surrender', 'storm'],
        emotionalTags: const ['anxious', 'overwhelmed'],
        scriptureAnchor: 'Jonah 1:1-17',
        bibleStoryKey: 'jonah_storm',
        storyLength: 'short',
        languageStyle: 'KJV',
      );
      final round = PalSession.fromJson(original.toJson());
      expect(round.storyId, original.storyId);
      expect(round.completedAt, original.completedAt);
      expect(round.mood, original.mood);
      expect(round.themeTags, original.themeTags);
      expect(round.emotionalTags, original.emotionalTags);
      expect(round.scriptureAnchor, original.scriptureAnchor);
      expect(round.bibleStoryKey, original.bibleStoryKey);
      expect(round.storyLength, original.storyLength);
      expect(round.languageStyle, original.languageStyle);
    });

    test('null fields omitted from JSON but readable on parse', () {
      final session = PalSession(
        storyId: 'x',
        completedAt: DateTime.utc(2026, 6, 18),
        languageStyle: 'WEB',
      );
      final json = session.toJson();
      expect(json.containsKey('mood'), isFalse);
      expect(json.containsKey('scriptureAnchor'), isFalse);
      expect(json.containsKey('bibleStoryKey'), isFalse);
      expect(json.containsKey('storyLength'), isFalse);

      final round = PalSession.fromJson(json);
      expect(round.mood, isNull);
      expect(round.themeTags, isEmpty);
      expect(round.emotionalTags, isEmpty);
      expect(round.scriptureAnchor, isNull);
      expect(round.bibleStoryKey, isNull);
      expect(round.storyLength, isNull);
    });
  });
}
