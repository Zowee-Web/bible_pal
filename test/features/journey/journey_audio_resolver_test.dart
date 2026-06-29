import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/journey/bundled_asset_journey_audio_resolver.dart';
import 'package:bible_pal/features/journey/journey.dart';
import 'package:bible_pal/features/journey/journey_audio_plan.dart';
import 'package:bible_pal/features/journey/journey_continuation_offer.dart';
import 'package:bible_pal/features/pal_memory/pal_session.dart';

/// Tests for [BundledAssetJourneyAudioResolver] — Slice 2 Phase 6.
///
/// **Doctrine focus:** silence floor. Every gate that could close
/// silently gets a dedicated test asserting `resolve()` returns null
/// instead of partial / fallback / substitute audio.
void main() {
  group('adult resolver — happy path', () {
    test('returns a plan when both adult clips exist', () async {
      final r = BundledAssetJourneyAudioResolver({
        _adultOfferPath('VOICE_STILLWATER'),
        _adultDeclinePath('VOICE_STILLWATER'),
      });
      final plan = await r.resolve(
        offer: _adultOffer(),
        activeVoiceKey: 'VOICE_STILLWATER',
      );
      expect(plan, isNotNull);
      plan!.validateStructure();
      expect(plan.voiceKey, 'VOICE_STILLWATER');
      expect(plan.offerClips, hasLength(1));
      expect(plan.offerClips.first.kind, JourneyClipKind.offer);
      expect(plan.offerClips.first.clipId, 'offer_narrative_adult');
      expect(plan.offerGapsBetween, isEmpty);
      expect(plan.declineClip.kind, JourneyClipKind.decline);
      expect(plan.declineClip.clipId, 'decline_adult');
    });
  });

  group('adult resolver — silence-floor gates', () {
    test('returns null when offer clip is missing', () async {
      final r = BundledAssetJourneyAudioResolver({
        _adultDeclinePath('VOICE_STILLWATER'),
        // offer NOT in bundle
      });
      expect(
        await r.resolve(
            offer: _adultOffer(), activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
      );
    });

    test('returns null when decline clip is missing', () async {
      final r = BundledAssetJourneyAudioResolver({
        _adultOfferPath('VOICE_STILLWATER'),
        // decline NOT in bundle
      });
      expect(
        await r.resolve(
            offer: _adultOffer(), activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
      );
    });

    test('returns null when both clips missing', () async {
      final r = BundledAssetJourneyAudioResolver(const {});
      expect(
        await r.resolve(
            offer: _adultOffer(), activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
      );
    });

    test('voice mismatch: clips exist for HOPE, offer asks for STILLWATER → null',
        () async {
      final r = BundledAssetJourneyAudioResolver({
        _adultOfferPath('VOICE_HOPE'),
        _adultDeclinePath('VOICE_HOPE'),
      });
      expect(
        await r.resolve(
            offer: _adultOffer(), activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
        reason:
            'Slice 2 voice-multiplicity = 1: missing voice = silence, NEVER fall back to another voice',
      );
    });
  });

  group('kid resolver — monolithic offer + decline (post-pivot)', () {
    // Pivot 2026-06-28: kid offers are one full-line clip per
    // journey (`<journeyId>_offer`) + a generic decline clip. The
    // older compositional carrier+name+invitation pattern was
    // retired after Adam ear-checked that standalone 1-syllable
    // names sound punched-out even with v3.

    test('happy path: returns monolithic plan when offer + decline exist',
        () async {
      final r = BundledAssetJourneyAudioResolver({
        _kidOfferPath('VOICE_STILLWATER', 'test_kid'),
        _kidDeclinePath('VOICE_STILLWATER'),
      });
      final plan = await r.resolve(
        offer: _kidOffer(),
        activeVoiceKey: 'VOICE_STILLWATER',
      );
      expect(plan, isNotNull);
      plan!.validateStructure();
      expect(plan.voiceKey, 'VOICE_STILLWATER');
      expect(plan.offerClips, hasLength(1),
          reason: 'kid offer is now MONOLITHIC — one full-line clip, '
              'not carrier+name+invitation stitched');
      expect(plan.offerClips.first.kind, JourneyClipKind.offer);
      expect(plan.offerClips.first.clipId, 'test_kid_offer',
          reason: 'clipId convention: <journeyId>_offer');
      expect(plan.offerGapsBetween, isEmpty,
          reason: 'no stitch gaps inside a monolithic offer');
      expect(plan.declineClip.kind, JourneyClipKind.decline);
      expect(plan.declineClip.clipId, 'decline_kid');
    });

    test('clipId derives from journeyId — kid_david_arc → kid_david_arc_offer',
        () async {
      // Verifies the canonical first-ship Kid David Arc shape.
      final r = BundledAssetJourneyAudioResolver({
        _kidOfferPath('VOICE_STILLWATER', 'kid_david_arc'),
        _kidDeclinePath('VOICE_STILLWATER'),
      });
      final plan = await r.resolve(
        offer: _kidOffer(journeyId: 'kid_david_arc'),
        activeVoiceKey: 'VOICE_STILLWATER',
      );
      expect(plan!.offerClips.first.clipId, 'kid_david_arc_offer');
    });

    test('silence-floor: offer clip missing → null', () async {
      final r = BundledAssetJourneyAudioResolver({
        _kidDeclinePath('VOICE_STILLWATER'),
        // per-journey offer NOT in bundle
      });
      expect(
        await r.resolve(
            offer: _kidOffer(), activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
      );
    });

    test('silence-floor: decline clip missing → null', () async {
      final r = BundledAssetJourneyAudioResolver({
        _kidOfferPath('VOICE_STILLWATER', 'test_kid'),
        // decline NOT in bundle
      });
      expect(
        await r.resolve(
            offer: _kidOffer(), activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
      );
    });

    test('voice mismatch: STILLWATER kid clips exist, offer asks HOPE → null',
        () async {
      final r = BundledAssetJourneyAudioResolver({
        _kidOfferPath('VOICE_STILLWATER', 'test_kid'),
        _kidDeclinePath('VOICE_STILLWATER'),
      });
      expect(
        await r.resolve(
            offer: _kidOffer(), activeVoiceKey: 'VOICE_HOPE'),
        isNull,
        reason:
            'Slice 2 voice-multiplicity = 1: missing voice = silence, NEVER fall back to another voice',
      );
    });
  });

  group('cross-lane safety', () {
    test('adult resolver path used for adult journey even when kid clips present',
        () async {
      // Bundle has BOTH lanes' clips. An adult offer should resolve
      // via adult-path; should not accidentally pull a kid-lane clip.
      final r = BundledAssetJourneyAudioResolver({
        _adultOfferPath('VOICE_STILLWATER'),
        _adultDeclinePath('VOICE_STILLWATER'),
        _kidOfferPath('VOICE_STILLWATER', 'kid_david_arc'),
        _kidDeclinePath('VOICE_STILLWATER'),
      });
      final plan = await r.resolve(
          offer: _adultOffer(), activeVoiceKey: 'VOICE_STILLWATER');
      expect(plan, isNotNull);
      expect(plan!.offerClips, hasLength(1));
      expect(plan.offerClips.first.kind, JourneyClipKind.offer);
      expect(plan.offerClips.first.clipId, 'offer_narrative_adult',
          reason: 'must resolve the adult generic offer, NOT a kid-journey offer');
    });
  });
}

// ---------------------------------------------------------------------------
// Path helpers — small wrappers to keep the test assertions readable
// without rebuilding the asset path string in every line.
// ---------------------------------------------------------------------------

String _adultOfferPath(String voice) =>
    'assets/pal/audio/$voice/journey/offer_narrative_adult.mp3';
String _adultDeclinePath(String voice) =>
    'assets/pal/audio/$voice/journey/decline_adult.mp3';
// Kid: monolithic per-journey offer clip + generic decline.
String _kidOfferPath(String voice, String journeyId) =>
    'assets/pal/audio/$voice/journey/${journeyId}_offer.mp3';
String _kidDeclinePath(String voice) =>
    'assets/pal/audio/$voice/journey/decline_kid.mp3';

// ---------------------------------------------------------------------------
// Offer fixtures.
// ---------------------------------------------------------------------------

JourneyContinuationOffer _adultOffer() {
  final journey = Journey.fromJsonString('''
{
  "journeyId": "test_adult",
  "journeyType": "narrative",
  "lane": "adult",
  "status": "ready",
  "stories": [
    {"storyNumber": 1, "scriptureAnchorId": "a", "label": "x"},
    {"storyNumber": 2, "scriptureAnchorId": "b", "label": "y"}
  ]
}
''');
  return JourneyContinuationOffer(
    journey: journey,
    sourceSession: PalSession(
      storyId: 'story_1_brave_courage_short_traditional',
      completedAt: DateTime.utc(2026, 6, 27),
      languageStyle: 'WEB',
    ),
    sourceStoryIndex: 0,
    nextStoryIndex: 1,
    nextStory: journey.stories[1],
  );
}

JourneyContinuationOffer _kidOffer({String journeyId = 'test_kid'}) {
  // Post-pivot: characterName is no longer used by the resolver.
  // The per-journey clip ID derives from journeyId, not character
  // name. Fixture omits characterName entirely to verify the
  // resolver doesn't depend on it anymore.
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
    sourceStoryIndex: 0,
    nextStoryIndex: 1,
    nextStory: journey.stories[1],
  );
}
