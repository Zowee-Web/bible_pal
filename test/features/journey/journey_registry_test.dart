import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/journey/journey.dart';
import 'package:bible_pal/features/journey/journey_registry.dart';

/// Tests for [JourneyRegistry] — Slice 2 Phase 3.
///
/// Pure-Dart: uses the fromJsonStrings constructor with fixture data.
/// The production [JourneyRegistry.load] path (which reads from
/// rootBundle / AssetManifest) is exercised indirectly via the
/// schema validator test + by the full-suite integration test once
/// the cascade lands (Phase 9).
void main() {
  group('construction + invariants', () {
    test('round-trips three valid journeys via fromJsonStrings', () {
      final r = JourneyRegistry.fromJsonStrings([
        _adultDanielJson,
        _adultLearningJson,
        _kidDavidJson,
      ]);
      expect(r.totalJourneyCount, 3);
      expect(r.readyJourneyCount, 2,
          reason: 'learning_to_wait is held; not counted as ready');
    });

    test('readyJourneys excludes non-ready', () {
      final r = JourneyRegistry.fromJsonStrings([
        _adultDanielJson,
        _adultLearningJson,
      ]);
      final readyIds =
          r.readyJourneys.map((j) => j.journeyId).toSet();
      expect(readyIds, {'daniel_arc'});
    });

    test('lookupJourney returns held/draft too (curator API)', () {
      final r = JourneyRegistry.fromJsonStrings([_adultLearningJson]);
      final j = r.lookupJourney('learning_to_wait');
      expect(j, isNotNull);
      expect(j!.status, JourneyStatus.held);
    });

    test('duplicate journeyId throws', () {
      expect(
        () => JourneyRegistry.fromJsonStrings([
          _adultDanielJson,
          _adultDanielJson,
        ]),
        throwsStateError,
      );
    });

    test('two ready adult journeys claiming the same storyNumber throws (sealed lanes)',
        () {
      const collidingJson = '''
{
  "journeyId": "other_daniel_arc",
  "journeyType": "character",
  "lane": "adult",
  "status": "ready",
  "stories": [
    {"storyNumber": 1486, "scriptureAnchorId": "x", "label": "duplicate of 1486"}
  ]
}
''';
      expect(
        () => JourneyRegistry.fromJsonStrings([
          _adultDanielJson,
          collidingJson,
        ]),
        throwsStateError,
      );
    });

    test('held journey does NOT poison the adult-storyNumber index', () {
      // Even though learning_to_wait references real storyNumbers,
      // held status means those slots are NOT registered. A future
      // ready journey can safely claim them without a collision.
      final r = JourneyRegistry.fromJsonStrings([
        _adultLearningJson,
        '''
{
  "journeyId": "future_journey",
  "journeyType": "narrative",
  "lane": "adult",
  "status": "ready",
  "stories": [
    {"storyNumber": 1121, "scriptureAnchorId": "x", "label": "uses 1121"}
  ]
}
''',
      ]);
      final m = r.lookupAdultByStoryNumber(1121);
      expect(m, isNotNull);
      expect(m!.journey.journeyId, 'future_journey');
    });
  });

  group('lookups', () {
    late JourneyRegistry r;
    setUp(() {
      r = JourneyRegistry.fromJsonStrings([
        _adultDanielJson,
        _adultLearningJson, // held — should not be indexed
        _kidDavidJson,
      ]);
    });

    test('lookupAdultByStoryNumber hits Daniel storyNumbers', () {
      final m = r.lookupAdultByStoryNumber(1486);
      expect(m, isNotNull);
      expect(m!.journey.journeyId, 'daniel_arc');
      expect(m.storyIndex, 0);

      final m2 = r.lookupAdultByStoryNumber(1002);
      expect(m2!.storyIndex, 1);
    });

    test('lookupAdultByStoryNumber misses on unknown number', () {
      expect(r.lookupAdultByStoryNumber(9999), isNull);
    });

    test('lookupAdultByStoryNumber misses on held-journey numbers', () {
      // 1121 (Hannah) is in held learning_to_wait — must NOT be
      // indexed.
      expect(r.lookupAdultByStoryNumber(1121), isNull);
    });

    test('lookupKidByAnchorId hits all 3 David kid anchors', () {
      expect(r.lookupKidByAnchorId('david_shepherd')!.storyIndex, 0);
      expect(r.lookupKidByAnchorId('david_goliath')!.storyIndex, 1);
      expect(r.lookupKidByAnchorId('david_king')!.storyIndex, 2);
    });

    test('lookupKidByAnchorId misses on unknown anchor', () {
      expect(r.lookupKidByAnchorId('moses_burning_bush'), isNull);
    });

    test('lookupJourney returns null for unknown id', () {
      expect(r.lookupJourney('totally_made_up'), isNull);
    });
  });
}

// ---------------------------------------------------------------------------
// Fixtures — JSON strings shaped exactly like the real
// assets/stories/journeys/*.json files (3 ready, 1 held).
// ---------------------------------------------------------------------------

const String _adultDanielJson = '''
{
  "journeyId": "daniel_arc",
  "journeyType": "narrative",
  "lane": "adult",
  "status": "ready",
  "nameRegistryKey": "daniel_in_the_lions_den",
  "stories": [
    {"storyNumber": 1486, "scriptureAnchorId": "daniel_1_8-21", "label": "Daniel 1"},
    {"storyNumber": 1002, "scriptureAnchorId": "daniel_3_13-27", "label": "Daniel 3"}
  ]
}
''';

const String _adultLearningJson = '''
{
  "journeyId": "learning_to_wait",
  "journeyType": "theme",
  "lane": "adult",
  "status": "held",
  "themeWord": "waiting on God",
  "stories": [
    {"storyNumber": 1121, "scriptureAnchorId": "1_samuel_1_9-20", "label": "Hannah"},
    {"storyNumber": 1177, "scriptureAnchorId": "luke_2_25-38", "label": "Simeon"}
  ]
}
''';

const String _kidDavidJson = '''
{
  "journeyId": "kid_david_arc",
  "journeyType": "narrative",
  "lane": "kid",
  "status": "ready",
  "characterName": "David",
  "stories": [
    {"productionId": 1836, "anchorId": "david_shepherd", "label": "Shepherd"},
    {"productionId": 1801, "anchorId": "david_goliath", "label": "Goliath"},
    {"productionId": 1908, "anchorId": "david_king", "label": "King"}
  ]
}
''';
