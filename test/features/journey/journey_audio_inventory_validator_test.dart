import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/journey/journey.dart';
import 'package:bible_pal/features/journey/journey_audio_paths.dart';

/// Audio inventory validator for journey clips — Journey Doctrine
/// Slice 2 Phase 6. Mirrors Slice 2c.3's
/// `memory_audio_inventory_validator_test.dart`.
///
/// Asserts that for every PAL voice that has *any* rendered journey
/// clips, the bundle contains EVERY clip required by every ready
/// journey in the registry. Partial renders are the failure mode:
/// a voice with carriers but a missing name clip would silently
/// produce silence on every kid-journey offer in that voice.
///
/// Discovery is filesystem-based (not rootBundle-based) so the test
/// runs in plain `flutter test` without needing widget infrastructure.
/// Production uses the same `assets/pal/audio/<VOICE>/journey/*.mp3`
/// paths via `BundledAssetJourneyAudioResolver`.
///
/// Two graceful skips:
///   1. No `assets/pal/audio/` tree at all → skip (PAL audio not set up).
///   2. No voice has any rendered .mp3 in its `journey/` subdirectory
///      → skip (Phase 6 audio render hasn't shipped yet — expected
///      pre-render state). A directory containing only a `.gitkeep`
///      marker counts as "not actively rendering" so it doesn't
///      false-fail.
void main() {
  late List<Journey> readyJourneys;
  late Set<String> requiredAdultStaticClipIds;
  late Set<String> requiredKidStaticClipIds;
  // One entry per offer slot; each inner list is that slot's ACCEPTABLE
  // clip ids in resolver-priority order. The offer is satisfied when at
  // least one is rendered — mirrors BundledAssetJourneyAudioResolver's
  // per-source-story-then-legacy fallback.
  late List<List<String>> requiredPerSourceStoryOffers;

  setUpAll(() {
    // Load every ready adult/kid journey from the live registry on
    // disk. The validator computes its expected-clip set against
    // these — so adding a new journey (or adding stories to one)
    // automatically updates what this test demands without
    // requiring a test edit.
    readyJourneys = _loadReadyJourneys();

    final hasReadyAdult =
        readyJourneys.any((j) => j.lane == JourneyLane.adult);
    final hasReadyKid =
        readyJourneys.any((j) => j.lane == JourneyLane.kid);

    // Lane statics — the decline clip per lane, and (adult, 2026-07-15)
    // the ten Open-Door Tail Family clips: the resolver stitches a
    // rotated tail after every adult offer body and silence-floors the
    // whole offer if no tail is bundled, so a rendered voice missing
    // tails would silently kill every adult journey offer.
    requiredAdultStaticClipIds = hasReadyAdult
        ? const {
            'decline_adult',
            'tail_heart_today',
            'tail_on_your_mind',
            'tail_weighing_on_you',
            'tail_today_been_like',
            'tail_how_youre_doing',
            'tail_whatever_on_mind',
            'tail_mind_lately',
            'tail_thinking_about',
            'tail_day_going',
            'tail_brought_you_here',
          }
        : const {};
    requiredKidStaticClipIds =
        hasReadyKid ? const {'decline_kid'} : const {};

    // Per-source-story offers: one clip per (journey, sourceStoryIndex)
    // where sourceStoryIndex ∈ [0, journey.stories.length - 1).
    // The LAST index has no offer (end-of-journey is silent in
    // Slice 2; Slice 5 Guidance Graph handles that surface).
    //
    // Short-variant clips (`<journeyId>_offer_<idx>_short`) exist in
    // the bundle from the abandoned mood-button variant but are not
    // required — the Entry-Point Split doctrine (2026-06-30) locked
    // the journey cascade to the PAL button only.
    //
    // Each offer slot accepts either convention the resolver tries:
    //   1. `<sourceStoryNumber>_pal_continuation` — Scale-Horizon
    //      per-source-story clip (the outgoing_beats.json ledger).
    //   2. `<journeyId>_offer_<idx>` — legacy per-arc-index clip.
    // At least one must be rendered per voice, or the offer is silent.
    requiredPerSourceStoryOffers = <List<String>>[
      for (final j in readyJourneys)
        for (var i = 0; i < j.stories.length - 1; i++)
          <String>[
            if (j.stories[i].storyNumber != null)
              '${j.stories[i].storyNumber}_pal_continuation',
            '${j.journeyId}_offer_$i',
          ],
    ];
  });

  test('every rendered voice has clips for every ready-journey offer', () {
    final palAudioRoot = Directory('assets/pal/audio');
    if (!palAudioRoot.existsSync()) {
      markTestSkipped('No assets/pal/audio/ tree — PAL audio not set up.');
      return;
    }

    bool hasRenderedJourneyClips(Directory voiceDir) {
      final journeyDir = Directory('${voiceDir.path}/journey');
      if (!journeyDir.existsSync()) return false;
      return journeyDir
          .listSync()
          .whereType<File>()
          .any((f) => f.path.endsWith('.mp3'));
    }

    final voicesWithJourney = palAudioRoot
        .listSync()
        .whereType<Directory>()
        .where(hasRenderedJourneyClips)
        .map((d) => d.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last)
        .toList();

    if (voicesWithJourney.isEmpty) {
      markTestSkipped(
          'No PAL voice has any rendered journey clips yet. Phase 6 audio '
          'render hasn\'t shipped. This test will activate automatically '
          'once any voice has journey audio rendered.');
      return;
    }

    final staticRequired = <String>{
      ...requiredAdultStaticClipIds,
      ...requiredKidStaticClipIds,
    };

    // For each voice that is actively rendering: every static clip must
    // exist, and every per-source-story offer slot must have at least
    // one of its acceptable clips rendered (resolver fallback shape).
    final missing = <String>[];
    for (final voice in voicesWithJourney) {
      for (final clipId in staticRequired) {
        final path = PalJourneyAudioPaths.assetPathFor(
            voiceKey: voice, clipId: clipId);
        if (!File(path).existsSync()) missing.add(path);
      }
      for (final alternatives in requiredPerSourceStoryOffers) {
        final anyPresent = alternatives.any((clipId) => File(
                PalJourneyAudioPaths.assetPathFor(
                    voiceKey: voice, clipId: clipId))
            .existsSync());
        if (!anyPresent) {
          missing.add(
              '$voice: none of {${alternatives.map((c) => "$c.mp3").join(", ")}}');
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'Voices with partially-rendered journey audio. The '
          'bundled resolver would return silence for these journey '
          'offers — and silence on a registered ready journey is a '
          'render gap, not an editorial decision. Render the missing '
          'clips, or change the journey\'s status from "ready" to '
          '"held" until the audio ships.\n\n'
          'Voices present: ${voicesWithJourney.join(", ")}\n'
          'Offer slots required: ${requiredPerSourceStoryOffers.length} '
          '(+ statics ${staticRequired.toList()..sort()})\n'
          'Missing (${missing.length}):\n${missing.join("\n")}',
    );
  });

  test('required-clip enumeration math is sane', () {
    // FINAL Slice 2 Phase 6 math (2026-06-28):
    //   ready-adult journeys contribute 1 static clipId
    //     (decline_adult), shared across all adult journeys.
    //   ready-kid journeys contribute 1 static clipId
    //     (decline_kid), shared across all kid journeys.
    //   Every ready journey (adult OR kid) contributes
    //     (stories.length - 1) per-source-story offer clipIds
    //     `<journeyId>_offer_<index>`.
    //
    // Ceilings on static clipIds catch a refactor that accidentally
    // adds more required statics — a common silent-weakening failure
    // mode. Adult = decline + the 10 Open-Door Tail Family clips
    // (2026-07-15); kid = decline only.
    expect(requiredAdultStaticClipIds.length, lessThanOrEqualTo(11));
    expect(requiredKidStaticClipIds.length, lessThanOrEqualTo(1));

    // Per-source-story offer count == sum over ready journeys of
    // (stories.length - 1). Slice 2 first ship: Daniel Arc (4
    // stories → 3 offers) + Kid David Arc (3 stories → 2 offers)
    // = 5 per-source-story offer clips per voice.
    final expectedPerSourceCount = readyJourneys.fold<int>(
        0, (sum, j) => sum + (j.stories.length - 1));
    expect(requiredPerSourceStoryOffers.length, expectedPerSourceCount);
  });
}

/// Walk assets/stories/journeys/*.json and return every status==ready
/// journey. Mirrors the production loader's filter; failing this read
/// would point at a malformed registry, not a bug in this test.
List<Journey> _loadReadyJourneys() {
  final dir = Directory('assets/stories/journeys');
  if (!dir.existsSync()) return const [];
  final out = <Journey>[];
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    final j = Journey.fromJson(jsonDecode(f.readAsStringSync())
        as Map<String, dynamic>);
    if (j.status == JourneyStatus.ready) out.add(j);
  }
  return out;
}
