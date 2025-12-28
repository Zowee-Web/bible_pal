import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/models/pending_share.dart';
import 'package:bible_pal/models/share_record.dart';

/// Unit tests for pending share queue (Transport Layer v1)
void main() {
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
  });

  group('Pending Share Queue', () {
    test('should add pending share to queue', () async {
      final share = PendingShare(
        shareId: 'share_uuid_123',
        storyId: 'story_001',
        storyTitle: 'Test Story',
        toPalId: 'pal_abc',
        createdAt: DateTime.now(),
      );

      await storage.addToPendingQueue(share);

      final pending = await storage.getPendingShares();
      expect(pending.length, equals(1));
      expect(pending.first.shareId, equals('share_uuid_123'));
      expect(pending.first.retryCount, equals(0));
    });

    test('should enforce idempotency (same shareId not added twice)', () async {
      final share1 = PendingShare(
        shareId: 'share_uuid_123', // SAME shareId
        storyId: 'story_001',
        storyTitle: 'Test Story',
        toPalId: 'pal_abc',
        createdAt: DateTime.now(),
      );

      final share2 = PendingShare(
        shareId: 'share_uuid_123', // SAME shareId (retry scenario)
        storyId: 'story_001',
        storyTitle: 'Test Story',
        toPalId: 'pal_abc',
        createdAt: DateTime.now(),
        retryCount: 1,
      );

      await storage.addToPendingQueue(share1);
      await storage.addToPendingQueue(share2); // Should be ignored

      final pending = await storage.getPendingShares();
      expect(pending.length, equals(1));
      expect(pending.first.shareId, equals('share_uuid_123'));
    });

    test('should enforce 50-share cap (FIFO)', () async {
      for (int i = 0; i < 55; i++) {
        await storage.addToPendingQueue(PendingShare(
          shareId: 'share_$i',
          storyId: 'story_$i',
          storyTitle: 'Story $i',
          toPalId: 'pal_abc',
          createdAt: DateTime.now(),
        ));
      }

      final pending = await storage.getPendingShares();
      expect(pending.length, equals(50));
      expect(pending.first.shareId, equals('share_54'));
      expect(pending.last.shareId, equals('share_5'));
    });

    test('should remove pending share by shareId', () async {
      await storage.addToPendingQueue(PendingShare(
        shareId: 'share_1',
        storyId: 'story_1',
        storyTitle: 'Story 1',
        toPalId: 'pal_abc',
        createdAt: DateTime.now(),
      ));

      await storage.addToPendingQueue(PendingShare(
        shareId: 'share_2',
        storyId: 'story_2',
        storyTitle: 'Story 2',
        toPalId: 'pal_abc',
        createdAt: DateTime.now(),
      ));

      await storage.removeFromPendingQueue('share_1');

      final pending = await storage.getPendingShares();
      expect(pending.length, equals(1));
      expect(pending.first.shareId, equals('share_2'));
    });

    test('should clear all pending shares', () async {
      await storage.addToPendingQueue(PendingShare(
        shareId: 'share_1',
        storyId: 'story_1',
        storyTitle: 'Story 1',
        toPalId: 'pal_abc',
        createdAt: DateTime.now(),
      ));

      await storage.clearPendingQueue();

      final pending = await storage.getPendingShares();
      expect(pending.isEmpty, isTrue);
    });
  });

  group('hasShare (Idempotency Check)', () {
    test('should return false for non-existent shareId', () async {
      final exists = await storage.hasShare('non_existent');
      expect(exists, isFalse);
    });

    test('should return true for existing shareId', () async {
      final share = ShareRecord(
        shareId: 'share_uuid_123',
        storyId: 'story_001',
        storyTitle: 'Test Story',
        toPalId: 'pal_abc',
        timestamp: DateTime.now(),
        direction: ShareDirection.received,
      );

      await storage.addShare(share);

      final exists = await storage.hasShare('share_uuid_123');
      expect(exists, isTrue);
    });
  });

  group('Inbox Sync Timestamp', () {
    test('should store and retrieve timestamp', () async {
      final now = DateTime.now();
      await storage.setLastInboxSyncTimestamp(now);

      final retrieved = await storage.getLastInboxSyncTimestamp();
      expect(retrieved, isNotNull);
      expect(retrieved!.year, equals(now.year));
    });

    test('should return null if no timestamp stored', () async {
      final timestamp = await storage.getLastInboxSyncTimestamp();
      expect(timestamp, isNull);
    });
  });
}
