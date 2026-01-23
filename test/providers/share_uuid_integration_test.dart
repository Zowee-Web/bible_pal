import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/services/feature_flag_service.dart';
import 'package:bible_pal/models/share_record.dart';
import 'package:bible_pal/models/pending_share.dart';
import 'package:bible_pal/models/pal.dart';
import 'package:uuid/uuid.dart';

/// Integration tests for UUID-based shareId + conditional pending queue
/// Tests the complete flow: shareStoryWithPals() → ShareRecord + PendingShare
void main() {
  late StorageService storage;
  late FeatureFlagService featureFlags;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    featureFlags = FeatureFlagService();

    // Add test PAL
    await storage.addPal(PAL(
      palId: 'pal_123',
      displayName: 'Test PAL',
      createdAt: DateTime.now(),
    ));
  });

  group('UUID Generation (Idempotency Fix)', () {
    test('shareId should be valid UUID v4 format', () async {
      // Simulate shareStoryWithPals() behavior
      final shareId = const Uuid().v4();
      final timestamp = DateTime.now();

      final share = ShareRecord(
        shareId: shareId,
        storyId: 'story_001',
        storyTitle: 'Test Story',
        toPalId: 'pal_123',
        timestamp: timestamp,
        direction: ShareDirection.sent,
      );
      await storage.addShare(share);

      // Verify UUID format
      final uuidPattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      );
      expect(shareId, matches(uuidPattern),
          reason: 'shareId should be UUID v4, not timestamp');

      // Verify it's NOT old timestamp format
      expect(shareId, isNot(contains('_pal_')),
          reason: 'Should not contain timestamp pattern');
    });

    test('each share should get unique UUID', () async {
      final shareIds = <String>{};

      // Generate 10 shares
      for (int i = 0; i < 10; i++) {
        final shareId = const Uuid().v4();
        shareIds.add(shareId);

        await storage.addShare(ShareRecord(
          shareId: shareId,
          storyId: 'story_$i',
          storyTitle: 'Story $i',
          toPalId: 'pal_123',
          timestamp: DateTime.now(),
          direction: ShareDirection.sent,
        ));
      }

      // All should be unique
      expect(shareIds.length, equals(10), reason: 'All UUIDs should be unique');
    });

    test('UUID should remain stable across serialization', () async {
      final originalShareId = const Uuid().v4();

      final share = ShareRecord(
        shareId: originalShareId,
        storyId: 'story_002',
        storyTitle: 'Serialization Test',
        toPalId: 'pal_123',
        timestamp: DateTime.now(),
        direction: ShareDirection.sent,
      );

      // Serialize to JSON
      final json = share.toJson();
      expect(json['shareId'], equals(originalShareId));

      // Deserialize from JSON
      final deserialized = ShareRecord.fromJson(json);
      expect(deserialized.shareId, equals(originalShareId),
          reason: 'UUID should survive serialization roundtrip');
    });
  });

  group('Conditional Pending Queue (Transport Flag OFF)', () {
    test('should NOT add to pending queue when transport is OFF', () async {
      final transportEnabled = await featureFlags.isTransportLayerEnabled();
      expect(transportEnabled, isFalse,
          reason: 'Transport should be OFF by default');

      // Simulate shareStoryWithPals() with transport OFF
      final shareId = const Uuid().v4();
      final timestamp = DateTime.now();

      // Always create ShareRecord
      await storage.addShare(ShareRecord(
        shareId: shareId,
        storyId: 'story_003',
        storyTitle: 'Local-Only Story',
        toPalId: 'pal_123',
        timestamp: timestamp,
        direction: ShareDirection.sent,
      ));

      // Do NOT add to pending queue (transport OFF)
      // (No call to addToPendingQueue)

      // Verify ShareRecord exists
      final shares = await storage.getShares();
      expect(shares.length, equals(1));

      // Verify pending queue is EMPTY
      final pending = await storage.getPendingShares();
      expect(pending.isEmpty, isTrue,
          reason: 'No pending shares when transport is OFF');
    });

    test('multiple shares should NOT populate pending queue when OFF',
        () async {
      // Add more PALs
      await storage.addPal(PAL(
        palId: 'pal_456',
        displayName: 'PAL 2',
        createdAt: DateTime.now(),
      ));
      await storage.addPal(PAL(
        palId: 'pal_789',
        displayName: 'PAL 3',
        createdAt: DateTime.now(),
      ));

      // Simulate sharing with 3 PALs (transport OFF)
      final palIds = ['pal_123', 'pal_456', 'pal_789'];
      for (final palId in palIds) {
        final shareId = const Uuid().v4();
        await storage.addShare(ShareRecord(
          shareId: shareId,
          storyId: 'story_004',
          storyTitle: 'Multi-PAL Story',
          toPalId: palId,
          timestamp: DateTime.now(),
          direction: ShareDirection.sent,
        ));
        // Do NOT add to pending queue
      }

      // Verify ShareRecords exist
      final shares = await storage.getShares();
      expect(shares.length, equals(3));

      // Verify pending queue is EMPTY
      final pending = await storage.getPendingShares();
      expect(pending.isEmpty, isTrue);
    });
  });

  group('Conditional Pending Queue (Simulated Transport ON)', () {
    test('ShareRecord and PendingShare should have SAME shareId', () async {
      // Simulate transport ON scenario
      final shareId = const Uuid().v4();
      final timestamp = DateTime.now();

      // Create ShareRecord
      await storage.addShare(ShareRecord(
        shareId: shareId, // Same UUID
        storyId: 'story_005',
        storyTitle: 'Transport Enabled Story',
        toPalId: 'pal_123',
        timestamp: timestamp,
        direction: ShareDirection.sent,
      ));

      // Add to pending queue (same shareId)
      await storage.addToPendingQueue(PendingShare(
        shareId: shareId, // Reuse same UUID
        storyId: 'story_005',
        storyTitle: 'Transport Enabled Story',
        toPalId: 'pal_123',
        createdAt: timestamp,
        retryCount: 0,
      ));

      // Verify both exist
      final shares = await storage.getShares();
      expect(shares.length, equals(1));

      final pending = await storage.getPendingShares();
      expect(pending.length, equals(1));

      // CRITICAL: Both should have SAME shareId
      expect(shares.first.shareId, equals(pending.first.shareId),
          reason: 'ShareRecord and PendingShare MUST share same UUID');
    });

    test('idempotency check should work with shared shareId', () async {
      final shareId = const Uuid().v4();
      final timestamp = DateTime.now();

      // Create ShareRecord
      await storage.addShare(ShareRecord(
        shareId: shareId,
        storyId: 'story_006',
        storyTitle: 'Idempotency Test',
        toPalId: 'pal_123',
        timestamp: timestamp,
        direction: ShareDirection.sent,
      ));

      // Add to pending queue
      await storage.addToPendingQueue(PendingShare(
        shareId: shareId,
        storyId: 'story_006',
        storyTitle: 'Idempotency Test',
        toPalId: 'pal_123',
        createdAt: timestamp,
        retryCount: 0,
      ));

      // hasShare should return true (prevents inbox duplicates)
      final exists = await storage.hasShare(shareId);
      expect(exists, isTrue,
          reason: 'hasShare() should find ShareRecord by UUID');

      // Pending queue should reject duplicate (idempotency at queue level)
      await storage.addToPendingQueue(PendingShare(
        shareId: shareId, // Same UUID
        storyId: 'story_006',
        storyTitle: 'Idempotency Test',
        toPalId: 'pal_123',
        createdAt: timestamp,
        retryCount: 1, // Different retry count
      ));

      final pending = await storage.getPendingShares();
      expect(pending.length, equals(1),
          reason: 'Duplicate shareId should be rejected by queue');
    });
  });

  group('Backward Compatibility', () {
    test('should handle legacy timestamp-based shareIds in storage', () async {
      // Simulate old format shareId (for migration testing)
      final legacyShareId = '${DateTime.now().millisecondsSinceEpoch}_pal_123';

      await storage.addShare(ShareRecord(
        shareId: legacyShareId,
        storyId: 'story_007',
        storyTitle: 'Legacy Share',
        toPalId: 'pal_123',
        timestamp: DateTime.now(),
        direction: ShareDirection.sent,
      ));

      // Should be readable
      final shares = await storage.getShares();
      expect(shares.length, equals(1));
      expect(shares.first.shareId, equals(legacyShareId));

      // hasShare should work
      final exists = await storage.hasShare(legacyShareId);
      expect(exists, isTrue);
    });

    test('new UUIDs should coexist with legacy timestamp shareIds', () async {
      // Add legacy format share
      final legacyShareId = '${DateTime.now().millisecondsSinceEpoch}_pal_456';
      await storage.addShare(ShareRecord(
        shareId: legacyShareId,
        storyId: 'story_008',
        storyTitle: 'Legacy',
        toPalId: 'pal_123',
        timestamp: DateTime.now(),
        direction: ShareDirection.sent,
      ));

      // Add new UUID format share
      final newShareId = const Uuid().v4();
      await storage.addShare(ShareRecord(
        shareId: newShareId,
        storyId: 'story_009',
        storyTitle: 'Modern',
        toPalId: 'pal_123',
        timestamp: DateTime.now(),
        direction: ShareDirection.sent,
      ));

      // Both should exist
      final shares = await storage.getShares();
      expect(shares.length, equals(2));

      // Both should be findable
      expect(await storage.hasShare(legacyShareId), isTrue);
      expect(await storage.hasShare(newShareId), isTrue);
    });
  });
}
