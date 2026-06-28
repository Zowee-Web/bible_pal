import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'pal_session.dart';

/// Thin wrapper over [StorageService] for PAL memory session persistence.
///
/// Slice 1 of the PAL Memory Doctrine — see docs/PAL_MEMORY_DOCTRINE.md.
/// Writes one [PalSession] per completed story playback (≥90% playback,
/// aligned with the existing SPEC Feature 50.4 completion threshold).
/// Provides the read API that future Level 2 (Facts) templates consume —
/// the doctrine's first user-visible memory line surfaces from
/// [getMostRecentCompleted].
///
/// Storage is centralised in [StorageService] for parity with other
/// stores (CompletedStoriesStore, play log, history). Cap = 1000 sessions,
/// FIFO eviction by completion timestamp; healing on startup mirrors the
/// play log.
class PalSessionStore {
  final StorageService _storage;

  PalSessionStore(this._storage);

  /// Record a completed-story session. Snapshots every memory-relevant
  /// field from [parable] at completion time so future reads don't need to
  /// re-resolve the manifest (manifest entries can change after the user
  /// hears them).
  ///
  /// [mood] should be the user's last-detected mood at the moment of
  /// completion; pass null when the entry point bypasses the mood picker.
  /// [at] defaults to `DateTime.now()` and exists for deterministic tests.
  ///
  /// Append-only. Re-listening to the same story creates a fresh entry,
  /// not an update — the doctrine cares about journey, not uniqueness.
  Future<void> recordCompletion(
    Parable parable, {
    String? mood,
    DateTime? at,
  }) async {
    final session = PalSession(
      storyId: parable.storyId,
      completedAt: at ?? DateTime.now(),
      mood: mood,
      themeTags: parable.themeTags ?? const <String>[],
      emotionalTags: parable.emotionalTags,
      scriptureAnchor: parable.bibleSourceRef,
      bibleStoryKey: parable.bibleStoryKey,
      storyLength: parable.storyLength,
      languageStyle: parable.languageStyle,
    );
    await _storage.addPalSession(session);
  }

  /// Returns the most recently completed session within [within], or null
  /// if none exist. The default 14-day window is wide enough to feel like
  /// continuation and tight enough that a months-old session never
  /// surfaces as "yesterday."
  Future<PalSession?> getMostRecentCompleted({
    Duration within = const Duration(days: 14),
  }) async {
    final sessions = await _storage.getPalSessions();
    if (sessions.isEmpty) return null;
    final cutoff = DateTime.now().subtract(within);
    // Sessions persisted append-order (newest at tail). Iterate in reverse
    // to find the newest in-window session in one pass.
    for (final s in sessions.reversed) {
      if (s.completedAt.isAfter(cutoff)) return s;
    }
    return null;
  }

  /// Record that PAL just spoke a memory line. The single truthful
  /// producer of the `lastSpokenAt` value fed back into
  /// [PalMemoryEngine.nextLine] as the cooldown anchor.
  ///
  /// PAL Memory Doctrine, Slice 2d (see docs/PAL_MEMORY_DOCTRINE.md):
  /// callers must invoke this ONLY after the carrier+name plan finished
  /// playing successfully. A render gap, missing clip, or playback
  /// failure must NOT advance the cooldown — otherwise PAL falls silent
  /// for the next 3 days for a line the user never actually heard.
  ///
  /// [at] defaults to `DateTime.now()` and exists for deterministic tests.
  Future<void> recordMemoryLineSpoken({DateTime? at}) async {
    await _storage.setLastMemoryLineSpokenAt(at ?? DateTime.now());
  }

  /// Returns when PAL last spoke a memory line, or null if PAL has
  /// never spoken one for this user. Pass-through over
  /// [StorageService.getLastMemoryLineSpokenAt] so consumers depend on
  /// [PalSessionStore] for both the session log and the cooldown anchor.
  Future<DateTime?> getLastMemoryLineSpokenAt() async {
    return _storage.getLastMemoryLineSpokenAt();
  }

  /// Record that PAL just spoke a journey-continuation offer. The
  /// single truthful producer of the `lastJourneyContinuationSpokenAt`
  /// value fed back into `JourneyEngine.nextOffer` as the cooldown
  /// anchor (3-day cooldown, adult lane only; kid lane bypasses per
  /// the doctrine's Continuation Invariant rule 3).
  ///
  /// Journey Doctrine, Slice 2 Phase 5 (docs/JOURNEY_DOCTRINE.md):
  /// callers must invoke this ONLY after the offer line + carrier
  /// finished playing successfully. A missing clip, audio failure,
  /// or user-cancelled offer must NOT advance the cooldown —
  /// otherwise PAL falls silent for the next 3 days for an offer the
  /// user never actually heard.
  ///
  /// [at] defaults to `DateTime.now()` and exists for deterministic tests.
  Future<void> recordJourneyContinuationSpoken({DateTime? at}) async {
    await _storage.setLastJourneyContinuationSpokenAt(at ?? DateTime.now());
  }

  /// Returns when PAL last spoke a journey-continuation offer, or null
  /// if PAL has never spoken one. Pass-through over
  /// [StorageService.getLastJourneyContinuationSpokenAt].
  Future<DateTime?> getLastJourneyContinuationSpokenAt() async {
    return _storage.getLastJourneyContinuationSpokenAt();
  }

  /// Returns every persisted session in append order (oldest first).
  /// Reserved for future Level 2 / Level 3 pattern detection — Slice 1
  /// exposes it for tests and forward compatibility, not for UI.
  Future<List<PalSession>> all() async {
    return _storage.getPalSessions();
  }

  /// Wipe every persisted session AND both cooldown anchors (memory
  /// line + journey continuation). Trust-protective entry point for
  /// the future "Clear PAL Memory" settings hook described in
  /// docs/PAL_MEMORY_DOCTRINE.md.
  ///
  /// Wiping all three ensures that after a clear, PAL is silent only
  /// because the engines' minimum gates have reset — never because a
  /// stale cooldown timestamp from before the wipe lingers. The
  /// journey cooldown is included here per Journey Doctrine Slice 2
  /// Phase 5 (same reasoning as the memory-line cooldown wipe).
  Future<void> clear() async {
    await _storage.clearPalSessions();
    await _storage.clearLastMemoryLineSpokenAt();
    await _storage.clearLastJourneyContinuationSpokenAt();
  }
}
