import 'package:flutter/foundation.dart' show immutable;

import 'pal_memory_line.dart';

/// One wording variant inside [PalMemoryTemplates].
///
/// PAL Memory Doctrine Slice 2c.2: each variant carries both the spoken
/// text (the "carrier" — everything PAL says before the story's display
/// name) AND a stable [carrierClipId] that maps to the pre-rendered
/// audio clip for that fragment. The display name itself is stitched in
/// at delivery time via the display-name registry; templates are
/// end-placeholder so the audio path is always carrier-then-name (no
/// middle-placeholder variants that would require a third clip).
@immutable
class PalMemoryTemplateVariant {
  /// Audio-layer identifier — `carrier_yesterday_sat_with` becomes
  /// `pal/audio/<VOICE>/memory/carrier_yesterday_sat_with.mp3` per voice.
  /// Must be filesystem-safe (lowercase, alphanumeric, underscores only).
  final String carrierClipId;

  /// The spoken text PAL utters before the display name. Does NOT include
  /// the placeholder; [fullTemplate] adds it. Example:
  /// `'Yesterday you sat with'`.
  final String carrierText;

  const PalMemoryTemplateVariant({
    required this.carrierClipId,
    required this.carrierText,
  });

  /// Full template text with the [PalMemoryTemplates.storyNamePlaceholder]
  /// appended and a trailing period. The resolver substitutes the
  /// placeholder with the registered display name at delivery time.
  String get fullTemplate =>
      '$carrierText ${PalMemoryTemplates.storyNamePlaceholder}.';
}

/// Versioned registry of memory-line templates.
///
/// PAL Memory Doctrine Slice 2a (see docs/PAL_MEMORY_DOCTRINE.md):
/// every template here is observational ("you sat with", "you spent
/// time with", "you listened to") and ends with the display name so
/// audio delivery is always a clean carrier-then-name stitch. New
/// variants MUST pass the observation-only audit in
/// `pal_memory_templates_test.dart` — never edit a template without
/// updating the audit if a new verb is introduced.
///
/// The list is intentionally small. The doctrine prefers a few well-aged
/// lines spoken rarely over a sprawling registry that drifts into
/// inference territory. Grow this list only under explicit editorial
/// review — same discipline as the story corpus.
///
/// Slice 2c.2 note: the prior `"I remember {storyName} from yesterday."`
/// middle-placeholder variants were removed in favor of three uniformly
/// end-placeholder variants per band (sat-with / spent-time-with /
/// listened-to). End-placeholder is the structural requirement for the
/// stitched-clip audio architecture in [PalMemoryDoctrine §Slice 2b].
class PalMemoryTemplates {
  PalMemoryTemplates._();

  /// The literal placeholder substring that the resolver replaces with
  /// the registered display name at delivery time.
  static const String storyNamePlaceholder = '{storyName}';

  static const Map<RecencyBand, List<PalMemoryTemplateVariant>> _registry = {
    RecencyBand.yesterday: [
      PalMemoryTemplateVariant(
        carrierClipId: 'carrier_yesterday_sat_with',
        carrierText: 'Yesterday you sat with',
      ),
      PalMemoryTemplateVariant(
        carrierClipId: 'carrier_yesterday_spent_time_with',
        carrierText: 'Yesterday you spent time with',
      ),
      PalMemoryTemplateVariant(
        carrierClipId: 'carrier_yesterday_listened_to',
        carrierText: 'Yesterday you listened to',
      ),
    ],
    RecencyBand.fewDaysAgo: [
      PalMemoryTemplateVariant(
        carrierClipId: 'carrier_few_days_ago_sat_with',
        carrierText: 'A few days ago you sat with',
      ),
      PalMemoryTemplateVariant(
        carrierClipId: 'carrier_few_days_ago_spent_time_with',
        carrierText: 'A few days ago you spent time with',
      ),
      PalMemoryTemplateVariant(
        carrierClipId: 'carrier_few_days_ago_listened_to',
        carrierText: 'A few days ago you listened to',
      ),
    ],
    RecencyBand.earlierThisWeek: [
      PalMemoryTemplateVariant(
        carrierClipId: 'carrier_earlier_this_week_sat_with',
        carrierText: 'Earlier this week you sat with',
      ),
      PalMemoryTemplateVariant(
        carrierClipId: 'carrier_earlier_this_week_spent_time_with',
        carrierText: 'Earlier this week you spent time with',
      ),
      PalMemoryTemplateVariant(
        carrierClipId: 'carrier_earlier_this_week_listened_to',
        carrierText: 'Earlier this week you listened to',
      ),
    ],
  };

  /// Wording variants for the given recency band. Engine picks one
  /// deterministically per source session so the same session never
  /// produces two different lines on repeat queries.
  static List<PalMemoryTemplateVariant> variantsFor(RecencyBand band) =>
      _registry[band] ?? const <PalMemoryTemplateVariant>[];

  /// Flat view over every variant. Used by the observation-only audit
  /// and (in Slice 2c.3) by the audio inventory validator to enumerate
  /// every carrier clip the engine could ever fire.
  static Iterable<PalMemoryTemplateVariant> all() =>
      _registry.values.expand((v) => v);
}
