import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
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

  // ── Open-Door Tail Family (2026-07-15, Adam-ratified) ─────────────
  // docs/JOURNEY_TRANSITION_VOICE.md § Open-Door Tail Family. Adult
  // offer BODIES end at the invitation's question mark; the third-path
  // tail is a separate clip stitched after a short breath. Each play
  // rotates within the journey's flavor bucket + the neutral pool,
  // never repeating the immediately-previous tail. Kid offers keep
  // their fixed baked-in tail (no stitching).
  static const Map<String, List<String>> _tailBuckets = {
    'hopeful': ['tail_heart_today', 'tail_on_your_mind'],
    'heavier': ['tail_weighing_on_you', 'tail_today_been_like'],
    'gentle': ['tail_how_youre_doing', 'tail_whatever_on_mind'],
  };
  static const List<String> _tailNeutral = [
    'tail_mind_lately',
    'tail_thinking_about',
    'tail_day_going',
    'tail_brought_you_here',
  ];

  /// Breath between body and tail — mirrors the ellipsis pause the
  /// single-clip renders carried before "Or, tell me…".
  static const Duration _tailGap = Duration(milliseconds: 420);

  // Session-scoped rotation memory (static so const instances share
  // it — same never-twice-in-a-row contract as the accept-ack set).
  static String? _lastTailClipId;
  static final Random _tailRandom = Random();

  /// Test-only seam: reset the rotation memory.
  @visibleForTesting
  static void resetTailRotationForTesting() => _lastTailClipId = null;

  /// Pick the next tail clip id for [journey], filtered to tails whose
  /// clips are actually bundled for [voiceKey]. Returns null when no
  /// tail is available (silence floor — an adult offer may not play
  /// without its third-path signal).
  String? _pickTailClipId(Journey journey, String voiceKey) {
    final bucket = _tailBuckets[journey.offerTailFlavor] ?? const <String>[];
    final pool = <String>[...bucket, ..._tailNeutral].where((id) {
      final path =
          PalJourneyAudioPaths.assetPathFor(voiceKey: voiceKey, clipId: id);
      return bundledPaths.contains(path);
    }).toList();
    if (pool.isEmpty) return null;
    var eligible =
        pool.where((id) => id != _lastTailClipId).toList();
    if (eligible.isEmpty) eligible = pool;
    final pick = eligible[_tailRandom.nextInt(eligible.length)];
    _lastTailClipId = pick;
    return pick;
  }

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
    // Both lanes resolve to the same monolithic shape (since the
    // adult pivot 2026-06-28): one per-source-story offer clip +
    // one lane-specific decline clip. The only lane difference is
    // the decline-clip ID.
    return _resolve(offer, activeVoiceKey);
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
  //   - Offer:   `<journeyId>_offer_<sourceStoryIndex>`
  //              e.g. daniel_arc_offer_2 = the offer that fires
  //              AFTER hearing Daniel 6 (index 2), offering
  //              Daniel 7 (index 3).
  //   - Decline: `decline_adult` or `decline_kid` (lane-specific,
  //              shared across all journeys in that lane).
  //
  // Vestigial clips (kept bundled per [feedback_never_delete_audio]
  // but not referenced by this resolver):
  //   - offer_narrative_adult (abandoned generic adult offer)
  //   - daniel_arc_offer (abandoned per-journey adult)
  //   - kid_david_arc_offer (abandoned per-journey kid)
  //   - carrier_narrative_kid + invitation_narrative_kid +
  //     name_david_journey (abandoned compositional kid)
  //   - <journeyId>_offer_<idx>_short × 5 (abandoned mood-button
  //     variant — Entry-Point Split doctrine 2026-06-30 removed
  //     the mood-button cascade entirely; short clips stay bundled
  //     but the resolver no longer references them)
  //
  // End-of-journey is silent: when source is the LAST story in the
  // journey, the engine returns null (no offer), so the resolver
  // is never called for that case. End-of-journey curation is
  // Slice 5's job (the Guidance Graph) — explicitly deferred.
  // ------------------------------------------------------------
  JourneyAudioPlan? _resolve(
      JourneyContinuationOffer offer, String voiceKey) {
    final declineClipId = offer.journey.lane == JourneyLane.adult
        ? 'decline_adult'
        : 'decline_kid';
    final declinePath = PalJourneyAudioPaths.assetPathFor(
        voiceKey: voiceKey, clipId: declineClipId);
    // Silence-floor: decline clip missing → null. No partial plans.
    if (!bundledPaths.contains(declinePath)) return null;

    // Offer-clip resolution, in priority order:
    //   1. Scale-Horizon per-source-story clip
    //      `<sourceStoryNumber>_pal_continuation` — the library-wide
    //      ledger convention (assets/stories/outgoing_beats.json,
    //      rendered by render_journey_audio.py). Keyed off the source
    //      story, not its arc position, so it survives the shift from
    //      curated arcs to per-story beats (Journey Doctrine Scale
    //      Horizon). Adult only — kid slots carry no storyNumber.
    //   2. Legacy per-arc-index clip
    //      `<journeyId>_offer_<sourceStoryIndex>` — the Slice 2
    //      first-ship convention still used by Daniel/Joseph/Ruth/
    //      Elijah and the kid arcs.
    // First bundled candidate wins; silence-floor if neither exists.
    final sourceStory = offer.journey.stories[offer.sourceStoryIndex];
    final candidateClipIds = <String>[
      if (sourceStory.storyNumber != null)
        '${sourceStory.storyNumber}_pal_continuation',
      '${offer.journey.journeyId}_offer_${offer.sourceStoryIndex}',
    ];

    for (final offerClipId in candidateClipIds) {
      final offerPath = PalJourneyAudioPaths.assetPathFor(
          voiceKey: voiceKey, clipId: offerClipId);
      if (!bundledPaths.contains(offerPath)) continue;

      final bodyClip = JourneyAudioClipRef(
        clipId: offerClipId,
        kind: JourneyClipKind.offer,
        assetPath: offerPath,
      );

      // Adult offers: stitch the rotated Open-Door tail after the body
      // (2026-07-15). Silence-floor: an adult offer without its
      // third-path tail fails Voice Audit Q7 — no tail bundled means
      // no offer. Kid offers carry their tail baked in.
      final clips = <JourneyAudioClipRef>[bodyClip];
      final gaps = <Duration>[];
      if (offer.journey.lane == JourneyLane.adult) {
        final tailClipId = _pickTailClipId(offer.journey, voiceKey);
        if (tailClipId == null) return null;
        clips.add(JourneyAudioClipRef(
          clipId: tailClipId,
          kind: JourneyClipKind.offer,
          assetPath: PalJourneyAudioPaths.assetPathFor(
              voiceKey: voiceKey, clipId: tailClipId),
        ));
        gaps.add(_tailGap);
      }

      return JourneyAudioPlan(
        voiceKey: voiceKey,
        offerClips: clips,
        offerGapsBetween: gaps,
        declineClip: JourneyAudioClipRef(
          clipId: declineClipId,
          kind: JourneyClipKind.decline,
          assetPath: declinePath,
        ),
      );
    }
    return null;
  }
}
