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
/// unresolved — the Slice 2c.2 resolver substitutes it using the
/// editorial display-name registry. Slice 2a stays a pure function over
/// its inputs and has no opinion about how or whether the line gets spoken.
@immutable
class PalMemoryLine {
  /// Template string with the `{storyName}` placeholder. Slice 2a
  /// guarantees the template was drawn from [PalMemoryTemplates] and
  /// therefore passes the observation-only audit.
  final String template;

  /// Stable audio-layer identifier for the carrier (the part of the line
  /// PAL says before the display name). Slice 2c.2 added this so the
  /// resolver and the audio inventory validator can locate the
  /// pre-rendered clip without parsing the template string. Mirrors the
  /// `carrierClipId` on the [PalMemoryTemplateVariant] that produced
  /// this line.
  final String carrierClipId;

  /// Human-readable carrier text — what PAL says before the display name.
  /// e.g. `'Yesterday you sat with'`. Mirrors the variant's `carrierText`;
  /// exposed on the line so the resolver doesn't have to reverse-parse
  /// the template string.
  final String carrierText;

  /// Which recency band produced this line. Useful for downstream
  /// analytics and for selecting pre-rendered audio.
  final RecencyBand band;

  /// Story this line refers to. The Slice 2c.2 resolver looks up the
  /// editorial display name by [sourceBibleStoryKey] in the
  /// display-name registry; falls through to silence when the key is
  /// absent (opt-out).
  final String sourceStoryId;
  final String? sourceBibleStoryKey;

  const PalMemoryLine({
    required this.template,
    required this.carrierClipId,
    required this.carrierText,
    required this.band,
    required this.sourceStoryId,
    this.sourceBibleStoryKey,
  });
}
