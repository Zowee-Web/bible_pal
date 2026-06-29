import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/journey/bundled_asset_journey_audio_resolver.dart';
import 'package:bible_pal/features/journey/journey.dart';
import 'package:bible_pal/features/journey/journey_audio_plan.dart';
import 'package:bible_pal/features/journey/journey_continuation_offer.dart';
import 'package:bible_pal/features/pal_memory/pal_session.dart';

/// Tests for [BundledAssetJourneyAudioResolver] — Slice 2 Phase 6
/// FINAL shape (per-source-story monolithic offer + lane-specific decline).
///
/// **Doctrine focus:** silence floor at every gate. Every clip the
/// resolver needs gets a dedicated test asserting `resolve()` returns
/// null when that clip is missing — no partial plans, no fallback,
/// no substitute audio.
///
/// **Clip ID conventions tested:**
///   - Offer:   `<journeyId>_offer_<sourceStoryIndex>` (both lanes)
///   - Decline: `decline_adult` (adult), `decline_kid` (kid)
void main() {
  group('adult resolver — happy path', () {
    test('returns a per-source-story plan when both clips exist',
        () async {
      final r = BundledAssetJourneyAudioResolver({
        _offerPath('VOICE_STILLWATER', 'test_adult', 0),
        _declinePath('VOICE_STILLWATER', JourneyLane.adult),
      });
      final plan = await r.resolve(
        offer: _adultOffer(sourceStoryIndex: 0),
        activeVoiceKey: 'VOICE_STILLWATER',
      );
      expect(plan, isNotNull);
      plan!.validateStructure();
      expect(plan.voiceKey, 'VOICE_STILLWATER');
      expect(plan.offerClips, hasLength(1));
      expect(plan.offerClips.first.kind, JourneyClipKind.offer);
      expect(plan.offerClips.first.clipId, 'test_adult_offer_0',
          reason: 'clipId convention: <journeyId>_offer_<sourceStoryIndex>');
      expect(plan.offerGapsBetween, isEmpty);
      expect(plan.declineClip.kind, JourneyClipKind.decline);
      expect(plan.declineClip.clipId, 'decline_adult');
    });

    test('clip ID encodes the sourceStoryIndex (0 vs 1 vs 2)',
        () async {
      // daniel_arc has 4 stories so valid offer indices are 0, 1, 2
      // (index 3 = end-of-journey, engine never produces an offer).
      final r = BundledAssetJourneyAudioResolver({
        _offerPath('VOICE_STILLWATER', 'daniel_arc', 0),
        _offerPath('VOICE_STILLWATER', 'daniel_arc', 1),
        _offerPath('VOICE_STILLWATER', 'daniel_arc', 2),
        _declinePath('VOICE_STILLWATER', JourneyLane.adult),
      });
      for (final sourceIdx in [0, 1, 2]) {
        final plan = await r.resolve(
          offer: _adultOffer(
              journeyId: 'daniel_arc', sourceStoryIndex: sourceIdx),
          activeVoiceKey: 'VOICE_STILLWATER',
        );
        expect(plan, isNotNull, reason: 'sourceStoryIndex=$sourceIdx');
        expect(plan!.offerClips.first.clipId,
            'daniel_arc_offer_$sourceIdx');
      }
    });
  });

  group('adult resolver — silence-floor gates', () {
    test('returns null when the per-source-story offer clip is missing',
        () async {
      final r = BundledAssetJourneyAudioResolver({
        _declinePath('VOICE_STILLWATER', JourneyLane.adult),
        // offer NOT in bundle
      });
      expect(
        await r.resolve(
            offer: _adultOffer(sourceStoryIndex: 0),
            activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
      );
    });

    test('returns null when decline clip is missing', () async {
      final r = BundledAssetJourneyAudioResolver({
        _offerPath('VOICE_STILLWATER', 'test_adult', 0),
        // decline NOT in bundle
      });
      expect(
        await r.resolve(
            offer: _adultOffer(sourceStoryIndex: 0),
            activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
      );
    });

    test('returns null when both clips missing', () async {
      final r = BundledAssetJourneyAudioResolver(const {});
      expect(
        await r.resolve(
            offer: _adultOffer(sourceStoryIndex: 0),
            activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
      );
    });

    test('returns null when the SPECIFIC sourceStoryIndex offer is missing',
        () async {
      // The bundle has the offer for index 0 but not index 1. An
      // offer with sourceStoryIndex=1 must NOT silently fall back
      // to index 0 — silence-floor honesty.
      final r = BundledAssetJourneyAudioResolver({
        _offerPath('VOICE_STILLWATER', 'test_adult', 0),
        // index 1 NOT in bundle
        _declinePath('VOICE_STILLWATER', JourneyLane.adult),
      });
      expect(
        await r.resolve(
            offer: _adultOffer(sourceStoryIndex: 1),
            activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
        reason: 'missing per-source-story clip → silence, never reuse '
            'a different index\'s clip',
      );
    });

    test('voice mismatch: clips exist for HOPE, offer asks for STILLWATER → null',
        () async {
      final r = BundledAssetJourneyAudioResolver({
        _offerPath('VOICE_HOPE', 'test_adult', 0),
        _declinePath('VOICE_HOPE', JourneyLane.adult),
      });
      expect(
        await r.resolve(
            offer: _adultOffer(sourceStoryIndex: 0),
            activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
        reason:
            'Slice 2 voice-multiplicity = 1: missing voice = silence, NEVER fall back to another voice',
      );
    });
  });

  group('kid resolver — same monolithic shape, different decline clip', () {
    test('happy path: returns per-source-story plan with kid decline',
        () async {
      final r = BundledAssetJourneyAudioResolver({
        _offerPath('VOICE_STILLWATER', 'test_kid', 0),
        _declinePath('VOICE_STILLWATER', JourneyLane.kid),
      });
      final plan = await r.resolve(
        offer: _kidOffer(sourceStoryIndex: 0),
        activeVoiceKey: 'VOICE_STILLWATER',
      );
      expect(plan, isNotNull);
      plan!.validateStructure();
      expect(plan.offerClips, hasLength(1));
      expect(plan.offerClips.first.clipId, 'test_kid_offer_0');
      expect(plan.declineClip.clipId, 'decline_kid');
    });

    test('canonical first-ship Kid David Arc: kid_david_arc_offer_0/1',
        () async {
      // Validates the actual shipping fixture: Kid David Arc has 3
      // stories so valid offer indices are 0 and 1 (after Shepherd
      // / after Goliath). Index 2 = end-of-journey, no offer.
      final r = BundledAssetJourneyAudioResolver({
        _offerPath('VOICE_STILLWATER', 'kid_david_arc', 0),
        _offerPath('VOICE_STILLWATER', 'kid_david_arc', 1),
        _declinePath('VOICE_STILLWATER', JourneyLane.kid),
      });
      for (final sourceIdx in [0, 1]) {
        final plan = await r.resolve(
          offer: _kidOffer(
              journeyId: 'kid_david_arc', sourceStoryIndex: sourceIdx),
          activeVoiceKey: 'VOICE_STILLWATER',
        );
        expect(plan!.offerClips.first.clipId,
            'kid_david_arc_offer_$sourceIdx');
      }
    });

    test('silence-floor: kid offer clip missing → null', () async {
      final r = BundledAssetJourneyAudioResolver({
        _declinePath('VOICE_STILLWATER', JourneyLane.kid),
      });
      expect(
        await r.resolve(
            offer: _kidOffer(sourceStoryIndex: 0),
            activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
      );
    });

    test('silence-floor: kid decline clip missing → null', () async {
      final r = BundledAssetJourneyAudioResolver({
        _offerPath('VOICE_STILLWATER', 'test_kid', 0),
      });
      expect(
        await r.resolve(
            offer: _kidOffer(sourceStoryIndex: 0),
            activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
      );
    });

    test('kid does NOT use the adult decline clip (and vice versa)',
        () async {
      // Bundle has the adult decline but NOT the kid decline.
      // A kid offer must NOT fall back to decline_adult.
      final r = BundledAssetJourneyAudioResolver({
        _offerPath('VOICE_STILLWATER', 'test_kid', 0),
        _declinePath('VOICE_STILLWATER', JourneyLane.adult),
        // kid decline NOT in bundle
      });
      expect(
        await r.resolve(
            offer: _kidOffer(sourceStoryIndex: 0),
            activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
        reason:
            'kid lane decline is decline_kid; must not silently use decline_adult',
      );
    });
  });

  group('cross-lane safety', () {
    test('adult journey resolves to adult-decline; kid to kid-decline',
        () async {
      // Bundle has BOTH lanes' clips + both per-source-story offers.
      // Adult offer should pick decline_adult; kid offer should
      // pick decline_kid.
      final r = BundledAssetJourneyAudioResolver({
        _offerPath('VOICE_STILLWATER', 'test_adult', 0),
        _offerPath('VOICE_STILLWATER', 'test_kid', 0),
        _declinePath('VOICE_STILLWATER', JourneyLane.adult),
        _declinePath('VOICE_STILLWATER', JourneyLane.kid),
      });
      final adultPlan = await r.resolve(
          offer: _adultOffer(sourceStoryIndex: 0),
          activeVoiceKey: 'VOICE_STILLWATER');
      final kidPlan = await r.resolve(
          offer: _kidOffer(sourceStoryIndex: 0),
          activeVoiceKey: 'VOICE_STILLWATER');

      expect(adultPlan!.declineClip.clipId, 'decline_adult');
      expect(kidPlan!.declineClip.clipId, 'decline_kid');
    });
  });
}

// ---------------------------------------------------------------------------
// Path helpers — unified across lanes now that both use
// <journeyId>_offer_<sourceStoryIndex>.
// ---------------------------------------------------------------------------

String _offerPath(String voice, String journeyId, int sourceStoryIndex) =>
    'assets/pal/audio/$voice/journey/${journeyId}_offer_$sourceStoryIndex.mp3';

String _declinePath(String voice, JourneyLane lane) {
  final clip = lane == JourneyLane.adult ? 'decline_adult' : 'decline_kid';
  return 'assets/pal/audio/$voice/journey/$clip.mp3';
}

// ---------------------------------------------------------------------------
// Offer fixtures.
// ---------------------------------------------------------------------------

JourneyContinuationOffer _adultOffer({
  String journeyId = 'test_adult',
  int sourceStoryIndex = 0,
}) {
  final journey = Journey.fromJsonString('''
{
  "journeyId": "$journeyId",
  "journeyType": "narrative",
  "lane": "adult",
  "status": "ready",
  "stories": [
    {"storyNumber": 1, "scriptureAnchorId": "a", "label": "x"},
    {"storyNumber": 2, "scriptureAnchorId": "b", "label": "y"},
    {"storyNumber": 3, "scriptureAnchorId": "c", "label": "z"},
    {"storyNumber": 4, "scriptureAnchorId": "d", "label": "w"}
  ]
}
''');
  return JourneyContinuationOffer(
    journey: journey,
    sourceSession: PalSession(
      storyId: 'story_${sourceStoryIndex + 1}_brave_courage_short_traditional',
      completedAt: DateTime.utc(2026, 6, 27),
      languageStyle: 'WEB',
    ),
    sourceStoryIndex: sourceStoryIndex,
    nextStoryIndex: sourceStoryIndex + 1,
    nextStory: journey.stories[sourceStoryIndex + 1],
  );
}

JourneyContinuationOffer _kidOffer({
  String journeyId = 'test_kid',
  int sourceStoryIndex = 0,
}) {
  final journey = Journey.fromJsonString('''
{
  "journeyId": "$journeyId",
  "journeyType": "narrative",
  "lane": "kid",
  "status": "ready",
  "stories": [
    {"productionId": 1, "anchorId": "a", "label": "x"},
    {"productionId": 2, "anchorId": "b", "label": "y"},
    {"productionId": 3, "anchorId": "c", "label": "z"}
  ]
}
''');
  return JourneyContinuationOffer(
    journey: journey,
    sourceSession: PalSession(
      storyId: 'kidstory_kid_a_short',
      completedAt: DateTime.utc(2026, 6, 27),
      languageStyle: 'WEB',
    ),
    sourceStoryIndex: sourceStoryIndex,
    nextStoryIndex: sourceStoryIndex + 1,
    nextStory: journey.stories[sourceStoryIndex + 1],
  );
}
