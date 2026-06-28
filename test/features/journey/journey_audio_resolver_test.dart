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
      expect(plan.offerClips.first.clipId, 'journey_offer_adult');
      expect(plan.offerGapsBetween, isEmpty);
      expect(plan.declineClip.kind, JourneyClipKind.decline);
      expect(plan.declineClip.clipId, 'journey_decline_adult');
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

  group('kid resolver — happy path', () {
    test('returns a stitched plan when all 4 clips exist (carrier + name + invitation + decline)',
        () async {
      final r = BundledAssetJourneyAudioResolver({
        _kidCarrierPath('VOICE_STILLWATER'),
        _kidNamePath('VOICE_STILLWATER', 'David'),
        _kidInvitationPath('VOICE_STILLWATER'),
        _kidDeclinePath('VOICE_STILLWATER'),
      });
      final plan = await r.resolve(
        offer: _kidOffer(characterName: 'David'),
        activeVoiceKey: 'VOICE_STILLWATER',
      );
      expect(plan, isNotNull);
      plan!.validateStructure();
      expect(plan.offerClips, hasLength(3));
      expect(plan.offerClips[0].kind, JourneyClipKind.carrier);
      expect(plan.offerClips[0].clipId, 'journey_carrier_kid');
      expect(plan.offerClips[1].kind, JourneyClipKind.name);
      expect(plan.offerClips[1].clipId, 'name_david_journey');
      expect(plan.offerClips[2].kind, JourneyClipKind.invitation);
      expect(plan.offerClips[2].clipId, 'journey_invitation_kid');
      expect(plan.offerGapsBetween, hasLength(2));
      // Both stitch gaps reuse Slice 2d's 50ms carrier→name gap.
      expect(plan.offerGapsBetween[0], const Duration(milliseconds: 50));
      expect(plan.offerGapsBetween[1], const Duration(milliseconds: 50));
      expect(plan.declineClip.clipId, 'journey_decline_kid');
    });

    test('character clip ID is derived per-character (Moses → name_moses_journey)',
        () async {
      final r = BundledAssetJourneyAudioResolver({
        _kidCarrierPath('VOICE_STILLWATER'),
        _kidNamePath('VOICE_STILLWATER', 'Moses'),
        _kidInvitationPath('VOICE_STILLWATER'),
        _kidDeclinePath('VOICE_STILLWATER'),
      });
      final plan = await r.resolve(
        offer: _kidOffer(characterName: 'Moses'),
        activeVoiceKey: 'VOICE_STILLWATER',
      );
      expect(plan!.offerClips[1].clipId, 'name_moses_journey');
    });
  });

  group('kid resolver — silence-floor gates', () {
    test('returns null when carrier missing', () async {
      final r = BundledAssetJourneyAudioResolver({
        // carrier NOT in bundle
        _kidNamePath('VOICE_STILLWATER', 'David'),
        _kidInvitationPath('VOICE_STILLWATER'),
        _kidDeclinePath('VOICE_STILLWATER'),
      });
      expect(
        await r.resolve(
            offer: _kidOffer(characterName: 'David'),
            activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
      );
    });

    test('returns null when name clip missing', () async {
      final r = BundledAssetJourneyAudioResolver({
        _kidCarrierPath('VOICE_STILLWATER'),
        // name NOT in bundle
        _kidInvitationPath('VOICE_STILLWATER'),
        _kidDeclinePath('VOICE_STILLWATER'),
      });
      expect(
        await r.resolve(
            offer: _kidOffer(characterName: 'David'),
            activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
        reason:
            'A kid offer cannot compose without the character name clip',
      );
    });

    test('returns null when invitation missing', () async {
      final r = BundledAssetJourneyAudioResolver({
        _kidCarrierPath('VOICE_STILLWATER'),
        _kidNamePath('VOICE_STILLWATER', 'David'),
        // invitation NOT in bundle
        _kidDeclinePath('VOICE_STILLWATER'),
      });
      expect(
        await r.resolve(
            offer: _kidOffer(characterName: 'David'),
            activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
      );
    });

    test('returns null when decline missing', () async {
      final r = BundledAssetJourneyAudioResolver({
        _kidCarrierPath('VOICE_STILLWATER'),
        _kidNamePath('VOICE_STILLWATER', 'David'),
        _kidInvitationPath('VOICE_STILLWATER'),
        // decline NOT in bundle
      });
      expect(
        await r.resolve(
            offer: _kidOffer(characterName: 'David'),
            activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
      );
    });

    test('voice mismatch: STILLWATER kid clips exist, offer asks HOPE → null',
        () async {
      final r = BundledAssetJourneyAudioResolver({
        _kidCarrierPath('VOICE_STILLWATER'),
        _kidNamePath('VOICE_STILLWATER', 'David'),
        _kidInvitationPath('VOICE_STILLWATER'),
        _kidDeclinePath('VOICE_STILLWATER'),
      });
      expect(
        await r.resolve(
            offer: _kidOffer(characterName: 'David'),
            activeVoiceKey: 'VOICE_HOPE'),
        isNull,
      );
    });

    test('kid offer without characterName → null (cannot compose name slot)',
        () async {
      // Defensive: schema validator should catch this upstream, but
      // the resolver must not crash if it reaches here.
      final r = BundledAssetJourneyAudioResolver({
        _kidCarrierPath('VOICE_STILLWATER'),
        _kidInvitationPath('VOICE_STILLWATER'),
        _kidDeclinePath('VOICE_STILLWATER'),
      });
      expect(
        await r.resolve(
            offer: _kidOffer(characterName: null),
            activeVoiceKey: 'VOICE_STILLWATER'),
        isNull,
      );
    });
  });

  group('cross-lane safety', () {
    test('adult resolver path used for adult journey even when kid clips present',
        () async {
      // Bundle has BOTH lanes' clips. An adult offer should resolve
      // via adult-path; should not accidentally pull kid clips.
      final r = BundledAssetJourneyAudioResolver({
        _adultOfferPath('VOICE_STILLWATER'),
        _adultDeclinePath('VOICE_STILLWATER'),
        _kidCarrierPath('VOICE_STILLWATER'),
        _kidNamePath('VOICE_STILLWATER', 'David'),
        _kidInvitationPath('VOICE_STILLWATER'),
        _kidDeclinePath('VOICE_STILLWATER'),
      });
      final plan = await r.resolve(
          offer: _adultOffer(), activeVoiceKey: 'VOICE_STILLWATER');
      expect(plan, isNotNull);
      expect(plan!.offerClips, hasLength(1)); // adult shape, not kid 3-clip
      expect(plan.offerClips.first.kind, JourneyClipKind.offer);
    });
  });
}

// ---------------------------------------------------------------------------
// Path helpers — small wrappers to keep the test assertions readable
// without rebuilding the asset path string in every line.
// ---------------------------------------------------------------------------

String _adultOfferPath(String voice) =>
    'assets/pal/audio/$voice/journey/journey_offer_adult.mp3';
String _adultDeclinePath(String voice) =>
    'assets/pal/audio/$voice/journey/journey_decline_adult.mp3';
String _kidCarrierPath(String voice) =>
    'assets/pal/audio/$voice/journey/journey_carrier_kid.mp3';
String _kidNamePath(String voice, String character) =>
    'assets/pal/audio/$voice/journey/name_${character.toLowerCase()}_journey.mp3';
String _kidInvitationPath(String voice) =>
    'assets/pal/audio/$voice/journey/journey_invitation_kid.mp3';
String _kidDeclinePath(String voice) =>
    'assets/pal/audio/$voice/journey/journey_decline_kid.mp3';

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

JourneyContinuationOffer _kidOffer({required String? characterName}) {
  final cn = characterName == null
      ? ''
      : '"characterName": "$characterName",';
  final journey = Journey.fromJsonString('''
{
  "journeyId": "test_kid",
  "journeyType": "narrative",
  "lane": "kid",
  "status": "ready",
  $cn
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
