import '../core/relatability_tags.dart';
import '../models/parable.dart';

/// Relatability Matcher - extracts tags from user input and ranks stories.
///
/// Algorithm (v1):
/// A) Normalize input (lowercase, trim, collapse spaces, normalize apostrophes)
/// B) If low-signal or too short → return empty tags
/// C) Extract all matching tags (unique), cap at 3 in tagOrder priority
/// D) Score = count of matches between extracted tags and story.emotionalTags
/// E) Tie-break: least-recently-played timestamp, then storyId ascending
class RelatabilityMatcher {
  /// Normalize user input for matching.
  /// - Lowercase
  /// - Trim whitespace
  /// - Collapse multiple spaces to single space
  /// - Normalize smart apostrophes to standard apostrophe
  String normalizeInput(String input) {
    return input
        .toLowerCase()
        .trim()
        // Normalize smart apostrophes
        .replaceAll(''', "'")
        .replaceAll(''', "'")
        .replaceAll('"', '"')
        .replaceAll('"', '"')
        // Collapse multiple spaces
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Check if input is low-signal and should skip matching.
  bool isLowSignal(String normalizedInput) {
    if (normalizedInput.length < minInputLength) {
      return true;
    }
    if (lowSignalInputs.contains(normalizedInput)) {
      return true;
    }
    return false;
  }

  /// Extract relatability tags from user input text.
  /// Returns up to [maxExtractedTags] tags in [tagOrder] priority.
  Set<String> extractTags(String userText) {
    final normalized = normalizeInput(userText);

    if (isLowSignal(normalized)) {
      return {};
    }

    final extracted = <String>{};

    // Iterate in explicit tagOrder for deterministic results
    for (final tag in tagOrder) {
      final keywords = tagKeywords[tag];
      if (keywords == null) continue;

      // Check if any keyword matches via substring
      for (final keyword in keywords) {
        if (normalized.contains(keyword)) {
          extracted.add(tag);
          break; // Only add tag once, move to next tag
        }
      }

      // Cap at max tags
      if (extracted.length >= maxExtractedTags) {
        break;
      }
    }

    return extracted;
  }

  /// Calculate relatability score for a parable.
  /// Score = count of extracted tags that appear in parable.emotionalTags.
  int scoreParable(Set<String> extractedTags, Parable parable) {
    if (extractedTags.isEmpty) return 0;

    final storyTags = parable.emotionalTags.toSet();
    return extractedTags.intersection(storyTags).length;
  }

  /// Rank parables by relatability score.
  ///
  /// Parameters:
  /// - [userText]: Raw user input text
  /// - [candidates]: Pre-filtered eligible parables (already respects invariants)
  /// - [playHistory]: Map of storyId -> last played timestamp (for tie-breaking)
  ///
  /// Returns candidates sorted by:
  /// 1. Relatability score (descending)
  /// 2. Least-recently-played (ascending timestamp, null = never played = lowest)
  /// 3. StoryId (ascending, for stable determinism)
  ///
  /// If extractedTags is empty (low-signal input), returns candidates unchanged.
  List<Parable> rankByRelatability(
    String userText,
    List<Parable> candidates, {
    Map<String, DateTime>? playHistory,
  }) {
    if (candidates.isEmpty) return [];

    final extractedTags = extractTags(userText);

    // If no tags extracted (low-signal), return original order
    if (extractedTags.isEmpty) {
      return List.from(candidates);
    }

    // Score all candidates
    final scored = candidates.map((p) {
      return _ScoredParable(
        parable: p,
        score: scoreParable(extractedTags, p),
        lastPlayed: playHistory?[p.storyId],
      );
    }).toList();

    // Sort by score desc, then lastPlayed asc (null first), then storyId asc
    scored.sort((a, b) {
      // Primary: score descending
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;

      // Secondary: least-recently-played (null = never played = comes first)
      final aTime = a.lastPlayed;
      final bTime = b.lastPlayed;
      if (aTime == null && bTime != null) return -1;
      if (aTime != null && bTime == null) return 1;
      if (aTime != null && bTime != null) {
        final timeCompare = aTime.compareTo(bTime);
        if (timeCompare != 0) return timeCompare;
      }

      // Tertiary: storyId ascending for stable determinism
      return a.parable.storyId.compareTo(b.parable.storyId);
    });

    return scored.map((s) => s.parable).toList();
  }
}

/// Internal helper for sorting parables with scores.
class _ScoredParable {
  final Parable parable;
  final int score;
  final DateTime? lastPlayed;

  _ScoredParable({
    required this.parable,
    required this.score,
    this.lastPlayed,
  });
}
