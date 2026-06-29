import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import 'journey.dart';
import 'journey_audio_paths.dart';
import 'journey_audio_plan.dart';
import 'journey_audio_resolver.dart';
import 'journey_continuation_offer.dart';

/// Bundled-asset [JourneyAudioResolver] — checks the runtime asset
/// manifest for every required clip and returns a plan only when
/// ALL clips exist for the active voice.
///
/// Journey Doctrine Slice 2 Phase 6 — silence-floor honest: missing
/// clip means silence, never fallback. Mirrors the shape of
/// `BundledAssetMemoryAudioResolver` (Slice 2c.3).
///
/// The set of bundled paths is captured once at construction time so
/// every [resolve] call is a synchronous Set lookup. Production
/// callers use the [load] factory; tests construct directly with a
/// synthetic path set.
class BundledAssetJourneyAudioResolver implements JourneyAudioResolver {
  /// Full bundled-asset paths of every PAL journey audio clip that
  /// exists in the bundle at construction time.
  final Set<String> bundledPaths;

  const BundledAssetJourneyAudioResolver(this.bundledPaths);

  /// Production factory — loads [AssetManifest] from [rootBundle]
  /// and filters to PAL journey audio paths
  /// (`assets/pal/audio/*/journey/*.mp3`).
  static Future<BundledAssetJourneyAudioResolver> load() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    const prefix = 'assets/pal/audio/';
    const journeyFragment = '/journey/';
    final paths = manifest
        .listAssets()
        .where((p) =>
            p.startsWith(prefix) &&
            p.contains(journeyFragment) &&
            p.endsWith('.mp3'))
        .toSet();
    return BundledAssetJourneyAudioResolver(paths);
  }

  @override
  Future<JourneyAudioPlan?> resolve({
    required JourneyContinuationOffer offer,
    required String activeVoiceKey,
  }) async {
    if (offer.journey.lane == JourneyLane.adult) {
      return _resolveAdult(activeVoiceKey);
    } else {
      return _resolveKid(offer, activeVoiceKey);
    }
  }

  // ------------------------------------------------------------
  // ADULT — one generic offer clip + one generic decline clip.
  // No per-journey customization (per Cascade Option C lock).
  // ------------------------------------------------------------
  JourneyAudioPlan? _resolveAdult(String voiceKey) {
    const offerClipId = 'offer_narrative_adult';
    const declineClipId = 'decline_adult';

    final offerPath = PalJourneyAudioPaths.assetPathFor(
        voiceKey: voiceKey, clipId: offerClipId);
    final declinePath = PalJourneyAudioPaths.assetPathFor(
        voiceKey: voiceKey, clipId: declineClipId);

    if (!bundledPaths.contains(offerPath)) return null;
    if (!bundledPaths.contains(declinePath)) return null;

    return JourneyAudioPlan(
      voiceKey: voiceKey,
      offerClips: [
        JourneyAudioClipRef(
          clipId: offerClipId,
          kind: JourneyClipKind.offer,
          assetPath: offerPath,
        ),
      ],
      offerGapsBetween: const [],
      declineClip: JourneyAudioClipRef(
        clipId: declineClipId,
        kind: JourneyClipKind.decline,
        assetPath: declinePath,
      ),
    );
  }

  // ------------------------------------------------------------
  // KID — MONOLITHIC per-journey offer clip + generic decline.
  //
  // Pivot 2026-06-28 after Adam ear-checked the compositional
  // (carrier+name+invitation) version: standalone 1-syllable name
  // clips sound punched-out even with v3, because the model has no
  // sentence-context for natural prosody (compare: "Hey, Adam!"
  // sounds natural because the name is in a phrase). Kid offers
  // now ship as one full-line clip per journey:
  //   clipId convention: '<journeyId>_offer' (e.g.
  //   'kid_david_arc_offer' for Kid David Arc)
  // Each new kid journey adds one full-line render per voice
  // (~30 credits / ~$0.30 per voice per kid journey).
  //
  // The generic kid clips left over from the compositional design
  // (carrier_narrative_kid, invitation_narrative_kid,
  // name_<x>_journey) remain bundled per [feedback_never_delete_audio]
  // but the resolver no longer references them.
  // ------------------------------------------------------------
  JourneyAudioPlan? _resolveKid(
      JourneyContinuationOffer offer, String voiceKey) {
    final offerClipId = '${offer.journey.journeyId}_offer';
    const declineClipId = 'decline_kid';

    final offerPath = PalJourneyAudioPaths.assetPathFor(
        voiceKey: voiceKey, clipId: offerClipId);
    final declinePath = PalJourneyAudioPaths.assetPathFor(
        voiceKey: voiceKey, clipId: declineClipId);

    // Silence-floor: either clip missing → null. No partial plans.
    if (!bundledPaths.contains(offerPath)) return null;
    if (!bundledPaths.contains(declinePath)) return null;

    return JourneyAudioPlan(
      voiceKey: voiceKey,
      offerClips: [
        JourneyAudioClipRef(
          clipId: offerClipId,
          kind: JourneyClipKind.offer,
          assetPath: offerPath,
        ),
      ],
      offerGapsBetween: const [],
      declineClip: JourneyAudioClipRef(
        clipId: declineClipId,
        kind: JourneyClipKind.decline,
        assetPath: declinePath,
      ),
    );
  }
}
