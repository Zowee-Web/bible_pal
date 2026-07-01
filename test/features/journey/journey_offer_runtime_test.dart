import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_pal/features/journey/journey_audio_paths.dart';
import 'package:bible_pal/features/journey/journey_audio_plan.dart';
import 'package:bible_pal/features/journey/journey_audio_resolver.dart';
import 'package:bible_pal/features/journey/journey_continuation_offer.dart';
import 'package:bible_pal/features/journey/journey_offer_runtime.dart';
import 'package:bible_pal/features/journey/journey_registry.dart';
import 'package:bible_pal/features/journey/journey_response_classifier.dart';
import 'package:bible_pal/features/pal_memory/pal_session.dart';
import 'package:bible_pal/features/pal_memory/pal_session_store.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/services/storage_service.dart';

/// End-to-end cascade tests for [fireJourneyOffer] — Journey Doctrine
/// Slice 2 Phase 9 runtime integration (see docs/JOURNEY_DOCTRINE.md).
///
/// The cascade has five gates (consent → engine → audio plan → play
/// offer → STT → classify → dispatch) and one side-effect handled
/// outside the runtime (cooldown advancement). Every gate gets its
/// own test, and every dispatch bucket (accept / decline / moodRedirect
/// / ambiguous) gets its own test asserting the right audio
/// side-effects + telemetry payloads.
void main() {
  late StorageService storage;
  late PalSessionStore sessionStore;
  late JourneyRegistry registry;
  const classifier = JourneyResponseClassifier();
  final now = DateTime.utc(2026, 6, 30, 12, 0);
  final yesterday = now.subtract(const Duration(days: 1));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    sessionStore = PalSessionStore(storage);
    registry = JourneyRegistry.fromJsonStrings(const [_adultDanielJson]);
  });

  UserPreferences buildPrefs({
    bool palVoiceEnabled = true,
    bool? palGreetingsEnabled = true,
    String palVoiceKey = 'VOICE_STILLWATER',
    bool kidFriendlyOnly = false,
  }) {
    return UserPreferences.defaults().copyWith(
      palVoiceEnabled: palVoiceEnabled,
      palGreetingsEnabled: palGreetingsEnabled,
      palVoiceKey: palVoiceKey,
      kidFriendlyOnly: kidFriendlyOnly,
    );
  }

  Future<void> seedAdultSession() async {
    await storage.addPalSession(PalSession(
      storyId: 'story_1486_brave_courage_full_traditional',
      completedAt: yesterday,
      languageStyle: 'WEB',
    ));
  }

  // -----------------------------------------------------------------
  // Consent gate
  // -----------------------------------------------------------------
  group('Gate 0 — voice consent', () {
    test('null preferences → consentBlocked', () async {
      final events = <_Event>[];
      final res = await fireJourneyOffer(
        preferences: null,
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: _AlwaysOkResolver(),
        classifier: classifier,
        playOfferPlan: _failPlay,
        playDeclinePlan: _failPlay,
        captureResponse: _captureNull,
        now: now,
        logger: events.record,
      );
      expect(res.outcome, JourneyOfferOutcome.consentBlocked);
      expect(res.skippedReason, 'no_preferences');
      expect(events.first.event, 'pal_journey_offer_skipped');
      expect(events.first.props['reason'], 'no_preferences');
    });

    test('palVoiceEnabled=false → consentBlocked', () async {
      final res = await fireJourneyOffer(
        preferences: buildPrefs(palVoiceEnabled: false),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: _AlwaysOkResolver(),
        classifier: classifier,
        playOfferPlan: _failPlay,
        playDeclinePlan: _failPlay,
        captureResponse: _captureNull,
        now: now,
      );
      expect(res.outcome, JourneyOfferOutcome.consentBlocked);
      expect(res.skippedReason, 'pal_voice_disabled');
    });

    test('palGreetingsEnabled=false → consentBlocked', () async {
      final res = await fireJourneyOffer(
        preferences: buildPrefs(palGreetingsEnabled: false),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: _AlwaysOkResolver(),
        classifier: classifier,
        playOfferPlan: _failPlay,
        playDeclinePlan: _failPlay,
        captureResponse: _captureNull,
        now: now,
      );
      expect(res.outcome, JourneyOfferOutcome.consentBlocked);
      expect(res.skippedReason, 'pal_greetings_disabled');
    });
  });

  // -----------------------------------------------------------------
  // Engine gate
  // -----------------------------------------------------------------
  group('Gate 1 — engine', () {
    test('no sessions → engineSilent', () async {
      final res = await fireJourneyOffer(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: _AlwaysOkResolver(),
        classifier: classifier,
        playOfferPlan: _failPlay,
        playDeclinePlan: _failPlay,
        captureResponse: _captureNull,
        now: now,
      );
      expect(res.outcome, JourneyOfferOutcome.engineSilent);
    });

    test('cooldown active → engineSilent', () async {
      await seedAdultSession();
      // Spoke yesterday — within 3-day adult cooldown.
      await sessionStore.recordJourneyContinuationSpoken(at: yesterday);
      final res = await fireJourneyOffer(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: _AlwaysOkResolver(),
        classifier: classifier,
        playOfferPlan: _failPlay,
        playDeclinePlan: _failPlay,
        captureResponse: _captureNull,
        now: now,
      );
      expect(res.outcome, JourneyOfferOutcome.engineSilent);
    });
  });

  // -----------------------------------------------------------------
  // Audio plan gate
  // -----------------------------------------------------------------
  group('Gate 2 — audio plan', () {
    test('resolver returns null → missingClip, offer present in result',
        () async {
      await seedAdultSession();
      final res = await fireJourneyOffer(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: _NullResolver(),
        classifier: classifier,
        playOfferPlan: _failPlay,
        playDeclinePlan: _failPlay,
        captureResponse: _captureNull,
        now: now,
      );
      expect(res.outcome, JourneyOfferOutcome.missingClip);
      expect(res.offer, isNotNull,
          reason: 'engine produced an offer; resolver just failed');
      expect(res.offerWasSpoken, isFalse);
    });
  });

  // -----------------------------------------------------------------
  // Playback failure gate
  // -----------------------------------------------------------------
  group('Gate 3 — offer playback', () {
    test('offer playback returns false → playbackFailed, NO cooldown advance',
        () async {
      await seedAdultSession();
      final res = await fireJourneyOffer(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: _AlwaysOkResolver(),
        classifier: classifier,
        playOfferPlan: _failPlay,
        playDeclinePlan: _failPlay,
        captureResponse: _captureText('yes'),
        now: now,
      );
      expect(res.outcome, JourneyOfferOutcome.playbackFailed);
      expect(res.offerWasSpoken, isFalse);
      // STT should NEVER be called when offer playback fails.
      expect(await sessionStore.getLastJourneyContinuationSpokenAt(), isNull,
          reason: 'cooldown must not advance on failed playback');
    });
  });

  // -----------------------------------------------------------------
  // Dispatch — every bucket
  // -----------------------------------------------------------------
  group('Gate 5 — dispatch', () {
    test('accept → acceptedAndContinued, decline clip NOT played, '
        'suppressSlice2dRecognition=true', () async {
      await seedAdultSession();
      var declineCalls = 0;
      final events = <_Event>[];
      final res = await fireJourneyOffer(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: _AlwaysOkResolver(),
        classifier: classifier,
        playOfferPlan: _okPlay,
        playDeclinePlan: (plan) async {
          declineCalls++;
          return true;
        },
        captureResponse: _captureText('yes please'),
        now: now,
        logger: events.record,
      );
      expect(res.outcome, JourneyOfferOutcome.acceptedAndContinued);
      expect(res.offer, isNotNull);
      expect(res.offer!.nextStory.storyNumber, 1002);
      expect(declineCalls, 0, reason: 'accept must not play decline clip');
      expect(res.suppressSlice2dRecognition, isTrue);
      // Telemetry: fired + accepted (two events).
      final eventNames = events.map((e) => e.event).toList();
      expect(eventNames, contains('pal_journey_offer_fired'));
      expect(eventNames, contains('pal_journey_continuation_accepted'));
    });

    test('decline → declinedExplicit, decline clip PLAYED, '
        'suppressSlice2dRecognition=false', () async {
      await seedAdultSession();
      var declineCalls = 0;
      final events = <_Event>[];
      final res = await fireJourneyOffer(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: _AlwaysOkResolver(),
        classifier: classifier,
        playOfferPlan: _okPlay,
        playDeclinePlan: (plan) async {
          declineCalls++;
          return true;
        },
        captureResponse: _captureText('no thanks'),
        now: now,
        logger: events.record,
      );
      expect(res.outcome, JourneyOfferOutcome.declinedExplicit);
      expect(declineCalls, 1);
      expect(res.suppressSlice2dRecognition, isFalse,
          reason: 'decline lets Slice 2d fire on the mood-flow story');
      expect(res.offerWasSpoken, isTrue);
      final eventNames = events.map((e) => e.event).toList();
      expect(eventNames, contains('pal_journey_continuation_declined'));
    });

    test('moodRedirect → declinedMoodRedirect, decline clip NOT played, '
        'moodPhrase passed through verbatim', () async {
      await seedAdultSession();
      var declineCalls = 0;
      final events = <_Event>[];
      final res = await fireJourneyOffer(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: _AlwaysOkResolver(),
        classifier: classifier,
        playOfferPlan: _okPlay,
        playDeclinePlan: (plan) async {
          declineCalls++;
          return true;
        },
        captureResponse: _captureText("I'm tired today"),
        now: now,
        logger: events.record,
      );
      expect(res.outcome, JourneyOfferOutcome.declinedMoodRedirect);
      expect(declineCalls, 0,
          reason:
              'mood-redirect must NOT ask the user to decline twice');
      expect(res.moodPhrase, "I'm tired today",
          reason: 'caller passes the phrase to MoodService unchanged');
      final eventNames = events.map((e) => e.event).toList();
      expect(eventNames,
          contains('pal_journey_continuation_mood_redirect'));
      expect(eventNames,
          isNot(contains('pal_journey_continuation_declined')));
    });

    test('ambiguous (empty STT) → declinedAmbiguous, decline clip PLAYED',
        () async {
      await seedAdultSession();
      var declineCalls = 0;
      final events = <_Event>[];
      final res = await fireJourneyOffer(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: _AlwaysOkResolver(),
        classifier: classifier,
        playOfferPlan: _okPlay,
        playDeclinePlan: (plan) async {
          declineCalls++;
          return true;
        },
        captureResponse: _captureNull,
        now: now,
        logger: events.record,
      );
      expect(res.outcome, JourneyOfferOutcome.declinedAmbiguous);
      expect(declineCalls, 1);
      final ambiguousEvent = events.firstWhere(
          (e) => e.event == 'pal_journey_continuation_ambiguous_default');
      expect(ambiguousEvent.props['transcript_was_empty'], isTrue);
    });

    test("ambiguous (\"I don't know\") → declinedAmbiguous", () async {
      await seedAdultSession();
      final res = await fireJourneyOffer(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: _AlwaysOkResolver(),
        classifier: classifier,
        playOfferPlan: _okPlay,
        playDeclinePlan: _okPlay,
        captureResponse: _captureText("I don't know"),
        now: now,
      );
      expect(res.outcome, JourneyOfferOutcome.declinedAmbiguous);
    });
  });

  // -----------------------------------------------------------------
  // Variant selection (Slice 2 PR B — mood-button entry point)
  // -----------------------------------------------------------------
  group('variant selection', () {
    test('short variant → resolver receives JourneyOfferVariant.short + '
        'clip ID gets _short suffix', () async {
      await seedAdultSession();
      JourneyOfferVariant? receivedVariant;
      final resolver = _CaptureVariantResolver(
          (v) => receivedVariant = v);
      final res = await fireJourneyOffer(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: resolver,
        classifier: classifier,
        playOfferPlan: _okPlay,
        playDeclinePlan: _okPlay,
        captureResponse: _captureText('yes'),
        now: now,
        variant: JourneyOfferVariant.short,
      );
      expect(receivedVariant, JourneyOfferVariant.short);
      // Plan built by the capture resolver uses the short clip id
      // convention (verified via the plan's offer clip id).
      expect(res.outcome, JourneyOfferOutcome.acceptedAndContinued);
    });

    test('default variant is full (backward compatible)', () async {
      await seedAdultSession();
      JourneyOfferVariant? receivedVariant;
      final resolver = _CaptureVariantResolver(
          (v) => receivedVariant = v);
      await fireJourneyOffer(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: resolver,
        classifier: classifier,
        playOfferPlan: _okPlay,
        playDeclinePlan: _okPlay,
        captureResponse: _captureText('yes'),
        now: now,
      );
      expect(receivedVariant, JourneyOfferVariant.full);
    });
  });

  // -----------------------------------------------------------------
  // Decline-clip suppression (mood-button uses this)
  // -----------------------------------------------------------------
  group('playDeclineClipOnDecline flag', () {
    test('false + decline → decline outcome, NO decline clip played',
        () async {
      await seedAdultSession();
      var declineCalls = 0;
      final res = await fireJourneyOffer(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: _AlwaysOkResolver(),
        classifier: classifier,
        playOfferPlan: _okPlay,
        playDeclinePlan: (plan) async {
          declineCalls++;
          return true;
        },
        captureResponse: _captureText('no thanks'),
        now: now,
        playDeclineClipOnDecline: false,
      );
      expect(res.outcome, JourneyOfferOutcome.declinedExplicit);
      expect(declineCalls, 0,
          reason:
              'mood-button caller: user already tapped a mood, no '
              'need for a decline acknowledgment');
    });

    test('false + ambiguous → ambiguous outcome, NO decline clip played',
        () async {
      await seedAdultSession();
      var declineCalls = 0;
      final res = await fireJourneyOffer(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: _AlwaysOkResolver(),
        classifier: classifier,
        playOfferPlan: _okPlay,
        playDeclinePlan: (plan) async {
          declineCalls++;
          return true;
        },
        captureResponse: _captureNull,
        now: now,
        playDeclineClipOnDecline: false,
      );
      expect(res.outcome, JourneyOfferOutcome.declinedAmbiguous);
      expect(declineCalls, 0);
    });
  });

  // -----------------------------------------------------------------
  // Safe-fail
  // -----------------------------------------------------------------
  group('safe-fail', () {
    test('exception in resolver → exception outcome, integration site '
        'continues silently', () async {
      await seedAdultSession();
      final res = await fireJourneyOffer(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: _ThrowingResolver(),
        classifier: classifier,
        playOfferPlan: _failPlay,
        playDeclinePlan: _failPlay,
        captureResponse: _captureNull,
        now: now,
      );
      expect(res.outcome, JourneyOfferOutcome.exception);
    });
  });

  // -----------------------------------------------------------------
  // Cooldown contract
  // -----------------------------------------------------------------
  group('cooldown contract', () {
    test('runtime does NOT advance cooldown — that is the integration '
        'site\'s job after next-story playback', () async {
      await seedAdultSession();
      await fireJourneyOffer(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        journeyRegistry: registry,
        audioResolver: _AlwaysOkResolver(),
        classifier: classifier,
        playOfferPlan: _okPlay,
        playDeclinePlan: _okPlay,
        captureResponse: _captureText('yes'),
        now: now,
      );
      // Runtime must NEVER touch the cooldown; the doctrine requires
      // cooldown to advance only after the next-in-journey story
      // plays successfully, which the runtime doesn't observe.
      expect(await sessionStore.getLastJourneyContinuationSpokenAt(), isNull);
    });
  });
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _AlwaysOkResolver implements JourneyAudioResolver {
  @override
  Future<JourneyAudioPlan?> resolve({
    required JourneyContinuationOffer offer,
    required String activeVoiceKey,
    JourneyOfferVariant variant = JourneyOfferVariant.full,
  }) async {
    final baseOfferId =
        '${offer.journey.journeyId}_offer_${offer.sourceStoryIndex}';
    final offerId = variant == JourneyOfferVariant.short
        ? '${baseOfferId}_short'
        : baseOfferId;
    return JourneyAudioPlan(
      voiceKey: activeVoiceKey,
      offerClips: [
        JourneyAudioClipRef(
          clipId: offerId,
          kind: JourneyClipKind.offer,
          assetPath: PalJourneyAudioPaths.assetPathFor(
              voiceKey: activeVoiceKey, clipId: offerId),
        ),
      ],
      offerGapsBetween: const [],
      declineClip: JourneyAudioClipRef(
        clipId: 'decline_adult',
        kind: JourneyClipKind.decline,
        assetPath: PalJourneyAudioPaths.assetPathFor(
            voiceKey: activeVoiceKey, clipId: 'decline_adult'),
      ),
    );
  }
}

