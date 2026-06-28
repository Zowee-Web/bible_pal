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
  late Set<String> requiredKidCharacterClipIds;

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

    requiredAdultClipIds = hasReadyAdult
        ? const {'journey_offer_adult', 'journey_decline_adult'}
        : const {};

    requiredKidStaticClipIds = hasReadyKid
        ? const {
            'journey_carrier_kid',
            'journey_invitation_kid',
            'journey_decline_kid',
          }
        : const {};

    requiredKidCharacterClipIds = readyJourneys
        .where((j) => j.lane == JourneyLane.kid)
        .map((j) {
          final cn = j.characterName;
          if (cn == null || cn.isEmpty) return null;
          return PalJourneyAudioPaths.nameClipIdFor(cn);
        })
        .whereType<String>()
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
      ...requiredKidCharacterClipIds,
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
    // The validator's math: ready-adult journeys contribute 2 static
    // adult clipIds (offer + decline); ready-kid journeys contribute
    // 3 static kid clipIds (carrier + invitation + decline) + one
    // per-journey character clip. Sanity-check that nothing has
    // drifted (a refactor adding more required clips per journey
    // type would silently weaken this test if the enumeration
    // wasn't pinned).
    expect(requiredAdultClipIds.length, lessThanOrEqualTo(2));
    expect(requiredKidStaticClipIds.length, lessThanOrEqualTo(3));
    // Character clipId count == number of ready kid journeys with
    // a characterName. Slice 2 first ship: kid David Arc → 1.
    final readyKidJourneysWithName = readyJourneys.where(
        (j) => j.lane == JourneyLane.kid && (j.characterName ?? '').isNotEmpty);
    expect(requiredKidCharacterClipIds.length,
        readyKidJourneysWithName.length);
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
