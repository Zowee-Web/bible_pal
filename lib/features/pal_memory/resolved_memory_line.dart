import 'package:flutter/foundation.dart' show immutable;

import 'pal_memory_line.dart';

/// A memory line after the display-name lookup and voice selection.
///
/// PAL Memory Doctrine, Slice 2c.2 (see docs/PAL_MEMORY_DOCTRINE.md):
/// the resolved line carries everything an audio layer needs to play
/// the line — clip IDs for the carrier and the name, the active voice
/// — plus enough human-readable metadata for logging, tests, and
/// future analytics.
///
/// Produced by [MemoryLineResolver]. Consumed by [MemoryAudioResolver]
/// which converts it to a [MemoryAudioPlan] (or null if any required
/// clip is missing).
@immutable
class ResolvedMemoryLine {
  /// PAL voice this line was resolved for — `'VOICE_HOPE'` /
  /// `'VOICE_SHEPHERD'` / `'VOICE_STILLWATER'`. Drives the audio path
  /// in [MemoryAudioPlan] (one clip set per voice).
  final String voiceKey;

  /// Stable audio-layer identifier for the carrier clip — e.g.
  /// `'carrier_yesterday_sat_with'`.
  final String carrierClipId;

  /// Stable audio-layer identifier for the display-name clip — e.g.
  /// `'name_daniel'`.
  final String displayNameClipId;

  /// Which recency band produced this line. Preserved through resolution
  /// for downstream tagging and (eventually) audio-render selection.
  final RecencyBand band;

  /// The session this line refers to — useful for analytics and for
  /// callers wanting to navigate to the source story.
  final String sourceStoryId;

  /// The exact phrase PAL will speak as the name — e.g. `'Daniel'`,
  /// `'the Good Samaritan'`. Editorial choice from the display-name
  /// registry; never inferred at runtime.
  final String displayName;

  /// What PAL says before the name — e.g. `'Yesterday you sat with'`.
  /// Carried forward from the originating [PalMemoryLine.carrierText].
  final String carrierText;

  const ResolvedMemoryLine({
    required this.voiceKey,
    required this.carrierClipId,
    required this.displayNameClipId,
    required this.band,
    required this.sourceStoryId,
    required this.displayName,
    required this.carrierText,
  });

  /// The full line as PAL would speak it — useful for logging and for
  /// asserting "this is the right line" in tests without going through
  /// audio. Composed deterministically: `'$carrierText $displayName.'`.
  String get fullText => '$carrierText $displayName.';
}
