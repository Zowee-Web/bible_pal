import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/journey/journey_audio_paths.dart';
import 'package:bible_pal/features/journey/journey_audio_plan.dart';

/// Tests for [JourneyAudioPlan] + [PalJourneyAudioPaths] —
/// Slice 2 Phase 6.
///
/// Mirrors the Slice 2c.2 MemoryAudioPlan tests. Pure data; no IO.
void main() {
  group('PalJourneyAudioPaths.assetPathFor', () {
    test('composes the expected bundled-asset path', () {
      final p = PalJourneyAudioPaths.assetPathFor(
        voiceKey: 'VOICE_STILLWATER',
        clipId: 'journey_offer_adult',
      );
      expect(p,
          'assets/pal/audio/VOICE_STILLWATER/journey/journey_offer_adult.mp3');
    });

    test('lands under journey/ sibling of memory/ (Slice 2d convention)', () {
      final p = PalJourneyAudioPaths.assetPathFor(
        voiceKey: 'VOICE_STILLWATER',
        clipId: 'name_david_journey',
      );
      expect(p, startsWith('assets/pal/audio/VOICE_STILLWATER/'));
      expect(p, contains('/journey/'));
      expect(p, endsWith('.mp3'));
    });

    test('voice key is part of the path (per-voice isolation)', () {
      expect(
        PalJourneyAudioPaths.assetPathFor(
            voiceKey: 'VOICE_HOPE', clipId: 'x'),
        isNot(equals(PalJourneyAudioPaths.assetPathFor(
            voiceKey: 'VOICE_STILLWATER', clipId: 'x'))),
      );
    });
  });

  group('PalJourneyAudioPaths.nameClipIdFor — convention', () {
    test('single-word character: "David" → "name_david_journey"', () {
      expect(PalJourneyAudioPaths.nameClipIdFor('David'), 'name_david_journey');
    });

    test('multi-word character: "Mary Magdalene" → "name_mary_magdalene_journey"',
        () {
      expect(PalJourneyAudioPaths.nameClipIdFor('Mary Magdalene'),
          'name_mary_magdalene_journey');
    });

    test('article + capitals: "the Good Samaritan" → "name_the_good_samaritan_journey"',
        () {
      expect(PalJourneyAudioPaths.nameClipIdFor('the Good Samaritan'),
          'name_the_good_samaritan_journey');
    });

    test('apostrophes and punctuation become underscores (no double-underscore)',
        () {
      // "David's" → "name_david_s_journey" — apostrophe is non-alphanumeric
      // so it's replaced with an underscore. Between two letters, so no
      // _+ collapse needed.
      expect(PalJourneyAudioPaths.nameClipIdFor("David's"),
          'name_david_s_journey');
      // "Mary—Mother of Jesus" — em-dash should also collapse without
      // producing double underscores adjacent to spaces.
      expect(PalJourneyAudioPaths.nameClipIdFor('Mary - Mother'),
          'name_mary_mother_journey');
    });

    test('numeric characters allowed (forward compat: e.g. "Mary 2")', () {
      expect(PalJourneyAudioPaths.nameClipIdFor('Mary 2'),
          'name_mary_2_journey');
    });

    test('clipIds are distinct from Slice 2d display_name_registry "name_<x>"',
        () {
      // The _journey suffix is what keeps these from colliding with
      // recognition clips. Verify the suffix is always there.
      for (final name in ['David', 'Daniel', 'Jonah', 'the Good Samaritan']) {
        expect(PalJourneyAudioPaths.nameClipIdFor(name),
            endsWith('_journey'));
      }
    });

    test('empty character name throws', () {
      expect(() => PalJourneyAudioPaths.nameClipIdFor(''),
          throwsArgumentError);
      expect(() => PalJourneyAudioPaths.nameClipIdFor('   '),
          throwsArgumentError);
    });

    test('all-punctuation character name throws (would normalize to empty)',
        () {
      expect(() => PalJourneyAudioPaths.nameClipIdFor("!!!"),
          throwsArgumentError);
    });
  });

  group('JourneyAudioPlan structural invariants', () {
    test('adult plan: 1 offerClip, 0 gaps, decline present → valid', () {
      final plan = _adultPlan();
      expect(() => plan.validateStructure(), returnsNormally);
      expect(plan.offerClips, hasLength(1));
      expect(plan.offerGapsBetween, isEmpty);
    });

    test('kid plan: 3 offerClips, 2 gaps, decline present → valid', () {
      final plan = _kidPlan();
      expect(() => plan.validateStructure(), returnsNormally);
      expect(plan.offerClips, hasLength(3));
      expect(plan.offerGapsBetween, hasLength(2));
    });

    test('empty offerClips → throws', () {
      final bad = JourneyAudioPlan(
        voiceKey: 'VOICE_STILLWATER',
        offerClips: const [],
        offerGapsBetween: const [],
        declineClip: _clip('d', JourneyClipKind.decline),
      );
      expect(() => bad.validateStructure(), throwsStateError);
    });

    test('gap count mismatch → throws (gaps must equal clips - 1)', () {
      final bad = JourneyAudioPlan(
        voiceKey: 'VOICE_STILLWATER',
        offerClips: [
          _clip('a', JourneyClipKind.carrier),
          _clip('b', JourneyClipKind.name),
          _clip('c', JourneyClipKind.invitation),
        ],
        offerGapsBetween: const [
          Duration(milliseconds: 50),
        ], // should be 2 not 1
        declineClip: _clip('d', JourneyClipKind.decline),
      );
      expect(() => bad.validateStructure(), throwsStateError);
    });

    test('declineClip with wrong kind → throws', () {
      final bad = JourneyAudioPlan(
        voiceKey: 'VOICE_STILLWATER',
        offerClips: [_clip('a', JourneyClipKind.offer)],
        offerGapsBetween: const [],
        // Wrong kind on the decline slot.
        declineClip: _clip('d', JourneyClipKind.invitation),
      );
      expect(() => bad.validateStructure(), throwsStateError);
    });
  });

  group('JourneyAudioPlan field passthrough', () {
    test('voiceKey, offerClips, offerGapsBetween, declineClip are stored verbatim',
        () {
      final plan = _kidPlan();
      expect(plan.voiceKey, 'VOICE_STILLWATER');
      expect(plan.offerClips[0].kind, JourneyClipKind.carrier);
      expect(plan.offerClips[1].kind, JourneyClipKind.name);
      expect(plan.offerClips[2].kind, JourneyClipKind.invitation);
      expect(plan.declineClip.kind, JourneyClipKind.decline);
    });
  });
}

JourneyAudioClipRef _clip(String id, JourneyClipKind kind) {
  return JourneyAudioClipRef(
    clipId: id,
    kind: kind,
    assetPath: PalJourneyAudioPaths.assetPathFor(
        voiceKey: 'VOICE_STILLWATER', clipId: id),
  );
}

JourneyAudioPlan _adultPlan() => JourneyAudioPlan(
      voiceKey: 'VOICE_STILLWATER',
      offerClips: [_clip('journey_offer_adult', JourneyClipKind.offer)],
      offerGapsBetween: const [],
      declineClip:
          _clip('journey_decline_adult', JourneyClipKind.decline),
    );

JourneyAudioPlan _kidPlan() => JourneyAudioPlan(
      voiceKey: 'VOICE_STILLWATER',
      offerClips: [
        _clip('journey_carrier_kid', JourneyClipKind.carrier),
        _clip('name_david_journey', JourneyClipKind.name),
        _clip('journey_invitation_kid', JourneyClipKind.invitation),
      ],
      offerGapsBetween: const [
        Duration(milliseconds: 50),
        Duration(milliseconds: 50),
      ],
      declineClip: _clip('journey_decline_kid', JourneyClipKind.decline),
    );
