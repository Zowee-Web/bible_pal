import 'package:flutter/foundation.dart' show immutable;

import '../../models/user_preferences.dart';
import '../pal_memory/pal_session_store.dart';
import 'journey.dart';
import 'journey_audio_plan.dart';
import 'journey_audio_resolver.dart';
import 'journey_continuation_offer.dart';
import 'journey_engine.dart';
import 'journey_registry.dart';
import 'journey_response_classifier.dart';

/// Outcome of a single journey-continuation cascade attempt. Caller-
/// visible so the integration site can dispatch on the exact branch
/// (open next-in-journey story, route to mood-flow with the user's
/// phrase, fall through silently, etc.) and tests can assert dispatch
/// behavior without a Riverpod or widget harness.
///
/// Journey Doctrine Slice 2 Phase 9 — mirrors [MemoryLineOutcome].
enum JourneyOfferOutcome {
  // ---- Skip outcomes (offer never spoken) ----------------------------

  /// Voice consent gate stopped the cascade. Same shape as the
  /// PAL Memory consent gate.
  consentBlocked,

  /// [JourneyEngine.nextOffer] returned null (cooldown, no in-journey
  /// session, or end-of-journey).
  engineSilent,

  /// Engine returned an offer but the audio resolver could not produce
  /// a plan (offer or decline clip missing from bundle for active
  /// voice). Silence-floor honest: no fallback, no partial plan.
  missingClip,

  /// Offer audio playback failed mid-flight. Cooldown NOT advanced —
  /// engine will re-attempt on the next selection.
  playbackFailed,

  /// Any unhandled exception was swallowed. Integration site continues
  /// silently — a journey-cascade failure must NEVER block story
  /// selection.
  exception,

  // ---- Played outcomes (offer was spoken; user responded) ------------

  /// User accepted. The integration site should open the player with
  /// `offer.nextStory.storyId` and call
  /// [PalSessionStore.recordJourneyContinuationSpoken] AFTER the next
  /// story plays successfully (cooldown advances only on the full
  /// happy path per the doctrine).
  acceptedAndContinued,

  /// User explicitly declined ("no thanks" / "not today"). The runtime
  /// already played the decline clip; integration site should
  /// continue to the normal mood-flow.
  declinedExplicit,

  /// User's response was ambiguous or silent ("I don't know" / "" /
  /// "hmm"). The runtime already played the decline clip; integration
  /// site should continue to mood-flow with the user's existing
  /// default mood path.
  declinedAmbiguous,

  /// User expressed a mood instead of yes/no ("I'm anxious" / "had a
  /// rough day"). The runtime did NOT play the decline clip — the
  /// doctrine forbids asking the user to decline twice. Integration
  /// site should pass [JourneyOfferResult.moodPhrase] through to
  /// `MoodService.detectMood(...)` and the normal mood-flow story
  /// selection path.
  declinedMoodRedirect,

  /// User tapped Cancel during the offer or the STT capture. The
  /// runtime did NOT play the decline clip and did NOT classify a
  /// (possibly stop()-induced empty) transcript. The integration site
  /// must ABORT the whole flow — no mic restart, no mood fallback, no
  /// cold-open greeting. This exists because a bare stop() forces an
  /// empty result that would otherwise classify as ambiguous, play the
  /// decline clip, and reopen the mic — which reads to the user as
  /// "Cancel did nothing."
  cancelled,
}

@immutable
class JourneyOfferResult {
  final JourneyOfferOutcome outcome;
  final String? skippedReason;

  /// The offer the engine produced. Non-null whenever the engine
  /// returned an offer, regardless of subsequent gates. Useful for
  /// telemetry payloads and for the integration site's accept-path
  /// (`offer.nextStory.storyId`).
  final JourneyContinuationOffer? offer;

  /// The user's free-form utterance, set only for
  /// [JourneyOfferOutcome.declinedMoodRedirect]. The integration site
  /// passes it to mood detection unchanged (case preserved).
  final String? moodPhrase;

  const JourneyOfferResult(
    this.outcome, {
    this.skippedReason,
    this.offer,
    this.moodPhrase,
  });

  /// Whether the cascade reached the point of speaking the offer.
  /// Used by the integration site to decide whether to suppress
  /// Slice 2d recognition on the resulting story (the offer already
  /// named the character; recognition would be redundant on accept
  /// and is fine to skip on decline since the mood-flow story may
  /// have its own character).
  bool get offerWasSpoken => switch (outcome) {
        JourneyOfferOutcome.acceptedAndContinued => true,
        JourneyOfferOutcome.declinedExplicit => true,
        JourneyOfferOutcome.declinedAmbiguous => true,
        JourneyOfferOutcome.declinedMoodRedirect => true,
        _ => false,
      };

  /// Suppression rule for Slice 2d recognition. Per the doctrine,
  /// only the ACCEPT path suppresses — decline branches let
  /// recognition fire normally on whatever mood-flow story plays
  /// next (different character, different memory thread).
  bool get suppressSlice2dRecognition =>
      outcome == JourneyOfferOutcome.acceptedAndContinued;
}

