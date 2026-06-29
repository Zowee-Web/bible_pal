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
        clipId: 'offer_narrative_adult',
      );
      expect(p,
          'assets/pal/audio/VOICE_STILLWATER/journey/offer_narrative_adult.mp3');
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

    test('kid plan (post-pivot): 1 offerClip, 0 gaps, decline present → valid',
        () {
      // Post-pivot kid plans are MONOLITHIC (one full-line per-journey
      // offer clip). Structurally identical to adult plans now.
      final plan = _kidPlan();
      expect(() => plan.validateStructure(), returnsNormally);
      expect(plan.offerClips, hasLength(1));
      expect(plan.offerGapsBetween, isEmpty);
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
      // Post-pivot kid plans carry a single OFFER-kind clip
      // (monolithic per-journey clip), not the older carrier+name+
      // invitation stitched sequence.
      expect(plan.offerClips, hasLength(1));
      expect(plan.offerClips[0].kind, JourneyClipKind.offer);
      expect(plan.offerClips[0].clipId, endsWith('_offer'));
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
      offerClips: [_clip('offer_narrative_adult', JourneyClipKind.offer)],
      offerGapsBetween: const [],
      declineClip:
          _clip('decline_adult', JourneyClipKind.decline),
    );

// Post-pivot 2026-06-28: kid plan is now MONOLITHIC (one full-line
// per-journey offer clip + generic decline). The older stitched
// carrier+name+invitation shape was retired; see
// bundled_asset_journey_audio_resolver.dart for the pivot rationale.
JourneyAudioPlan _kidPlan() => JourneyAudioPlan(
      voiceKey: 'VOICE_STILLWATER',
      offerClips: [
        _clip('kid_david_arc_offer', JourneyClipKind.offer),
      ],
      offerGapsBetween: const [],
      declineClip: _clip('decline_kid', JourneyClipKind.decline),
    );
