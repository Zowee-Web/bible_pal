import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/journey/journey.dart';

/// Pure-Dart tests for [Journey] + [JourneyStory] models.
///
/// Journey Doctrine, Slice 2 (docs/JOURNEY_DOCTRINE.md). Covers
/// fromJson happy paths + every error path the schema validator test
/// catches at CI time, so a malformed runtime JSON (e.g. a forked
/// branch that bypassed the validator) throws cleanly instead of
/// silently producing a malformed Journey.
void main() {
  group('JourneyStory.fromJson', () {
    test('adult: storyNumber + scriptureAnchorId + label', () {
      final s = JourneyStory.fromJson({
        'storyNumber': 1486,
        'scriptureAnchorId': 'daniel_1_8-21',
        'label': 'Daniel 1 — the ten-day test',
      });
      expect(s.storyNumber, 1486);
      expect(s.productionId, isNull);
      expect(s.scriptureAnchorId, 'daniel_1_8-21');
      expect(s.anchorId, isNull);
      expect(s.label, contains('Daniel 1'));
      expect(s.editorialNote, isNull);
    });

    test('kid: productionId + anchorId + label', () {
      final s = JourneyStory.fromJson({
        'productionId': 1801,
        'anchorId': 'david_goliath',
        'label': '1 Samuel 17 — David and Goliath',
      });
      expect(s.productionId, 1801);
      expect(s.storyNumber, isNull);
      expect(s.anchorId, 'david_goliath');
      expect(s.scriptureAnchorId, isNull);
    });

    test('editorialNote passes through when present', () {
      final s = JourneyStory.fromJson({
        'storyNumber': 1,
        'scriptureAnchorId': 'x',
        'label': 'l',
        'editorialNote': 'curator only',
      });
      expect(s.editorialNote, 'curator only');
    });

    test('rejects entries with BOTH storyNumber and productionId', () {
      expect(
        () => JourneyStory.fromJson({
          'storyNumber': 1,
          'productionId': 2,
          'scriptureAnchorId': 'x',
          'label': 'l',
        }),
        throwsStateError,
      );
    });

    test('rejects entries with NEITHER storyNumber nor productionId', () {
      expect(
        () => JourneyStory.fromJson({
          'scriptureAnchorId': 'x',
          'label': 'l',
        }),
        throwsStateError,
      );
    });

    test('rejects entries with no anchor identifier', () {
      expect(
        () => JourneyStory.fromJson({
          'storyNumber': 1,
          'label': 'l',
        }),
        throwsStateError,
      );
    });

    test('rejects entries missing label', () {
      expect(
        () => JourneyStory.fromJson({
          'storyNumber': 1,
          'scriptureAnchorId': 'x',
        }),
        throwsStateError,
      );
    });

    test('rejects empty label', () {
      expect(
        () => JourneyStory.fromJson({
          'storyNumber': 1,
          'scriptureAnchorId': 'x',
          'label': '',
        }),
        throwsStateError,
      );
    });
  });

  group('Journey.fromJson — happy paths', () {
    test('adult narrative journey loads with all enums correct', () {
      final j = Journey.fromJson(_adultDanielJson());
      expect(j.journeyId, 'daniel_arc');
      expect(j.journeyType, JourneyType.narrative);
      expect(j.lane, JourneyLane.adult);
      expect(j.status, JourneyStatus.ready);
      expect(j.nameRegistryKey, 'daniel_in_the_lions_den');
      expect(j.stories, hasLength(2));
      expect(j.stories.first.storyNumber, 1486);
      expect(j.stories.last.storyNumber, 1002);
    });

    test('kid narrative journey loads with all enums correct', () {
      final j = Journey.fromJson(_kidDavidJson());
      expect(j.journeyId, 'kid_david_arc');
      expect(j.journeyType, JourneyType.narrative);
      expect(j.lane, JourneyLane.kid);
      expect(j.characterName, 'David');
      expect(j.stories, hasLength(3));
      expect(j.stories.first.productionId, 1836);
      expect(j.stories.first.anchorId, 'david_shepherd');
    });

    test('theme journey carries themeWord', () {
      final j = Journey.fromJson({
        'journeyId': 'learning_to_wait',
        'journeyType': 'theme',
        'lane': 'adult',
        'status': 'held',
        'themeWord': 'waiting on God',
        'stories': [
          {
            'storyNumber': 1121,
            'scriptureAnchorId': '1_samuel_1_9-20',
            'label': 'Hannah prays',
          },
        ],
      });
      expect(j.journeyType, JourneyType.theme);
      expect(j.themeWord, 'waiting on God');
      expect(j.status, JourneyStatus.held);
    });
  });

  group('Journey.fromJson — error paths', () {
    test('unknown journeyType throws', () {
      expect(
        () => Journey.fromJson({
          'journeyId': 'x',
          'journeyType': 'devotional',
          'lane': 'adult',
          'status': 'ready',
          'stories': [
            {'storyNumber': 1, 'scriptureAnchorId': 'a', 'label': 'l'},
          ],
        }),
        throwsStateError,
      );
    });

    test('unknown lane throws', () {
      expect(
        () => Journey.fromJson({
          'journeyId': 'x',
          'journeyType': 'narrative',
          'lane': 'family',
          'status': 'ready',
          'stories': [
            {'storyNumber': 1, 'scriptureAnchorId': 'a', 'label': 'l'},
          ],
        }),
        throwsStateError,
      );
    });

    test('unknown status throws', () {
      expect(
        () => Journey.fromJson({
          'journeyId': 'x',
          'journeyType': 'narrative',
          'lane': 'adult',
          'status': 'pending',
          'stories': [
            {'storyNumber': 1, 'scriptureAnchorId': 'a', 'label': 'l'},
          ],
        }),
        throwsStateError,
      );
    });

    test('missing journeyId throws', () {
      expect(
        () => Journey.fromJson({
          'journeyType': 'narrative',
          'lane': 'adult',
          'status': 'ready',
          'stories': [
            {'storyNumber': 1, 'scriptureAnchorId': 'a', 'label': 'l'},
          ],
        }),
        throwsStateError,
      );
    });

    test('empty stories[] throws', () {
      expect(
        () => Journey.fromJson({
          'journeyId': 'x',
          'journeyType': 'narrative',
          'lane': 'adult',
          'status': 'ready',
          'stories': [],
        }),
        throwsStateError,
      );
    });

    test('kid journey with theme type throws (doctrine)', () {
      expect(
        () => Journey.fromJson({
          'journeyId': 'kid_x',
          'journeyType': 'theme',
          'lane': 'kid',
          'status': 'ready',
          'stories': [
            {'productionId': 1, 'anchorId': 'a', 'label': 'l'},
            {'productionId': 2, 'anchorId': 'b', 'label': 'l'},
            {'productionId': 3, 'anchorId': 'c', 'label': 'l'},
          ],
        }),
        throwsStateError,
      );
    });

    test('kid journey with teaching type throws (doctrine)', () {
      expect(
        () => Journey.fromJson({
          'journeyId': 'kid_x',
          'journeyType': 'teaching',
          'lane': 'kid',
          'status': 'ready',
          'stories': [
            {'productionId': 1, 'anchorId': 'a', 'label': 'l'},
            {'productionId': 2, 'anchorId': 'b', 'label': 'l'},
            {'productionId': 3, 'anchorId': 'c', 'label': 'l'},
          ],
        }),
        throwsStateError,
      );
    });

    test('kid journey with 2 stories throws (doctrine: min 3)', () {
      expect(
        () => Journey.fromJson({
          'journeyId': 'kid_x',
          'journeyType': 'narrative',
          'lane': 'kid',
          'status': 'ready',
          'stories': [
            {'productionId': 1, 'anchorId': 'a', 'label': 'l'},
            {'productionId': 2, 'anchorId': 'b', 'label': 'l'},
          ],
        }),
        throwsStateError,
      );
    });

    test('kid journey with 6 stories throws (doctrine: max 5)', () {
      expect(
        () => Journey.fromJson({
          'journeyId': 'kid_x',
          'journeyType': 'narrative',
          'lane': 'kid',
          'status': 'ready',
          'stories': List.generate(
              6,
              (i) => {
                    'productionId': i,
                    'anchorId': 'a$i',
                    'label': 'l',
                  }),
        }),
        throwsStateError,
      );
    });

    test('adult journey with 10 stories does NOT throw (no model cap)', () {
      // Sanity-only cap is in the SCHEMA TEST (≤7), not in the model
      // — the model trusts the validator + permits future doctrine
      // changes without a parser update.
      expect(
        () => Journey.fromJson({
          'journeyId': 'x',
          'journeyType': 'narrative',
          'lane': 'adult',
          'status': 'ready',
          'stories': List.generate(
              10,
              (i) => {
                    'storyNumber': i,
                    'scriptureAnchorId': 'a$i',
                    'label': 'l',
                  }),
        }),
        returnsNormally,
      );
    });
  });

  test('Journey.fromJsonString round-trip', () {
    final j = Journey.fromJsonString('''
{
  "journeyId": "x",
  "journeyType": "narrative",
  "lane": "adult",
  "status": "ready",
  "stories": [
    {"storyNumber": 1, "scriptureAnchorId": "a", "label": "l"}
  ]
}
''');
    expect(j.journeyId, 'x');
  });
}

Map<String, dynamic> _adultDanielJson() => {
      'journeyId': 'daniel_arc',
      'journeyType': 'narrative',
      'lane': 'adult',
      'status': 'ready',
      'nameRegistryKey': 'daniel_in_the_lions_den',
      'stories': [
        {
          'storyNumber': 1486,
          'scriptureAnchorId': 'daniel_1_8-21',
          'label': 'Daniel 1 — ten-day test',
        },
        {
          'storyNumber': 1002,
          'scriptureAnchorId': 'daniel_3_13-27',
          'label': 'Daniel 3 — fiery furnace',
        },
      ],
    };

Map<String, dynamic> _kidDavidJson() => {
      'journeyId': 'kid_david_arc',
      'journeyType': 'narrative',
      'lane': 'kid',
      'status': 'ready',
      'characterName': 'David',
      'stories': [
        {
          'productionId': 1836,
          'anchorId': 'david_shepherd',
          'label': '1 Samuel 16:11-13 — Shepherd boy',
        },
        {
          'productionId': 1801,
          'anchorId': 'david_goliath',
          'label': '1 Samuel 17 — Goliath',
        },
        {
          'productionId': 1908,
          'anchorId': 'david_king',
          'label': '2 Samuel 5 — King',
        },
      ],
    };
