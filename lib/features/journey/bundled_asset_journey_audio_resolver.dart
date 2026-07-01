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
    JourneyOfferVariant variant = JourneyOfferVariant.full,
  }) async {
    // Both lanes resolve to the same monolithic shape (since the
    // adult pivot 2026-06-28): one per-source-story offer clip +
    // one lane-specific decline clip. The only lane difference is
    // the decline-clip ID. Variant selects between full-offer
    // (cold-open) and short-offer (mood-button) — see
    // [JourneyOfferVariant].
    return _resolve(offer, activeVoiceKey, variant);
  }

  // ------------------------------------------------------------
  // Per-source-story MONOLITHIC offer + lane-specific decline.
  //
  // FINAL Slice 2 audio shape (2026-06-28). Convergence after a
  // two-step pivot:
  //   1. Compositional carrier+name+invitation stitch was retired
  //      after Adam ear-checked: standalone 1-syllable name clips
  //      sound punched-out even with v3 (no sentence context for
  //      prosody). "Hey, Adam!" sounds natural; "David." doesn't.
  //   2. Per-journey monolithic (`<journeyId>_offer`) was retired
  //      same day after Adam's "magical memory" pivot: the offer
  //      should reference the SPECIFIC source story they just
  //      heard, not the journey as a whole. "Last time we walked
  //      with Daniel into the lions' den…" is the move.
  //
  // Clip ID conventions:
  //   - Full offer:  `<journeyId>_offer_<sourceStoryIndex>`
  //                  e.g. daniel_arc_offer_2 = the offer that fires
  //                  AFTER hearing Daniel 6 (index 2), offering
  //                  Daniel 7 (index 3). Used by the cold-open
  //                  cascade — ends with the redirect clause.
  //   - Short offer: `<journeyId>_offer_<sourceStoryIndex>_short`
  //                  Same scene reference, but drops the trailing
  //                  redirect clause. Used by the mood-button
  //                  cascade (user already tapped a mood, so
  //                  "or, tell me what's on your heart today"
  //                  is contradictory).
  //   - Decline:     `decline_adult` or `decline_kid` (lane-specific,
  //                  shared across all journeys in that lane).
  //
  // Vestigial clips (kept bundled per [feedback_never_delete_audio]
  // but not referenced by this resolver):
  //   - offer_narrative_adult (the abandoned generic adult offer)
  //   - daniel_arc_offer (the abandoned per-journey adult)
  //   - kid_david_arc_offer (the abandoned per-journey kid)
  //   - carrier_narrative_kid + invitation_narrative_kid +
  //     name_david_journey (the abandoned compositional kid)
  //
  // End-of-journey is silent: when source is the LAST story in the
  // journey, the engine returns null (no offer), so the resolver
  // is never called for that case. End-of-journey curation is
  // Slice 5's job (the Guidance Graph) — explicitly deferred.
  // ------------------------------------------------------------
  JourneyAudioPlan? _resolve(
      JourneyContinuationOffer offer,
      String voiceKey,
      JourneyOfferVariant variant) {
    final baseOfferClipId =
        '${offer.journey.journeyId}_offer_${offer.sourceStoryIndex}';
    final offerClipId = variant == JourneyOfferVariant.short
        ? '${baseOfferClipId}_short'
        : baseOfferClipId;
    final declineClipId = offer.journey.lane == JourneyLane.adult
        ? 'decline_adult'
        : 'decline_kid';

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
