import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import '../pal_memory/memory_audio_policy.dart';
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
  // KID — [carrier] + [name] + [invitation], stitched.
  // Plus separate decline clip.
  // Character clip ID derived from the journey's characterName via
  // PalJourneyAudioPaths.nameClipIdFor (e.g. "David" →
  // "name_david_journey").
  // ------------------------------------------------------------
  JourneyAudioPlan? _resolveKid(
      JourneyContinuationOffer offer, String voiceKey) {
    final characterName = offer.journey.characterName;
    if (characterName == null || characterName.isEmpty) {
      // Kid journey without a characterName cannot compose an offer.
      // Schema validator catches this upstream; defensive null here
      // for runtime resilience.
      return null;
    }

    const carrierClipId = 'carrier_narrative_kid';
    final nameClipId = PalJourneyAudioPaths.nameClipIdFor(characterName);
    const invitationClipId = 'invitation_narrative_kid';
    const declineClipId = 'decline_kid';

    final carrierPath = PalJourneyAudioPaths.assetPathFor(
        voiceKey: voiceKey, clipId: carrierClipId);
    final namePath = PalJourneyAudioPaths.assetPathFor(
        voiceKey: voiceKey, clipId: nameClipId);
    final invitationPath = PalJourneyAudioPaths.assetPathFor(
        voiceKey: voiceKey, clipId: invitationClipId);
    final declinePath = PalJourneyAudioPaths.assetPathFor(
        voiceKey: voiceKey, clipId: declineClipId);

    // Silence-floor: ANY missing clip → null. No partial plans.
    if (!bundledPaths.contains(carrierPath)) return null;
    if (!bundledPaths.contains(namePath)) return null;
    if (!bundledPaths.contains(invitationPath)) return null;
    if (!bundledPaths.contains(declinePath)) return null;

    return JourneyAudioPlan(
      voiceKey: voiceKey,
      offerClips: [
        JourneyAudioClipRef(
          clipId: carrierClipId,
          kind: JourneyClipKind.carrier,
          assetPath: carrierPath,
        ),
        JourneyAudioClipRef(
          clipId: nameClipId,
          kind: JourneyClipKind.name,
          assetPath: namePath,
        ),
        JourneyAudioClipRef(
          clipId: invitationClipId,
          kind: JourneyClipKind.invitation,
          assetPath: invitationPath,
        ),
      ],
      offerGapsBetween: const [
        // Reuse Slice 2d's audition-tested 50ms carrier→name gap for
        // both stitch points. If a kid-offer audition exposes a
        // different rhythm later, introduce a JourneyAudioPolicy
        // with kid-specific gap durations.
        PalMemoryAudioPolicy.carrierToNameGap,
        PalMemoryAudioPolicy.carrierToNameGap,
      ],
      declineClip: JourneyAudioClipRef(
        clipId: declineClipId,
        kind: JourneyClipKind.decline,
        assetPath: declinePath,
      ),
    );
  }
}
