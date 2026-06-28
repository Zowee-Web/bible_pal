import '../pal_memory/pal_session.dart';
import 'journey.dart';
import 'journey_continuation_offer.dart';
import 'journey_registry.dart';

/// Decides whether PAL has a journey continuation to offer right now.
///
/// Journey Doctrine, Slice 2 (docs/JOURNEY_DOCTRINE.md): pure function
/// over its inputs. No IO, no inference, no LLM. No persistence of
/// "PAL spoke" — that's the cascade layer's responsibility (Phase 9),
/// because only the cascade knows whether playback actually succeeded.
///
/// Continuation Invariant (doctrine rule 1): the engine's job is to
/// say what PAL CAN offer, not what PAL MUST offer. The cascade may
/// still choose silence even when the engine returns a non-null
/// offer (silence-floor honesty — missing audio, consent gate, etc.).
class JourneyEngine {
  const JourneyEngine();

  /// Cooldown between continuation offers on the adult lane. Kid
  /// lane has no cooldown per the doctrine's Kid-Lane Appendix
  /// (Continuation Invariant rule 3 override).
  static const Duration kAdultCooldown = Duration(days: 3);

  /// Returns the next continuation PAL would offer, or null for
  /// silence.
  ///
  /// - [sessions]: full PAL session log (any order; engine sorts).
  /// - [registry]: loaded journey registry (ready journeys only via
  ///   its lookup methods).
  /// - [lastJourneyContinuationSpokenAt]: the truthful "PAL last
  ///   spoke a journey continuation" timestamp. Caller MUST advance
  ///   only after successful playback, not after offer construction.
  /// - [now]: current time, injected for deterministic tests.
  /// - [currentLane]: user's active lane (adult vs kid mode). Engine
  ///   only matches sessions to journeys in this lane.
  JourneyContinuationOffer? nextOffer({
    required List<PalSession> sessions,
    required JourneyRegistry registry,
    required DateTime? lastJourneyContinuationSpokenAt,
    required DateTime now,
    required JourneyLane currentLane,
  }) {
    // Gate 1 — cooldown. Adult-only per Continuation Invariant rule
    // 3 (kid lane override).
    if (currentLane == JourneyLane.adult &&
        lastJourneyContinuationSpokenAt != null) {
      if (now.difference(lastJourneyContinuationSpokenAt) < kAdultCooldown) {
        return null;
      }
    }

    // Gate 2 — find the NEWEST session that lives in a ready journey
    // for the current lane. Slice 2 strict-newest rule per doctrine:
    // "the user's last completed story is in that journey." If the
    // newest in-journey session is at end-of-journey (Gate 3), we
    // stay silent rather than walking back to an older session —
    // PAL's offer should reflect the user's most recent listening
    // context, not reach backward.
    final sorted = List<PalSession>.from(sessions)
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    for (final session in sorted) {
      final membership = _matchSession(session, registry, currentLane);
      if (membership == null) continue;

      // Gate 3 — end-of-journey check. Strict-newest: stop here even
      // if a continuation exists in an older session's journey.
      // Slice 5 adds graduation; Slice 2 just stays silent.
      final nextIndex = membership.storyIndex + 1;
      if (nextIndex >= membership.journey.stories.length) {
        return null;
      }

      return JourneyContinuationOffer(
        journey: membership.journey,
        sourceSession: session,
        sourceStoryIndex: membership.storyIndex,
        nextStoryIndex: nextIndex,
        nextStory: membership.journey.stories[nextIndex],
      );
    }

    // No session in any ready journey for this lane — silence.
    return null;
  }

  /// Parses a session's storyId to extract its lookup key + lane,
  /// then queries the registry. Returns null if the session isn't in
  /// any ready journey for [lane] (either because the sid doesn't
  /// parse as that lane's pattern, or because no ready journey claims
  /// the extracted key).
  ///
  /// Adult sids: `story_<N>_<mood>_<length>_traditional[_kjv]` →
  /// extract integer `<N>`.
  /// Kid sids: `kidstory_kid_<anchor>_<length>` → extract `<anchor>`.
  JourneyMembership? _matchSession(
    PalSession session,
    JourneyRegistry registry,
    JourneyLane lane,
  ) {
    final sid = session.storyId;
    if (lane == JourneyLane.adult) {
      final m = _adultStoryNumberPattern.firstMatch(sid);
      if (m == null) return null;
      final n = int.tryParse(m.group(1)!);
      if (n == null) return null;
      return registry.lookupAdultByStoryNumber(n);
    } else {
      final m = _kidAnchorPattern.firstMatch(sid);
      if (m == null) return null;
      return registry.lookupKidByAnchorId(m.group(1)!);
    }
  }

  // Adult sid pattern: story_<N>_... where N is the leading number.
  // Matches every adult Traditional sid shape — full/short/long ×
  // WEB/KJV all share the `story_<N>_` prefix.
  static final RegExp _adultStoryNumberPattern = RegExp(r'^story_(\d+)_');

  // Kid sid pattern: kidstory_kid_<anchor>_<length>. Lazy match on
  // <anchor> so multi-underscore anchors (david_shepherd,
  // daniel_lions_den) capture correctly.
  static final RegExp _kidAnchorPattern =
      RegExp(r'^kidstory_kid_([a-z_]+?)_(short|full|long)$');
}
