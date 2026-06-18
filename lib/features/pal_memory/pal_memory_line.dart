import 'package:flutter/foundation.dart' show immutable;

/// How long ago the source session was completed, relative to "now."
/// Drives template selection in [PalMemoryEngine] so that what PAL says
/// matches what is actually true ("yesterday" must really mean yesterday).
enum RecencyBand {
  /// Source session completed on the previous calendar day.
  yesterday,

  /// Source session completed 2–4 calendar days ago.
  fewDaysAgo,

  /// Source session completed 5–7 calendar days ago.
  earlierThisWeek,
}

/// What PAL would say next, returned by [PalMemoryEngine.nextLine].
///
/// PAL Memory Doctrine Slice 2a (see docs/PAL_MEMORY_DOCTRINE.md):
/// observational only, deterministic, no inference about the user's
/// interior state. The `{storyName}` placeholder is intentionally left
/// unresolved — Slice 2b plugs in a parable/character-registry resolver
/// at delivery time. Slice 2a stays a pure function over its inputs and
/// has no opinion about how or whether the line gets spoken.
@immutable
class PalMemoryLine {
  /// Template string. Contains the `{storyName}` placeholder. Slice 2a
  /// guarantees the template was drawn from [PalMemoryTemplates] and
  /// therefore passes the observation-only audit.
  final String template;

  /// Which recency band produced this line. Useful for downstream
  /// analytics and (in Slice 2b) for selecting pre-rendered audio.
  final RecencyBand band;

  /// Story this line refers to. Slice 2b resolves the placeholder using
  /// this id (via the parable manifest) or [sourceBibleStoryKey] (via
  /// the character registry).
  final String sourceStoryId;
  final String? sourceBibleStoryKey;

  const PalMemoryLine({
    required this.template,
    required this.band,
    required this.sourceStoryId,
    this.sourceBibleStoryKey,
  });
}
