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
  });
}
