import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/services/completed_stories_store.dart';

/// Tests for the ≥ 90% story-body completion rule (SPEC Feature 50.4 — LOCKED).
///
/// These tests verify the completion-trigger semantics at the [CompletedStoriesStore]
/// layer, which is where the player's position listener writes. The player-side
/// position-stream hook itself is exercised by integration tests once real audio
/// is wired (Phase 2+); here we verify the *persistence contract* the player
/// depends on: idempotent, write-once, story-body only.
void main() {
  late StorageService storage;
  late CompletedStoriesStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    store = CompletedStoriesStore(storage);
  });

  /// Simulates the ratio check the player's position listener performs:
  /// position / duration >= 0.90 fires completion exactly once per load.
  Future<void> simulatePlayback({
    required String storyId,
    required int positionMs,
    required int durationMs,
    required bool Function() fireFlagGetter,
    required void Function() fireFlagSetter,
  }) async {
    if (durationMs <= 0) return;
    final ratio = positionMs / durationMs;
    if (ratio >= 0.90 && !fireFlagGetter()) {
      fireFlagSetter();
      await store.markCompleted(storyId);
    }
  }

  group('≥ 90% story-body completion rule (SPEC 50.4)', () {
    test('position at 89.9% does NOT mark complete', () async {
      bool fired = false;
      await simulatePlayback(
        storyId: 'david_001',
        positionMs: 8990,
        durationMs: 10000,
        fireFlagGetter: () => fired,
        fireFlagSetter: () => fired = true,
      );
      expect(fired, isFalse);
      expect(await store.isCompleted('david_001'), isFalse);
    });

    test('position at exactly 90% marks complete', () async {
      bool fired = false;
      await simulatePlayback(
        storyId: 'moses_001',
        positionMs: 9000,
        durationMs: 10000,
        fireFlagGetter: () => fired,
        fireFlagSetter: () => fired = true,
      );
      expect(fired, isTrue);
      expect(await store.isCompleted('moses_001'), isTrue);
    });

    test('position at 99% marks complete', () async {
      bool fired = false;
      await simulatePlayback(
        storyId: 'ruth_001',
        positionMs: 9900,
        durationMs: 10000,
        fireFlagGetter: () => fired,
        fireFlagSetter: () => fired = true,
      );
      expect(fired, isTrue);
      expect(await store.isCompleted('ruth_001'), isTrue);
    });

    test('position at 50% does NOT mark complete', () async {
      bool fired = false;
      await simulatePlayback(
        storyId: 'jonah_001',
        positionMs: 5000,
        durationMs: 10000,
        fireFlagGetter: () => fired,
        fireFlagSetter: () => fired = true,
      );
      expect(fired, isFalse);
      expect(await store.isCompleted('jonah_001'), isFalse);
    });
  });

  group('write-once per load (position stream fires many ticks)', () {
    test('multiple ticks above 90% only persist once', () async {
      bool fired = false;
      // Simulate many position updates after crossing 90% — the player's
      // one-shot flag ensures persistence is called exactly once.
      for (final position in [9000, 9100, 9200, 9500, 9800, 9999]) {
        await simulatePlayback(
          storyId: 'esther_001',
          positionMs: position,
          durationMs: 10000,
          fireFlagGetter: () => fired,
          fireFlagSetter: () => fired = true,
        );
      }
      expect(fired, isTrue);
      expect(await store.completedCount(), 1);
      expect(await store.isCompleted('esther_001'), isTrue);
    });

    test('position crosses 90% then dips below — still marked once', () async {
      bool fired = false;
      await simulatePlayback(
        storyId: 'samuel_001',
        positionMs: 9100,
        durationMs: 10000,
        fireFlagGetter: () => fired,
        fireFlagSetter: () => fired = true,
      );
      // User scrubs backwards below 90%
      await simulatePlayback(
        storyId: 'samuel_001',
        positionMs: 5000,
        durationMs: 10000,
        fireFlagGetter: () => fired,
        fireFlagSetter: () => fired = true,
      );
      // Fires forward again above 90%
      await simulatePlayback(
        storyId: 'samuel_001',
        positionMs: 9500,
        durationMs: 10000,
        fireFlagGetter: () => fired,
        fireFlagSetter: () => fired = true,
      );

      expect(fired, isTrue);
      expect(await store.completedCount(), 1);
    });
  });

  group('store-level idempotency (second safety net)', () {
    test('markCompleted across separate loads is still idempotent', () async {
      // First load: flag starts false, hits 90%, fires.
      bool firedA = false;
      await simulatePlayback(
        storyId: 'elijah_001',
        positionMs: 9500,
        durationMs: 10000,
        fireFlagGetter: () => firedA,
        fireFlagSetter: () => firedA = true,
      );
      expect(await store.completedCount(), 1);

      // Second load of the SAME story: fresh flag, hits 90% again.
      // CompletedStoriesStore.markCompleted() must still be idempotent —
      // this is the second safety net behind the player's one-shot flag.
      bool firedB = false;
      await simulatePlayback(
        storyId: 'elijah_001',
        positionMs: 9500,
        durationMs: 10000,
        fireFlagGetter: () => firedB,
        fireFlagSetter: () => firedB = true,
      );
      expect(await store.completedCount(), 1);
      expect(await store.isCompleted('elijah_001'), isTrue);
    });
  });

  group('duration edge cases', () {
    test('zero duration is guarded (divide-by-zero prevention)', () async {
      bool fired = false;
      await simulatePlayback(
        storyId: 'zero_duration',
        positionMs: 9000,
        durationMs: 0,
        fireFlagGetter: () => fired,
        fireFlagSetter: () => fired = true,
      );
      expect(fired, isFalse);
      expect(await store.isCompleted('zero_duration'), isFalse);
    });

    test('negative duration is guarded', () async {
      bool fired = false;
      await simulatePlayback(
        storyId: 'negative_duration',
        positionMs: 9000,
        durationMs: -1,
        fireFlagGetter: () => fired,
        fireFlagSetter: () => fired = true,
      );
      expect(fired, isFalse);
    });
  });
}
