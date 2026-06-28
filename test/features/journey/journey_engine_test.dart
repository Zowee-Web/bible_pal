import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/journey/journey.dart';
import 'package:bible_pal/features/journey/journey_engine.dart';
import 'package:bible_pal/features/journey/journey_registry.dart';
import 'package:bible_pal/features/pal_memory/pal_session.dart';

/// Tests for [JourneyEngine] — Slice 2 Phase 4.
///
/// Pure function. Every gate (cooldown / no-match / end-of-journey /
/// kid override / strict-newest) gets its own test. Determinism via
/// injected [now] + injected [lastJourneyContinuationSpokenAt].
void main() {
  const engine = JourneyEngine();

  final now = DateTime.utc(2026, 6, 28, 12, 0);
  final yesterday = now.subtract(const Duration(days: 1));
  final fourDaysAgo = now.subtract(const Duration(days: 4));

  JourneyRegistry buildRegistry({bool kidToo = true}) {
    final fixtures = <String>[
      _adultDanielJson,
      _adultLearningHeldJson, // held — should never be indexed
    ];
    if (kidToo) fixtures.add(_kidDavidJson);
    return JourneyRegistry.fromJsonStrings(fixtures);
  }

  PalSession adultSession(String storyNumber, DateTime when) => PalSession(
        storyId: 'story_${storyNumber}_brave_courage_full_traditional',
        completedAt: when,
        languageStyle: 'WEB',
      );

  PalSession kidSession(String anchor, DateTime when) => PalSession(
        storyId: 'kidstory_kid_${anchor}_full',
        completedAt: when,
        languageStyle: 'WEB',
      );

  group('happy paths', () {
    test('adult: newest Daniel session → offer next-in-journey', () {
      final offer = engine.nextOffer(
        sessions: [adultSession('1486', yesterday)],
        registry: buildRegistry(),
        lastJourneyContinuationSpokenAt: null,
        now: now,
        currentLane: JourneyLane.adult,
      );
      expect(offer, isNotNull);
      expect(offer!.journey.journeyId, 'daniel_arc');
      expect(offer.sourceStoryIndex, 0);
      expect(offer.nextStoryIndex, 1);
      expect(offer.nextStory.storyNumber, 1002,
          reason: 'next-in-journey after Daniel 1 (1486) is Daniel 3 (1002)');
    });

    test('kid: newest David session → offer next-in-journey', () {
      final offer = engine.nextOffer(
        sessions: [kidSession('david_shepherd', yesterday)],
        registry: buildRegistry(),
        lastJourneyContinuationSpokenAt: null,
        now: now,
        currentLane: JourneyLane.kid,
      );
      expect(offer, isNotNull);
      expect(offer!.journey.journeyId, 'kid_david_arc');
      expect(offer.nextStory.anchorId, 'david_goliath');
    });

    test('multiple sessions — picks NEWEST that lives in a journey', () {
      // Older session (1002, Daniel 3) is in Daniel arc;
      // newer session (1486, Daniel 1) is ALSO in Daniel arc.
      // Engine should pick the newer one → offer Daniel 3.
      final offer = engine.nextOffer(
        sessions: [
          adultSession('1002', fourDaysAgo),
          adultSession('1486', yesterday),
        ],
        registry: buildRegistry(),
        lastJourneyContinuationSpokenAt: null,
        now: now,
        currentLane: JourneyLane.adult,
      );
      expect(offer!.sourceSession.storyId, contains('story_1486_'));
      expect(offer.nextStory.storyNumber, 1002);
    });
  });

  group('cooldown gate', () {
    test('adult: lastSpokenAt 2 days ago → silent', () {
      final offer = engine.nextOffer(
        sessions: [adultSession('1486', yesterday)],
        registry: buildRegistry(),
        lastJourneyContinuationSpokenAt:
            now.subtract(const Duration(days: 2)),
        now: now,
        currentLane: JourneyLane.adult,
      );
      expect(offer, isNull, reason: 'cooldown 3d; 2d ago is still hot');
    });

    test('adult: lastSpokenAt exactly 3 days ago → fires (cooldown is <)', () {
      final offer = engine.nextOffer(
        sessions: [adultSession('1486', yesterday)],
        registry: buildRegistry(),
        lastJourneyContinuationSpokenAt:
            now.subtract(const Duration(days: 3)),
        now: now,
        currentLane: JourneyLane.adult,
      );
      expect(offer, isNotNull,
          reason: 'difference < 3d blocks; difference == 3d allows');
    });

    test('adult: lastSpokenAt 4 days ago → fires', () {
      final offer = engine.nextOffer(
        sessions: [adultSession('1486', yesterday)],
        registry: buildRegistry(),
        lastJourneyContinuationSpokenAt: fourDaysAgo,
        now: now,
        currentLane: JourneyLane.adult,
      );
      expect(offer, isNotNull);
    });

    test('kid: lastSpokenAt 1 hour ago → STILL fires (no kid cooldown)', () {
      final offer = engine.nextOffer(
        sessions: [kidSession('david_shepherd', yesterday)],
        registry: buildRegistry(),
        lastJourneyContinuationSpokenAt:
            now.subtract(const Duration(hours: 1)),
        now: now,
        currentLane: JourneyLane.kid,
      );
      expect(offer, isNotNull,
          reason: 'kid lane overrides adult cooldown per doctrine rule 3');
    });
  });

  group('silence gates', () {
    test('no sessions → silent', () {
      final offer = engine.nextOffer(
        sessions: [],
        registry: buildRegistry(),
        lastJourneyContinuationSpokenAt: null,
        now: now,
        currentLane: JourneyLane.adult,
      );
      expect(offer, isNull);
    });

    test('session story not in any ready journey → silent', () {
      // story_9999 is registered nowhere.
      final offer = engine.nextOffer(
        sessions: [adultSession('9999', yesterday)],
        registry: buildRegistry(),
        lastJourneyContinuationSpokenAt: null,
        now: now,
        currentLane: JourneyLane.adult,
      );
      expect(offer, isNull);
    });

    test('session is at END of journey → silent (strict-newest)', () {
      // 1002 is the LAST story in our fixture daniel_arc (2 stories).
      final offer = engine.nextOffer(
        sessions: [adultSession('1002', yesterday)],
        registry: buildRegistry(),
        lastJourneyContinuationSpokenAt: null,
        now: now,
        currentLane: JourneyLane.adult,
      );
      expect(offer, isNull,
          reason: 'end-of-journey is silent per Slice 2; Slice 5 will graduate');
    });

    test(
        'strict-newest: newest is at end-of-journey, older has continuation → still silent',
        () {
      // Older session (Daniel 1) has a continuation, but the newer
      // session (Daniel 3 = end) does NOT. Engine must NOT walk back.
      final offer = engine.nextOffer(
        sessions: [
          adultSession('1486', fourDaysAgo),
          adultSession('1002', yesterday),
        ],
        registry: buildRegistry(),
        lastJourneyContinuationSpokenAt: null,
        now: now,
        currentLane: JourneyLane.adult,
      );
      expect(offer, isNull,
          reason: "doctrine: 'user's last completed story is in that journey' "
              "— if the LAST one is at end-of-journey, PAL stays silent");
    });

    test('session in HELD journey → silent (held journeys are not indexed)', () {
      // 1121 (Hannah) is in HELD learning_to_wait fixture — must not
      // resolve to any journey.
      final offer = engine.nextOffer(
        sessions: [adultSession('1121', yesterday)],
        registry: buildRegistry(),
        lastJourneyContinuationSpokenAt: null,
        now: now,
        currentLane: JourneyLane.adult,
      );
      expect(offer, isNull);
    });

    test('adult-mode user with only kid sessions → silent', () {
      final offer = engine.nextOffer(
        sessions: [kidSession('david_shepherd', yesterday)],
        registry: buildRegistry(),
        lastJourneyContinuationSpokenAt: null,
        now: now,
        currentLane: JourneyLane.adult,
      );
      expect(offer, isNull,
          reason: 'lane filter: kid sessions never match adult lookups');
    });

    test('kid-mode user with only adult sessions → silent', () {
      final offer = engine.nextOffer(
        sessions: [adultSession('1486', yesterday)],
        registry: buildRegistry(),
        lastJourneyContinuationSpokenAt: null,
        now: now,
        currentLane: JourneyLane.kid,
      );
      expect(offer, isNull);
    });

    test('malformed session sid (no parse) → silent, not crash', () {
      final offer = engine.nextOffer(
        sessions: [
          PalSession(
            storyId: 'totally_unparseable_garbage',
            completedAt: yesterday,
            languageStyle: 'WEB',
          ),
        ],
        registry: buildRegistry(),
        lastJourneyContinuationSpokenAt: null,
        now: now,
        currentLane: JourneyLane.adult,
      );
      expect(offer, isNull);
    });
  });

  group('determinism', () {
    test('same inputs → same offer, byte for byte', () {
      final sessions = [adultSession('1486', yesterday)];
      final registry = buildRegistry();
      final a = engine.nextOffer(
        sessions: sessions,
        registry: registry,
        lastJourneyContinuationSpokenAt: null,
        now: now,
        currentLane: JourneyLane.adult,
      );
      final b = engine.nextOffer(
        sessions: sessions,
        registry: registry,
        lastJourneyContinuationSpokenAt: null,
        now: now,
        currentLane: JourneyLane.adult,
      );
      expect(a!.journey.journeyId, b!.journey.journeyId);
      expect(a.nextStory.storyNumber, b.nextStory.storyNumber);
      expect(a.sourceStoryIndex, b.sourceStoryIndex);
    });
  });
}

// ---------------------------------------------------------------------------
// Fixture journeys — minimal shapes so we can test gate behavior
// without depending on the live asset files.
//
// daniel_arc: 2 stories (1486 → 1002). Choosing 2 instead of full 4
// lets us cleanly test "newest is end-of-journey" with 1002.
// kid_david_arc: 3 stories (must be ≥3 per kid doctrine).
// learning_to_wait: 2 stories, HELD — used to test the held-not-indexed
// invariant.
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

const String _adultLearningHeldJson = '''
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