/// Plays the offer portion of a [JourneyAudioPlan]. Returns true on
/// success. Wraps [PalAudioService.playJourneyOffer].
typedef JourneyOfferPlanPlayer = Future<bool> Function(JourneyAudioPlan plan);

/// Plays the decline clip of a [JourneyAudioPlan]. Returns true on
/// success. Wraps [PalAudioService.playJourneyDecline].
typedef JourneyDeclinePlanPlayer = Future<bool> Function(
    JourneyAudioPlan plan);

/// Captures the user's STT response after the offer plays. Returns
/// the final transcript or null if no input was captured (timeout,
/// permission denied, etc.). Null is treated as [JourneyResponseBucket.ambiguous]
/// by the classifier.
typedef JourneyResponseCapture = Future<String?> Function();

/// Structured-event sink mirroring [AppLogger.logEvent]'s signature.
typedef EventLogger = void Function(String event, Map<String, Object?> props);

/// Run the journey-continuation cascade end-to-end. Pure-ish: every
/// IO dependency is injected so unit tests exercise every branch
/// without a Riverpod ProviderContainer or a widget harness.
///
/// Journey Doctrine Slice 2 Phase 9 (see docs/JOURNEY_DOCTRINE.md):
/// the cascade is consent → engine → audio plan → play offer → STT →
/// classify → dispatch. Any null/failure short-circuits to silence
/// per the silence-floor invariant; the doctrine forbids fallback to
/// a different voice, an alternate phrasing, or runtime TTS.
///
/// Cooldown advancement is the integration site's responsibility, NOT
/// the runtime's, because cooldown advances only when (accept AND
/// next-in-journey-story plays successfully) — and the runtime never
/// sees the next-story playback. See [JourneyOfferOutcome.acceptedAndContinued].
///
/// Any exception inside the cascade is caught and reported as
/// [JourneyOfferOutcome.exception]; the integration site can safely
/// `await` this without try/catch and proceed to story selection.
Future<JourneyOfferResult> fireJourneyOffer({
  required UserPreferences? preferences,
  required PalSessionStore sessionStore,
  required JourneyRegistry journeyRegistry,
  required JourneyAudioResolver audioResolver,
  required JourneyResponseClassifier classifier,
  required JourneyOfferPlanPlayer playOfferPlan,
  required JourneyDeclinePlanPlayer playDeclinePlan,
  required JourneyResponseCapture captureResponse,
  required DateTime now,
  EventLogger? logger,
  // Returns true if the user aborted (tapped Cancel) since the offer
  // began. Checked after the offer plays and after capture so an abort
  // short-circuits BEFORE the decline clip plays or a story opens.
  bool Function()? isCancelled,
}) async {
  void log(String event, Map<String, Object?> props) {
    final l = logger;
    if (l != null) l(event, props);
  }

  bool cancelled() => isCancelled?.call() ?? false;

  try {
    // Gate 0 — voice consent. Mirrors fireMemoryLine exactly so the
    // two cascades behave identically at the consent layer.
    if (preferences == null) {
      log('pal_journey_offer_skipped', const {'reason': 'no_preferences'});
      return const JourneyOfferResult(
        JourneyOfferOutcome.consentBlocked,
        skippedReason: 'no_preferences',
      );
    }
    if (preferences.palVoiceEnabled != true) {
      log('pal_journey_offer_skipped',
          const {'reason': 'pal_voice_disabled'});
      return const JourneyOfferResult(
        JourneyOfferOutcome.consentBlocked,
        skippedReason: 'pal_voice_disabled',
      );
    }
    if (preferences.palGreetingsEnabled == false) {
      log('pal_journey_offer_skipped',
          const {'reason': 'pal_greetings_disabled'});
      return const JourneyOfferResult(
        JourneyOfferOutcome.consentBlocked,
        skippedReason: 'pal_greetings_disabled',
      );
    }
    final voiceKey = preferences.palVoiceKey;
    final lane = preferences.kidFriendlyOnly
        ? JourneyLane.kid
        : JourneyLane.adult;

    // Gate 1 — engine. Pure rules over sessions + cooldown timestamp +
    // current lane.
    const engine = JourneyEngine();
    final sessions = await sessionStore.all();
    final lastSpokenAt =
        await sessionStore.getLastJourneyContinuationSpokenAt();
    final offer = engine.nextOffer(
      sessions: sessions,
      registry: journeyRegistry,
      lastJourneyContinuationSpokenAt: lastSpokenAt,
      now: now,
      currentLane: lane,
    );
    if (offer == null) {
      log('pal_journey_offer_skipped', const {'reason': 'engine_silent'});
      return const JourneyOfferResult(
        JourneyOfferOutcome.engineSilent,
        skippedReason: 'engine_silent',
      );
    }

    // Gate 2 — audio plan (bundled-asset existence check for offer +
    // decline clips). Silence-floor: missing clip returns null and
    // the cascade short-circuits without speaking.
    final plan = await audioResolver.resolve(
      offer: offer,
      activeVoiceKey: voiceKey,
    );
    if (plan == null) {
      log('pal_journey_offer_skipped', {
        'reason': 'missing_clip',
        'voice_key': voiceKey,
        'journey_id': offer.journey.journeyId,
        'source_story_index': offer.sourceStoryIndex,
      });
      return JourneyOfferResult(
        JourneyOfferOutcome.missingClip,
        skippedReason: 'missing_clip',
        offer: offer,
      );
    }

    // Gate 3 — play offer audio. Failure short-circuits without
    // advancing cooldown (engine re-attempts next selection).
    final offerPlayed = await playOfferPlan(plan);
    if (!offerPlayed) {
      log('pal_journey_offer_skipped', {
        'reason': 'playback_failed',
        'voice_key': voiceKey,
        'journey_id': offer.journey.journeyId,
        'source_story_index': offer.sourceStoryIndex,
      });
      return JourneyOfferResult(
        JourneyOfferOutcome.playbackFailed,
        skippedReason: 'playback_failed',
        offer: offer,
      );
    }

    // Cancel checkpoint — user aborted while the offer played. Abort
    // before capturing (and before the decline clip could ever play).
    if (cancelled()) {
      log('pal_journey_offer_cancelled', {
        'stage': 'after_offer',
        'journey_id': offer.journey.journeyId,
        'source_story_index': offer.sourceStoryIndex,
      });
      return JourneyOfferResult(JourneyOfferOutcome.cancelled, offer: offer);
    }

    // Telemetry — offer audio fired (heard by user). Logged BEFORE
    // STT capture so a crash during STT still leaves a 'fired'
    // breadcrumb for diagnostics.
    log('pal_journey_offer_fired', {
      'voice_key': voiceKey,
      'journey_id': offer.journey.journeyId,
      'source_story_index': offer.sourceStoryIndex,
      'next_story_index': offer.nextStoryIndex,
      'lane': lane.name,
    });

    // Gate 4 — STT capture. Null/empty → ambiguous bucket.
    final transcript = await captureResponse();

    // Cancel checkpoint — user tapped Cancel during capture. The
    // stop() that Cancel triggers forces an empty transcript here;
    // without this guard it would classify as ambiguous, play the
    // decline clip, and the integration site would reopen the mic.
    if (cancelled()) {
      log('pal_journey_offer_cancelled', {
        'stage': 'after_capture',
        'journey_id': offer.journey.journeyId,
        'source_story_index': offer.sourceStoryIndex,
      });
      return JourneyOfferResult(JourneyOfferOutcome.cancelled, offer: offer);
    }

    final classification = classifier.classify(transcript ?? '');

    // Gate 5 — dispatch on bucket.
    switch (classification.bucket) {
      case JourneyResponseBucket.accept:
        log('pal_journey_continuation_accepted', {
          'voice_key': voiceKey,
          'journey_id': offer.journey.journeyId,
          'source_story_index': offer.sourceStoryIndex,
          'next_story_index': offer.nextStoryIndex,
          'next_story_anchor': offer.nextStory.scriptureAnchorId ??
              offer.nextStory.anchorId,
        });
        return JourneyOfferResult(
          JourneyOfferOutcome.acceptedAndContinued,
          offer: offer,
        );

      case JourneyResponseBucket.moodRedirect:
        // Per doctrine: the user's mood-utterance IS the decline —
        // never ask them to decline twice. NO decline clip plays.
        log('pal_journey_continuation_mood_redirect', {
          'voice_key': voiceKey,
          'journey_id': offer.journey.journeyId,
          'source_story_index': offer.sourceStoryIndex,
          'transcript_chars': classification.text.length,
        });
        return JourneyOfferResult(
          JourneyOfferOutcome.declinedMoodRedirect,
          offer: offer,
          moodPhrase: classification.text,
        );

      case JourneyResponseBucket.decline:
        await playDeclinePlan(plan);
        log('pal_journey_continuation_declined', {
          'voice_key': voiceKey,
          'journey_id': offer.journey.journeyId,
          'source_story_index': offer.sourceStoryIndex,
        });
        return JourneyOfferResult(
          JourneyOfferOutcome.declinedExplicit,
          offer: offer,
        );

      case JourneyResponseBucket.ambiguous:
        await playDeclinePlan(plan);
        log('pal_journey_continuation_ambiguous_default', {
          'voice_key': voiceKey,
          'journey_id': offer.journey.journeyId,
          'source_story_index': offer.sourceStoryIndex,
          'transcript_was_empty':
              transcript == null || transcript.trim().isEmpty,
        });
        return JourneyOfferResult(
          JourneyOfferOutcome.declinedAmbiguous,
          offer: offer,
        );
    }
  } catch (e) {
    // Safe-fail: journey-cascade failure must NEVER block story
    // selection. The integration site awaits this without try/catch.
    log('pal_journey_offer_skipped', {
      'reason': 'exception',
      'error': e.toString(),
    });
    return JourneyOfferResult(
      JourneyOfferOutcome.exception,
      skippedReason: 'exception: $e',
    );
  }
}
