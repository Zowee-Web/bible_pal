import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/models/favorite.dart';
import 'package:bible_pal/models/history_entry.dart';
import 'package:bible_pal/models/pal.dart';
import 'package:bible_pal/models/share_record.dart';

/// Unit tests for storage service caps enforcement (v1.0 checklist)
/// - Favorites cap: 100 stories (MUST enforce)
/// - History cap: 20 stories (MUST enforce)
/// - PALs and Shares persistence
void main() {
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
  });

  group('History Cap (20 stories FIFO)', () {
    test('should enforce 20-story cap', () async {
      // Add 25 history entries
      for (int i = 0; i < 25; i++) {
        final entry = HistoryEntry(
          storyId: 'story_$i',
          title: 'Story $i',
          mood: 'joyful',
          length: 5,
          timestamp: DateTime.now(),
        );
        await storage.addToHistory(entry);
      }

      // Get history and verify cap
      final history = await storage.getHistory();

      expect(history.length, equals(20),
          reason: 'History should be capped at 20 entries');

      // Verify FIFO: most recent (story_24) should be first
      expect(history.first.storyId, equals('story_24'));

      // Oldest kept should be story_5 (24 - 19)
      expect(history.last.storyId, equals('story_5'));
    });

    test('should maintain order with cap', () async {
      for (int i = 0; i < 10; i++) {
        await storage.addToHistory(HistoryEntry(
          storyId: 'story_$i',
          title: 'Story $i',
          mood: 'neutral',
          length: 10,
          timestamp: DateTime.now(),
        ));
      }

      final history = await storage.getHistory();

      expect(history.length, equals(10));
      expect(history.first.storyId, equals('story_9')); // Most recent
      expect(history.last.storyId, equals('story_0')); // Oldest
    });
  });

  group('Favorites Cap (100 stories)', () {
    test('should allow adding up to 100 favorites', () async {
      // Add 100 favorites
      for (int i = 0; i < 100; i++) {
        final favorite = Favorite(
          storyId: 'story_$i',
          title: 'Story $i',
          mood: 'joyful',
          length: 5,
          scriptureSources: [],
          dateSaved: DateTime.now(),
        );
        await storage.addFavorite(favorite);
      }

      final favorites = await storage.getFavorites();

      expect(favorites.length, equals(100),
          reason: 'Should allow exactly 100 favorites');
    });

    test('should enforce 100-story cap and trim oldest', () async {
      // Add 105 favorites
      for (int i = 0; i < 105; i++) {
        await storage.addFavorite(Favorite(
          storyId: 'story_$i',
          title: 'Story $i',
          mood: 'neutral',
          length: 5,
          scriptureSources: [],
          dateSaved: DateTime.now(),
        ));
      }

      // Should be capped at 100
      final favorites = await storage.getFavorites();
      expect(favorites.length, equals(100),
          reason: 'Should enforce 100-story cap');

      // Verify newest 100 are kept (story_5 through story_104)
      expect(favorites.first.storyId, equals('story_104'),
          reason: 'Most recent should be first');
      expect(favorites.last.storyId, equals('story_5'),
          reason: 'Oldest kept should be story_5 (104 - 99)');
    });
  });

  group('PALs Persistence', () {
    test('should save and load PALs', () async {
      final pal1 = PAL(
        palId: 'pal_1',
        displayName: 'Alice',
        createdAt: DateTime.now(),
      );
      final pal2 = PAL(
        palId: 'pal_2',
        displayName: 'Bob',
        createdAt: DateTime.now(),
        pinned: true,
        shareCount: 5,
      );

      await storage.addPal(pal1);
      await storage.addPal(pal2);

      final pals = await storage.getPals();

      expect(pals.length, equals(2));

      // Verify sorting: pinned first, then by shareCount desc
      expect(pals[0].palId, equals('pal_2')); // Bob (pinned)
      expect(pals[1].palId, equals('pal_1')); // Alice
    });

    test('should update PAL share count', () async {
      final pal = PAL(
        palId: 'pal_1',
        displayName: 'Charlie',
        createdAt: DateTime.now(),
        shareCount: 0,
      );

      await storage.addPal(pal);
      await storage.incrementPalShareCount('pal_1');
      await storage.incrementPalShareCount('pal_1');

      final pals = await storage.getPals();

      expect(pals.first.shareCount, equals(2));
    });
  });

  group('Share Records Persistence', () {
    test('should save and load share records', () async {
      final share1 = ShareRecord(
        shareId: 'share_1',
        storyId: 'story_1',
        storyTitle: 'Story One',
        toPalId: 'pal_1',
        timestamp: DateTime.now(),
        direction: ShareDirection.sent,
      );
      final share2 = ShareRecord(
        shareId: 'share_2',
        storyId: 'story_2',
        storyTitle: 'Story Two',
        toPalId: 'pal_1',
        timestamp: DateTime.now(),
        direction: ShareDirection.sent,
      );

      await storage.addShare(share1);
      await storage.addShare(share2);

      final shares = await storage.getShares();

      expect(shares.length, equals(2));
    });

    test('should filter shares by PAL', () async {
      await storage.addShare(ShareRecord(
        shareId: 'share_1',
        storyId: 'story_1',
        storyTitle: 'Story One',
        toPalId: 'pal_alice',
        timestamp: DateTime.now(),
        direction: ShareDirection.sent,
      ));
      await storage.addShare(ShareRecord(
        shareId: 'share_2',
        storyId: 'story_2',
        storyTitle: 'Story Two',
        toPalId: 'pal_bob',
        timestamp: DateTime.now(),
        direction: ShareDirection.sent,
      ));
      await storage.addShare(ShareRecord(
        shareId: 'share_3',
        storyId: 'story_3',
        storyTitle: 'Story Three',
        toPalId: 'pal_alice',
        timestamp: DateTime.now(),
        direction: ShareDirection.sent,
      ));

      final aliceShares = await storage.getSharesToPal('pal_alice');
      final bobShares = await storage.getSharesToPal('pal_bob');

      expect(aliceShares.length, equals(2));
      expect(bobShares.length, equals(1));
    });
  });

  group('Enum Serialization (future-safe + backward compatible)', () {
    test('ShareDirection should serialize with .name as "sent"', () {
      final share = ShareRecord(
        shareId: 'share_1',
        storyId: 'story_1',
        storyTitle: 'Test Story',
        toPalId: 'pal_1',
        timestamp: DateTime.now(),
        direction: ShareDirection.sent,
      );

      final json = share.toJson();

      expect(json['direction'], equals('sent'),
          reason: 'Should serialize as "sent", not "ShareDirection.sent"');
    });

    test('ShareDirection should serialize with .name as "received"', () {
      final share = ShareRecord(
        shareId: 'share_1',
        storyId: 'story_1',
        storyTitle: 'Test Story',
        toPalId: 'pal_1',
        timestamp: DateTime.now(),
        direction: ShareDirection.received,
      );

      final json = share.toJson();

      expect(json['direction'], equals('received'),
          reason:
              'Should serialize as "received", not "ShareDirection.received"');
    });

    test('ShareDirection should deserialize from "sent"', () {
      final json = {
        'shareId': 'share_1',
        'storyId': 'story_1',
        'storyTitle': 'Test Story',
        'toPalId': 'pal_1',
        'timestamp': DateTime.now().toIso8601String(),
        'direction': 'sent',
      };

      final share = ShareRecord.fromJson(json);

      expect(share.direction, equals(ShareDirection.sent));
      expect(share.storyTitle, equals('Test Story'));
    });

    test('ShareDirection should deserialize from "received"', () {
      final json = {
        'shareId': 'share_1',
        'storyId': 'story_1',
        'storyTitle': 'Test Story',
        'toPalId': 'pal_1',
        'timestamp': DateTime.now().toIso8601String(),
        'direction': 'received',
      };

      final share = ShareRecord.fromJson(json);

      expect(share.direction, equals(ShareDirection.received));
      expect(share.storyTitle, equals('Test Story'));
    });

    test('ShareDirection should deserialize legacy "ShareDirection.sent"', () {
      final json = {
        'shareId': 'share_1',
        'storyId': 'story_1',
        // NOTE: storyTitle intentionally omitted to test backward compatibility
        'toPalId': 'pal_1',
        'timestamp': DateTime.now().toIso8601String(),
        'direction': 'ShareDirection.sent',
      };

      final share = ShareRecord.fromJson(json);

      expect(share.direction, equals(ShareDirection.sent),
          reason:
              'Should strip "ShareDirection." prefix and deserialize correctly');
      expect(share.storyTitle, equals('story_1'),
          reason: 'Should fallback to storyId when storyTitle missing');
    });

    test('ShareDirection should deserialize legacy "ShareDirection.received"',
        () {
      final json = {
        'shareId': 'share_1',
        'storyId': 'story_1',
        // NOTE: storyTitle intentionally omitted to test backward compatibility
        'toPalId': 'pal_1',
        'timestamp': DateTime.now().toIso8601String(),
        'direction': 'ShareDirection.received',
      };

      final share = ShareRecord.fromJson(json);

      expect(share.direction, equals(ShareDirection.received),
          reason:
              'Should strip "ShareDirection." prefix and deserialize correctly');
      expect(share.storyTitle, equals('story_1'),
          reason: 'Should fallback to storyId when storyTitle missing');
    });

    test('ShareDirection should default to sent on null direction', () {
      final json = {
        'shareId': 'share_1',
        'storyId': 'story_1',
        'toPalId': 'pal_1',
        'timestamp': DateTime.now().toIso8601String(),
        'direction': null,
      };

      final share = ShareRecord.fromJson(json);

      expect(share.direction, equals(ShareDirection.sent),
          reason: 'Should default to sent when direction is null');
    });

    test('ShareDirection should default to sent on empty direction', () {
      final json = {
        'shareId': 'share_1',
        'storyId': 'story_1',
        'toPalId': 'pal_1',
        'timestamp': DateTime.now().toIso8601String(),
        'direction': '',
      };

      final share = ShareRecord.fromJson(json);

      expect(share.direction, equals(ShareDirection.sent),
          reason: 'Should default to sent when direction is empty');
    });

    test('ShareDirection should default to sent on unknown value', () {
      final json = {
        'shareId': 'share_1',
        'storyId': 'story_1',
        'toPalId': 'pal_1',
        'timestamp': DateTime.now().toIso8601String(),
        'direction': 'UNKNOWN_DIRECTION',
      };

      final share = ShareRecord.fromJson(json);

      expect(share.direction, equals(ShareDirection.sent),
          reason: 'Should default to sent for backward compatibility');
    });
  });

  group('Play Log (selection-time anti-repeat, cap=1000)', () {
    test('starts empty and round-trips entries', () async {
      expect(await storage.getPlayLog(), isEmpty);

      final t = DateTime(2026, 4, 1, 12, 0);
      await storage.recordPlayed('story_a', at: t);

      final log = await storage.getPlayLog();
      expect(log.length, 1);
      expect(log['story_a'], t);
    });

    test('recordPlayed updates lastPlayedAt for a repeated story', () async {
      final t1 = DateTime(2026, 1, 1);
      final t2 = DateTime(2026, 4, 1);
      await storage.recordPlayed('story_a', at: t1);
      await storage.recordPlayed('story_a', at: t2);

      final log = await storage.getPlayLog();
      expect(log.length, 1, reason: 'Same storyId should not duplicate');
      expect(log['story_a'], t2);
    });

    test(
        'play log retains more than 20 entries '
        '(decoupled from 20-entry History cap)', () async {
      final base = DateTime(2026, 1, 1);
      for (int i = 0; i < 50; i++) {
        await storage.recordPlayed('story_$i',
            at: base.add(Duration(minutes: i)));
      }
      final log = await storage.getPlayLog();
      expect(log.length, 50,
          reason: 'Play log must hold >20; History cap is independent');
    });

    test('caps at 1000 by evicting oldest timestamps (FIFO)', () async {
      final base = DateTime(2026, 1, 1);
      // Insert 1005 entries with strictly increasing timestamps.
      for (int i = 0; i < 1005; i++) {
        await storage.recordPlayed('story_$i',
            at: base.add(Duration(seconds: i)));
      }
      final log = await storage.getPlayLog();
      expect(log.length, 1000,
          reason: 'Play log must cap at 1000 entries');
      // The 5 oldest (story_0..story_4) should be evicted.
      for (int i = 0; i < 5; i++) {
        expect(log.containsKey('story_$i'), false,
            reason: 'Oldest story_$i should have been evicted');
      }
      expect(log.containsKey('story_1004'), true,
          reason: 'Newest entry must be retained');
    });

    test('writing to play log does NOT affect 20-entry History cap',
        () async {
      // Seed a 25-entry play log
      final base = DateTime(2026, 1, 1);
      for (int i = 0; i < 25; i++) {
        await storage.recordPlayed('story_$i',
            at: base.add(Duration(minutes: i)));
      }

      // Then add 25 entries to the user-facing History via its own API
      for (int i = 0; i < 25; i++) {
        await storage.addToHistory(HistoryEntry(
          storyId: 'story_$i',
          title: 'Story $i',
          mood: 'joyful',
          length: 5,
          timestamp: base.add(Duration(minutes: i)),
        ));
      }

      final history = await storage.getHistory();
      final log = await storage.getPlayLog();
      expect(history.length, 20,
          reason: 'History cap (Feature #11 invariant) must remain 20');
      expect(log.length, 25,
          reason: 'Play log is independent of History cap');
    });

    test('clearPlayLog resets the log without touching History', () async {
      await storage.recordPlayed('story_a');
      await storage.addToHistory(HistoryEntry(
        storyId: 'story_a',
        title: 'A',
        mood: 'joyful',
        length: 5,
        timestamp: DateTime.now(),
      ));

      await storage.clearPlayLog();

      expect(await storage.getPlayLog(), isEmpty);
      expect((await storage.getHistory()).length, 1,
          reason: 'clearPlayLog must not affect History');
    });
  });

  group('Data Migration & Invariant Healing', () {
    test('should heal History cap violation (>20 entries)', () async {
      // Manually insert 30 history entries (simulating legacy data)
      final prefs = await SharedPreferences.getInstance();
      final legacyHistory = List.generate(
        30,
        (i) => {
          'storyId': 'story_$i',
          'title': 'Story $i',
          'mood': 'joyful',
          'length': 5,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      await prefs.setString('history', jsonEncode(legacyHistory));

      // Run migration
      final report = await storage.validateAndHealInvariants();

      // Verify trimmed count reported
      expect(report['history_trimmed'], equals(10),
          reason: 'Should report 10 entries trimmed (30 - 20)');

      // Verify cap enforced
      final history = await storage.getHistory();
      expect(history.length, equals(20),
          reason: 'History should be capped at 20 after migration');
    });

    test('should heal Favorites cap violation (>100 entries)', () async {
      // Manually insert 120 favorites (simulating legacy data)
      final prefs = await SharedPreferences.getInstance();
      final legacyFavorites = List.generate(
        120,
        (i) => {
          'storyId': 'story_$i',
          'title': 'Story $i',
          'mood': 'joyful',
          'length': 5,
          'scriptureSources': <String>[],
          'dateSaved': DateTime.now().toIso8601String(),
        },
      );
      await prefs.setString('favorites', jsonEncode(legacyFavorites));

      // Run migration
      final report = await storage.validateAndHealInvariants();

      // Verify trimmed count reported
      expect(report['favorites_trimmed'], equals(20),
          reason: 'Should report 20 entries trimmed (120 - 100)');

      // Verify cap enforced
      final favorites = await storage.getFavorites();
      expect(favorites.length, equals(100),
          reason: 'Favorites should be capped at 100 after migration');
    });

    test('should heal Pending Shares cap violation (>50 entries)', () async {
      // Manually insert 70 pending shares (simulating legacy data)
      final prefs = await SharedPreferences.getInstance();
      final legacyPending = List.generate(
        70,
        (i) => {
          'shareId': 'share_$i',
          'storyId': 'story_$i',
          'storyTitle': 'Story $i',
          'toPalId': 'pal_1',
          'createdAt': DateTime.now().toIso8601String(),
          'retryCount': 0,
        },
      );
      await prefs.setString('pending_shares', jsonEncode(legacyPending));

      // Run migration
      final report = await storage.validateAndHealInvariants();

      // Verify trimmed count reported
      expect(report['pending_shares_trimmed'], equals(20),
          reason: 'Should report 20 entries trimmed (70 - 50)');

      // Verify cap enforced
      final pending = await storage.getPendingShares();
      expect(pending.length, equals(50),
          reason: 'Pending shares should be capped at 50 after migration');
    });

    test('should heal Play Log cap violation (>1000 entries)', () async {
      // Manually insert 1010 play log entries (simulating legacy bloat)
      final prefs = await SharedPreferences.getInstance();
      final base = DateTime(2026, 1, 1);
      final legacy = <String, String>{
        for (int i = 0; i < 1010; i++)
          'story_$i': base.add(Duration(seconds: i)).toIso8601String(),
      };
      await prefs.setString('play_log', jsonEncode(legacy));

      final report = await storage.validateAndHealInvariants();
      expect(report['play_log_trimmed'], equals(10),
          reason: 'Should report 10 entries trimmed (1010 - 1000)');

      final log = await storage.getPlayLog();
      expect(log.length, 1000,
          reason: 'Play log should be capped at 1000 after migration');
      // The 10 oldest entries should be the ones evicted.
      for (int i = 0; i < 10; i++) {
        expect(log.containsKey('story_$i'), false);
      }
    });

    test('should return empty report when no healing needed', () async {
      // Start with clean slate (no data)
      final report = await storage.validateAndHealInvariants();

      // Verify empty report
      expect(report.isEmpty, true,
          reason: 'Should return empty report when no healing needed');
    });
  });
}
