import '../models/parable.dart';
import 'mood_similarity.dart';

/// Result of mood-expanded story selection.
/// [servedMood] may differ from the caller's selectedMood when expansion is used.
class SelectionResult {
  final Parable parable;

  /// The actual mood of the story returned.
  final String servedMood;

  /// Which priority tier produced this result (1-4).
  final int tier;

  /// All candidates in the winning tier, LRP-sorted.
  /// Callers may re-rank this list (e.g., relatability, seasonal boost)
  /// and pick a different candidate while staying within the correct tier.
  final List<Parable> tierCandidates;

  const SelectionResult({
    required this.parable,
    required this.servedMood,
    required this.tier,
    this.tierCandidates = const [],
  });
}

/// Pure 4-tier mood expansion algorithm per SPEC.md 15b.
///
/// Priority order:
///   1. exact selected mood + unseen
///   2. similar moods + unseen
///   3. exact selected mood + seen, least-recently-played first
///   4. similar moods + seen, least-recently-played first
class MoodExpansionEngine {
  const MoodExpansionEngine();

  /// Select a story from [pool] using the 4-tier priority.
  ///
  /// [selectedMood] — the mood the user chose.
  /// [pool] — all stories that pass non-mood filters (length, mode, kid safety, etc.).
  /// [playedStoryIds] — set of story IDs the user has already seen.
  /// [playHistory] — map of storyId → last played time (for LRP ordering).
  SelectionResult? select({
    required String selectedMood,
    required List<Parable> pool,
    required Set<String> playedStoryIds,
    Map<String, DateTime> playHistory = const {},
  }) {
    final exactPool = pool.where((p) => p.mood == selectedMood).toList();
    final similarMoods = MoodSimilarity.getSimilar(selectedMood);
    final similarPool =
        pool.where((p) => similarMoods.contains(p.mood)).toList();

    // Tier 1: exact mood + unseen
    final exactUnseen =
        exactPool.where((p) => !playedStoryIds.contains(p.storyId)).toList();
    if (exactUnseen.isNotEmpty) {
      final sorted = _sortLRP(exactUnseen, playHistory);
      return SelectionResult(
        parable: sorted.first,
        servedMood: selectedMood,
        tier: 1,
        tierCandidates: sorted,
      );
    }

    // Tier 2: similar moods + unseen
    final similarUnseen =
        similarPool.where((p) => !playedStoryIds.contains(p.storyId)).toList();
    if (similarUnseen.isNotEmpty) {
      final sorted = _sortLRP(similarUnseen, playHistory);
      return SelectionResult(
        parable: sorted.first,
        servedMood: sorted.first.mood,
        tier: 2,
        tierCandidates: sorted,
      );
    }

    // Tier 3: exact mood + seen, LRP order
    if (exactPool.isNotEmpty) {
      final sorted = _sortLRP(exactPool, playHistory);
      return SelectionResult(
        parable: sorted.first,
        servedMood: selectedMood,
        tier: 3,
        tierCandidates: sorted,
      );
    }

    // Tier 4: similar moods + seen, LRP order
    if (similarPool.isNotEmpty) {
      final sorted = _sortLRP(similarPool, playHistory);
      return SelectionResult(
        parable: sorted.first,
        servedMood: sorted.first.mood,
        tier: 4,
        tierCandidates: sorted,
      );
    }

    return null;
  }

  /// Sort candidates by least-recently-played. Never-played sorts first.
  /// Stable tie-break by storyId.
  List<Parable> _sortLRP(
      List<Parable> candidates, Map<String, DateTime> playHistory) {
    final sorted = List<Parable>.from(candidates);
    sorted.sort((a, b) {
      final aTime = playHistory[a.storyId];
      final bTime = playHistory[b.storyId];
      if (aTime == null && bTime != null) return -1;
      if (aTime != null && bTime == null) return 1;
      if (aTime != null && bTime != null) {
        final cmp = aTime.compareTo(bTime);
        if (cmp != 0) return cmp;
      }
      return a.storyId.compareTo(b.storyId);
    });
    return sorted;
  }
}
