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

  /// Returns every persisted session in append order (oldest first).
  /// Reserved for future Level 2 / Level 3 pattern detection — Slice 1
  /// exposes it for tests and forward compatibility, not for UI.
  Future<List<PalSession>> all() async {
    return _storage.getPalSessions();
  }

  /// Wipe every persisted session. Trust-protective entry point for the
  /// future "Clear PAL Memory" settings hook described in
  /// docs/PAL_MEMORY_DOCTRINE.md. Slice 1 has no UI consumer; the method
  /// exists so it's plumbed when the settings screen needs it.
  Future<void> clear() async {
    await _storage.clearPalSessions();
  }
}
