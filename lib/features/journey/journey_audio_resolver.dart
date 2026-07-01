import 'journey_audio_plan.dart';
import 'journey_continuation_offer.dart';

/// Interface for resolving a [JourneyContinuationOffer] into a
/// [JourneyAudioPlan] — Journey Doctrine Slice 2 Phase 6 (parallel
/// to Slice 2c.2's [MemoryAudioResolver]).
///
/// **Doctrine contract — silence floor:** if ANY required clip is
/// missing from the bundle for the active voice, the resolver MUST
/// return null. Never fall back to alternate voices, never substitute
/// runtime TTS, never emit a partial plan. The cascade (Phase 9)
/// treats null as "stay silent and proceed to mood-flow."
abstract class JourneyAudioResolver {
  Future<JourneyAudioPlan?> resolve({
    required JourneyContinuationOffer offer,
    required String activeVoiceKey,
    JourneyOfferVariant variant = JourneyOfferVariant.full,
  });
}

/// Two variants of the journey offer audio — chosen by entry point.
///
/// - [full]: cold-open cascade. Ends with the redirect clause
///   (*"…or, tell me what's on your heart today"* adult /
///   *"…or, what's on your mind?"* kid). The offer IS the cold-open
///   greeting; user has expressed no intent yet, so PAL invites both
///   the continuation AND the mood-flow.
///
/// - [short]: mood-button cascade. Ends after *"…if you'd like to
///   hear it"* — no redirect clause. The user already tapped a mood,
///   so an "or, tell me what's on your heart" question would be
///   contradictory. On silence/decline, the runtime does NOT play
///   the decline clip (user already chose a path); the caller
///   proceeds with the tapped mood.
///
/// Convention: full-variant clip id is `<journeyId>_offer_<idx>`;
/// short-variant clip id is `<journeyId>_offer_<idx>_short`.
enum JourneyOfferVariant { full, short }