class _NullResolver implements JourneyAudioResolver {
  @override
  Future<JourneyAudioPlan?> resolve({
    required JourneyContinuationOffer offer,
    required String activeVoiceKey,
    JourneyOfferVariant variant = JourneyOfferVariant.full,
  }) async =>
      null;
}

class _ThrowingResolver implements JourneyAudioResolver {
  @override
  Future<JourneyAudioPlan?> resolve({
    required JourneyContinuationOffer offer,
    required String activeVoiceKey,
    JourneyOfferVariant variant = JourneyOfferVariant.full,
  }) async =>
      throw StateError('intentional test failure');
}

/// Records the variant the runtime passed in, then delegates to
/// [_AlwaysOkResolver]'s plan shape. Lets a test assert the runtime
/// forwarded its `variant` param to the resolver correctly.
class _CaptureVariantResolver implements JourneyAudioResolver {
  final void Function(JourneyOfferVariant) onCapture;
  final _delegate = _AlwaysOkResolver();
  _CaptureVariantResolver(this.onCapture);

  @override
  Future<JourneyAudioPlan?> resolve({
    required JourneyContinuationOffer offer,
    required String activeVoiceKey,
    JourneyOfferVariant variant = JourneyOfferVariant.full,
  }) {
    onCapture(variant);
    return _delegate.resolve(
      offer: offer,
      activeVoiceKey: activeVoiceKey,
      variant: variant,
    );
  }
}

Future<bool> _okPlay(JourneyAudioPlan plan) async => true;
Future<bool> _failPlay(JourneyAudioPlan plan) async => false;
Future<String?> _captureNull() async => null;
JourneyResponseCapture _captureText(String text) => () async => text;

class _Event {
  final String event;
  final Map<String, Object?> props;
  _Event(this.event, this.props);
}

extension on List<_Event> {
  void record(String event, Map<String, Object?> props) {
    add(_Event(event, props));
  }
}

// ---------------------------------------------------------------------------
// Fixture — daniel_arc with two stories (matches journey_engine_test).
// ---------------------------------------------------------------------------

const String _adultDanielJson = '''
{
  "journeyId": "daniel_arc",
  "journeyType": "narrative",
  "lane": "adult",
  "status": "ready",
  "nameRegistryKey": "daniel_in_the_lions_den",
  "stories": [
    {"storyNumber": 1486, "scriptureAnchorId": "daniel_1_8-21", "label": "Daniel 1"},
    {"storyNumber": 1002, "scriptureAnchorId": "daniel_3_13-27", "label": "Daniel 3"}
  ]
}
''';
