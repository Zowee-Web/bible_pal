import 'storage_service.dart';

/// Thin wrapper over [StorageService] for PALs Paths completion persistence
/// (SPEC Feature 50.4 + 50.11).
///
/// Semantics:
/// - [markCompleted] is write-once idempotent for a given `storyId`
/// - [isCompleted] reflects durable state (survives app restart)
/// - Capacity is enforced by `StorageService.validateAndHealInvariants()`
///   on startup; the store itself does not re-check caps on every write
///
/// This store is populated when playback reaches ≥ 90% of the story body
/// (Feature 50.4). Reflection playback does not affect completion.
class CompletedStoriesStore {
  final StorageService _storage;

  CompletedStoriesStore(this._storage);

  /// Mark a story as completed. Idempotent — repeated calls for the same
  /// `storyId` are no-ops. No exception is thrown on repeat calls.
  Future<void> markCompleted(String storyId) async {
    await _storage.addCompletedStory(storyId);
  }

  /// True if this story has ever been completed (persisted across restarts).
  Future<bool> isCompleted(String storyId) async {
    return _storage.isStoryCompleted(storyId);
  }

  /// Returns the total number of completed stories. Useful for path
  /// completion percentage computation and for progress badges (Phase 4).
  Future<int> completedCount() async {
    final list = await _storage.getCompletedStories();
    return list.length;
  }

  /// Returns the full set of completed story IDs (insertion order).
  /// Callers should treat this as a set — duplicates are not possible by
  /// construction.
  Future<List<String>> all() async {
    return _storage.getCompletedStories();
  }
}
