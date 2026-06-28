import 'package:flutter/foundation.dart' show immutable;

/// The kinds of clip a journey audio plan can carry.
///
/// For Slice 2 first ship the populated kinds are:
///   - ADULT offer: a single [offer] clip
///   - KID offer:   [carrier] + [name] + [invitation] (stitched)
///   - BOTH lanes also carry a single [decline] clip, played
///     separately if the user declines / sends a mood phrase /
///     gives an ambiguous response
enum JourneyClipKind { offer, carrier, name, invitation, decline }

/// One clip reference inside a [JourneyAudioPlan]. Carries the
/// clipId for telemetry / debugging, the kind for cascade-side
/// branching, and the resolved bundled-asset path for the player.
@immutable
class JourneyAudioClipRef {
  final String clipId;
  final JourneyClipKind kind;
  final String assetPath;

  const JourneyAudioClipRef({
    required this.clipId,
    required this.kind,
    required this.assetPath,
  });
}

/// Pure data — what to play for a journey continuation offer.
///
/// Journey Doctrine Slice 2 Phase 6 (docs/JOURNEY_DOCTRINE.md):
/// parallel to [MemoryAudioPlan]. The resolver produces this; the
/// cascade (Phase 9) materializes it into a `ConcatenatingAudioSource`
/// for the [offerClips] portion, and plays the [declineClip] as a
/// separate audio event on declined / mood-redirect / gentle-default
/// responses.
///
/// Structural invariants (enforced by [validateStructure]):
///   - offerClips MUST be non-empty
///   - offerGapsBetween.length == offerClips.length - 1
///   - declineClip.kind == JourneyClipKind.decline
@immutable
class JourneyAudioPlan {
  /// Voice this plan was resolved for. Matches the bundled-asset
  /// path segment (`assets/pal/audio/<voiceKey>/journey/...`).
  final String voiceKey;

  /// Ordered clip sequence for the OFFER playback.
  /// Adult: 1 clip ([JourneyClipKind.offer]).
  /// Kid:   3 clips ([carrier], [name], [invitation]).
  final List<JourneyAudioClipRef> offerClips;

  /// Silences inserted between adjacent [offerClips]. Length is
  /// `offerClips.length - 1` (no leading/trailing silence). Adult
  /// plans have an empty list; kid plans have 2 entries.
  final List<Duration> offerGapsBetween;

  /// Standalone decline clip — played separately by the cascade on
  /// declined / mood-redirect / gentle-default responses. Always
  /// present in a plan, but only triggered on the non-accept branch.
  final JourneyAudioClipRef declineClip;

  const JourneyAudioPlan({
    required this.voiceKey,
    required this.offerClips,
    required this.offerGapsBetween,
    required this.declineClip,
  });

  /// Throws [StateError] if any structural invariant is violated.
  /// Mirrors the Slice 2c.2 MemoryAudioPlan validateStructure call.
  void validateStructure() {
    if (offerClips.isEmpty) {
      throw StateError(
          'JourneyAudioPlan.offerClips must be non-empty (voiceKey=$voiceKey)');
    }
    if (offerGapsBetween.length != offerClips.length - 1) {
      throw StateError(
          'JourneyAudioPlan.offerGapsBetween must have length '
          '${offerClips.length - 1} (= offerClips.length - 1); '
          'got ${offerGapsBetween.length} (voiceKey=$voiceKey)');
    }
    if (declineClip.kind != JourneyClipKind.decline) {
      throw StateError(
          'JourneyAudioPlan.declineClip must have kind=decline; '
          'got kind=${declineClip.kind} (voiceKey=$voiceKey)');
    }
  }
}
