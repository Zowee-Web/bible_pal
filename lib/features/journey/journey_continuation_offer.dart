import 'package:flutter/foundation.dart' show immutable;

import '../pal_memory/pal_session.dart';
import 'journey.dart';

/// What the [JourneyEngine] returns when PAL has a continuation to
/// offer: which journey, which session triggered it, and which story
/// would play if the user accepts.
///
/// Pure data — no behavior, no audio composition. The cascade layer
/// (Slice 2 Phase 9, the extended `fireMemoryLine`) turns this into
/// an audio plan + telemetry + cooldown advancement.
///
/// Journey Doctrine, Continuation Invariant rule 1: presence of an
/// offer is NEVER a requirement that PAL speak. The cascade may still
/// stay silent if, for example, a journey-type-specific offer-line
/// clip is missing for the active voice (silence-floor honesty
/// inherited from PAL Memory Slice 2c.3).
@immutable
class JourneyContinuationOffer {
  /// The journey the source session belongs to.
  final Journey journey;

  /// The completed session that triggered this offer (always the
  /// newest in-journey session per Slice 2's strict-newest rule).
  final PalSession sourceSession;

  /// 0-based index of [sourceSession]'s story in [journey].stories.
  final int sourceStoryIndex;

  /// 0-based index of the proposed next story = sourceStoryIndex + 1.
  final int nextStoryIndex;

  /// The story slot PAL would play if the user accepts.
  final JourneyStory nextStory;

  const JourneyContinuationOffer({
    required this.journey,
    required this.sourceSession,
    required this.sourceStoryIndex,
    required this.nextStoryIndex,
    required this.nextStory,
  });
}
