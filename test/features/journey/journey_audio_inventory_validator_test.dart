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
  late Set<String> requiredPerSourceStoryOfferClipIds;

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

    // Lane statics — just the decline clip per lane (shared across
    // all journeys in that lane). Post-pivot 2026-06-28: the
    // generic `offer_narrative_adult` clip is no longer required —
    // adult offers became per-source-story like kid.
    requiredAdultStaticClipIds =
        hasReadyAdult ? const {'decline_adult'} : const {};
    requiredKidStaticClipIds =
        hasReadyKid ? const {'decline_kid'} : const {};

    // Per-source-story offers: TWO clips per (journey, sourceStoryIndex)
    // where sourceStoryIndex ∈ [0, journey.stories.length - 1) —
    // full variant (cold-open) + short variant (mood-button).
    // See journey_audio_resolver.dart JourneyOfferVariant. The LAST
    // index has no offer (end-of-journey is silent in Slice 2;
    // Slice 5 Guidance Graph handles that surface).
    requiredPerSourceStoryOfferClipIds = <String>{
      for (final j in readyJourneys)
        for (var i = 0; i < j.stories.length - 1; i++) ...[
          '${j.journeyId}_offer_$i',
          '${j.journeyId}_offer_${i}_short',
        ],
    };
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

    final allRequired = <String>{
      ...requiredAdultStaticClipIds,
      ...requiredKidStaticClipIds,
      ...requiredPerSourceStoryOfferClipIds,
    };

    // For each voice that is actively rendering, every required
    // clipId must exist as a file under that voice's journey dir.
    final missing = <String>[];
    final present = <String>[];
    for (final voice in voicesWithJourney) {
      for (final clipId in allRequired) {
        final path = PalJourneyAudioPaths.assetPathFor(
            voiceKey: voice, clipId: clipId);
        if (File(path).existsSync()) {
          present.add(path);
        } else {
          missing.add(path);
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
          'Required clipIds (${allRequired.length}): ${allRequired.toList()..sort()}\n'
          'Missing files (${missing.length}):\n${missing.join("\n")}',
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
    // The `lessThanOrEqualTo(1)` ceiling on static clipIds catches
    // a refactor that accidentally adds more required statics — a
    // common silent-weakening failure mode.
    expect(requiredAdultStaticClipIds.length, lessThanOrEqualTo(1));
    expect(requiredKidStaticClipIds.length, lessThanOrEqualTo(1));

    // Per-source-story offer count == sum over ready journeys of
    // 2 × (stories.length - 1) — full variant + short variant
    // per (journey, sourceStoryIndex) pair since PR B added the
    // mood-button entry point. Daniel Arc (4 stories → 3 pairs
    // → 6 clips) + Kid David Arc (3 stories → 2 pairs → 4 clips)
    // = 10 per-source-story offer clips per voice.
    final expectedPerSourceCount = readyJourneys.fold<int>(
        0, (sum, j) => sum + 2 * (j.stories.length - 1));
    expect(requiredPerSourceStoryOfferClipIds.length,
        expectedPerSourceCount);
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
