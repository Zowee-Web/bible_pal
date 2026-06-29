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
  late Set<String> requiredAdultClipIds;
  late Set<String> requiredKidStaticClipIds;
  late Set<String> requiredKidPerJourneyOfferClipIds;

  setUpAll(() {
    // Load every ready adult/kid journey from the live registry on
    // disk. The validator computes its expected-clip set against
    // these — so adding a new journey automatically updates what
    // this test demands without requiring a test edit.
    readyJourneys = _loadReadyJourneys();

    final hasReadyAdult =
        readyJourneys.any((j) => j.lane == JourneyLane.adult);
    final hasReadyKid =
        readyJourneys.any((j) => j.lane == JourneyLane.kid);

    // Adult lane: 2 generic clips (offer_narrative_adult + decline_adult),
    // shared across all adult journeys per Cascade Option C.
    requiredAdultClipIds = hasReadyAdult
        ? const {'offer_narrative_adult', 'decline_adult'}
        : const {};

    // Kid lane (post-pivot 2026-06-28): 1 generic clip (decline_kid).
    // The carrier/invitation generic clips were retired when the
    // compositional carrier+name+invitation pattern was replaced by
    // per-journey monolithic offer clips (kid offers sound natural
    // only when the model gets a full sentence context for prosody
    // — single-syllable name slots punch through even with v3).
    requiredKidStaticClipIds = hasReadyKid
        ? const {'decline_kid'}
        : const {};

    // Kid lane per-journey: one full-line offer clip per ready kid
    // journey, named `<journeyId>_offer`. Replaces the prior per-
    // character `name_<x>_journey` clips.
    requiredKidPerJourneyOfferClipIds = readyJourneys
        .where((j) => j.lane == JourneyLane.kid)
        .map((j) => '${j.journeyId}_offer')
        .toSet();
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
      ...requiredAdultClipIds,
      ...requiredKidStaticClipIds,
      ...requiredKidPerJourneyOfferClipIds,
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
    // Post-pivot math (2026-06-28):
    //   ready-adult journeys contribute 2 static adult clipIds
    //     (offer_narrative_adult + decline_adult), shared across
    //     all adult journeys.
    //   ready-kid journeys contribute 1 static kid clipId
    //     (decline_kid), shared across all kid journeys.
    //   ready-kid journeys contribute 1 per-journey clipId
    //     (`<journeyId>_offer`) each.
    //
    // A refactor adding more required clips per journey type would
    // silently weaken this test if the enumeration wasn't pinned —
    // hence the explicit `lessThanOrEqualTo` ceiling on the statics.
    expect(requiredAdultClipIds.length, lessThanOrEqualTo(2));
    expect(requiredKidStaticClipIds.length, lessThanOrEqualTo(1));
    // Per-journey offer count == number of ready kid journeys.
    // Slice 2 first ship: kid David Arc → 1.
    final readyKidJourneyCount =
        readyJourneys.where((j) => j.lane == JourneyLane.kid).length;
    expect(requiredKidPerJourneyOfferClipIds.length,
        readyKidJourneyCount);
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
