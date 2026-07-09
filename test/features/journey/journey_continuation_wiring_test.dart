import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/journey/bundled_asset_journey_audio_resolver.dart';
import 'package:bible_pal/features/journey/journey.dart';
import 'package:bible_pal/features/journey/journey_audio_paths.dart';
import 'package:bible_pal/features/journey/journey_engine.dart';
import 'package:bible_pal/features/journey/journey_registry.dart';
import 'package:bible_pal/features/pal_memory/pal_session.dart';

/// End-to-end wiring test for the Scale-Horizon per-source-story
/// continuation path (David + Moses arcs, 2026-07-08).
///
/// Unlike the pure-engine and inventory tests, this drives the whole
/// chain against the REAL registry manifests and the REAL rendered
/// STILLWATER clips on disk:
///
///   completed session → JourneyEngine.nextOffer →
///   BundledAssetJourneyAudioResolver.resolve → JourneyAudioPlan
///
/// It proves the three cases Adam named for the on-device pass resolve
/// to the correct `<sourceStoryNumber>_pal_continuation` clip, and that
/// a voice with no journey audio (HOPE) stays silent — the silence
/// floor — rather than resolving to a phantom path.
void main() {
  const engine = JourneyEngine();
  final now = DateTime.utc(2026, 7, 8, 12, 0);

  // Real registry from the on-disk manifests (same files the app loads).
  late JourneyRegistry registry;
  // Real bundled STILLWATER journey clip paths, read from disk.
  late Set<String> stillwaterPaths;

  setUpAll(() {
    final journeyDir = Directory('assets/stories/journeys');
    final jsons = journeyDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .map((f) => f.readAsStringSync())
        .toList();
    registry = JourneyRegistry.fromJsonStrings(jsons);

    final clipDir = Directory('assets/pal/audio/VOICE_STILLWATER/journey');
    stillwaterPaths = clipDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.mp3'))
        // Normalize to the same relative shape assetPathFor produces.
        .map((f) => f.path.replaceFirst(RegExp(r'^\./'), ''))
        .toSet();
  });

  PalSession completed(String sid) => PalSession(
        storyId: sid,
        completedAt: now.subtract(const Duration(days: 1)),
        languageStyle: 'WEB',
      );

  // (source sid, expected next storyNumber, expected offer clipId)
  final cases = <(String, int, String)>[
    ('story_1022_joyful_short_traditional', 1112, '1022_pal_continuation'),
    ('story_1033_brave_courage_short_traditional', 1019, '1033_pal_continuation'),
    ('story_1135_encouraging_short_traditional', 1561, '1135_pal_continuation'),
  ];

  for (final (sid, expectedNext, expectedClipId) in cases) {
    test('$sid → offers $expectedNext via $expectedClipId (STILLWATER)',
        () async {
      final offer = engine.nextOffer(
        sessions: [completed(sid)],
        registry: registry,
        lastJourneyContinuationSpokenAt: null,
        now: now,
        currentLane: JourneyLane.adult,
      );
      expect(offer, isNotNull, reason: '$sid should be a ready-journey story');
      expect(offer!.nextStory.storyNumber, expectedNext);

      final resolver = BundledAssetJourneyAudioResolver(stillwaterPaths);
      final plan =
          await resolver.resolve(offer: offer, activeVoiceKey: 'VOICE_STILLWATER');
      expect(plan, isNotNull,
          reason: 'STILLWATER has the rendered clip — must resolve, not silence');
      expect(plan!.offerClips.single.clipId, expectedClipId,
          reason: 'must resolve the per-source-story clip, not a legacy id');
      final expectedPath = PalJourneyAudioPaths.assetPathFor(
          voiceKey: 'VOICE_STILLWATER', clipId: expectedClipId);
      expect(plan.offerClips.single.assetPath, expectedPath);
      expect(File(expectedPath).existsSync(), isTrue,
          reason: 'the resolved clip is a real file on disk');
    });

    test('$sid → SILENCE on HOPE (no journey audio rendered)', () async {
      final offer = engine.nextOffer(
        sessions: [completed(sid)],
        registry: registry,
        lastJourneyContinuationSpokenAt: null,
        now: now,
        currentLane: JourneyLane.adult,
      );
      // HOPE has zero journey clips → resolver must return null (silence
      // floor), never a phantom plan.
      final resolver = BundledAssetJourneyAudioResolver(stillwaterPaths);
      final plan =
          await resolver.resolve(offer: offer!, activeVoiceKey: 'VOICE_HOPE');
      expect(plan, isNull);
    });
  }

  test('cooldown: an offer spoken 2 days ago suppresses a fresh one', () {
    final offer = engine.nextOffer(
      sessions: [completed('story_1022_joyful_short_traditional')],
      registry: registry,
      lastJourneyContinuationSpokenAt: now.subtract(const Duration(days: 2)),
      now: now,
      currentLane: JourneyLane.adult,
    );
    expect(offer, isNull, reason: '3-day adult cooldown not yet elapsed');
  });
}
