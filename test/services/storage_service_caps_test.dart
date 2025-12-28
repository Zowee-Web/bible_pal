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
          faithTradition: 'Protestant',
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
          faithTradition: 'Protestant',
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
          faithTradition: 'Protestant',
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
          faithTradition: 'Protestant',
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
}
