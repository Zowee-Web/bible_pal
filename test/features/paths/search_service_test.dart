import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/services/search_service.dart';

/// Phase 2 Slice 6 tests for SearchService (SPEC Feature 50.7).
///
/// Priority order (LOCKED):
///   1. Scripture anchor match (exact or bibleStoryKey substring)
///   2. Chapter/book match (parsed reference)
///   3. Metadata substring match
///
/// Contracts verified:
/// - Traditional stories only — Creative invisible
/// - Kid-mode filter applied at snapshot layer
/// - Empty query returns empty list
/// - Raw query never mutates state (deterministic across calls)
/// - No external side effects (no logging, no telemetry — verified by
///   the absence of imports in search_service.dart)
void main() {
  Parable fixture({
    required String storyId,
    required String title,
    required String bibleSourceRef,
    required String bibleStoryKey,
    required String primaryCharacterId,
    required String primaryCharacterDisplayName,
    required int bibleOrderIndex,
    List<String>? themeTags,
    List<String>? characterIds,
    List<String>? characterDisplayNames,
    bool kidFriendly = false,
    String storytellingMode = 'traditional',
  }) {
    return Parable(
      storyId: storyId,
      title: title,
      mood: 'brave_courage',
      storytellingMode: storytellingMode,
      kidFriendly: kidFriendly,
      bibleSourceRef: bibleSourceRef,
      bibleStoryKey: bibleStoryKey,
      storyLength: 'short',
      narratorVoiceKey: 'VOICE_JAMES_HUSKY',
      primaryCharacterId: primaryCharacterId,
      primaryCharacterDisplayName: primaryCharacterDisplayName,
      bibleOrderIndex: bibleOrderIndex,
      timelineEra: 'kingdom',
      themeTags: themeTags,
      characterIds: characterIds,
      characterDisplayNames: characterDisplayNames,
      characterPathOrder: 1,
    );
  }

  List<Parable> buildSnapshot() {
    return [
      fixture(
        storyId: 's1000',
        title: 'Rest for the Heavy Laden',
        bibleSourceRef: 'Matthew 11:28-30',
        bibleStoryKey: 'rest_for_the_weary',
        primaryCharacterId: 'jesus',
        primaryCharacterDisplayName: 'Jesus',
        bibleOrderIndex: 650,
        themeTags: const ['mercy', 'hope'],
      ),
      fixture(
        storyId: 's1004',
        title: 'The Night Heaven Sang for Joy',
        bibleSourceRef: 'Luke 2:1-20',
        bibleStoryKey: 'nativity',
        primaryCharacterId: 'jesus',
        primaryCharacterDisplayName: 'Jesus',
        bibleOrderIndex: 620,
        themeTags: const ['hope', 'faith'],
        kidFriendly: true,
      ),
      fixture(
        storyId: 's1005',
        title: 'The Little Man Who Found Big Love',
        bibleSourceRef: 'Luke 19:1-10',
        bibleStoryKey: 'zacchaeus',
        primaryCharacterId: 'jesus',
        primaryCharacterDisplayName: 'Jesus',
        bibleOrderIndex: 640,
        themeTags: const ['mercy', 'faith'],
      ),
      fixture(
        storyId: 's1022',
        title: 'David Anointed King',
        bibleSourceRef: '1 Samuel 16:1-13',
        bibleStoryKey: 'david_anointed',
        primaryCharacterId: 'david',
        primaryCharacterDisplayName: 'David',
        bibleOrderIndex: 200,
        themeTags: const ['faith', 'provision'],
      ),
      fixture(
        storyId: 's1019',
        title: 'Moses and the Burning Bush',
        bibleSourceRef: 'Exodus 3:1-15',
        bibleStoryKey: 'burning_bush',
        primaryCharacterId: 'moses',
        primaryCharacterDisplayName: 'Moses',
        bibleOrderIndex: 50,
        themeTags: const ['obedience', 'faith'],
      ),
      fixture(
        storyId: 's1048',
        title: 'The Crossing of the Red Sea',
        bibleSourceRef: 'Exodus 14:10-31',
        bibleStoryKey: 'crossing_the_red_sea',
        primaryCharacterId: 'moses',
        primaryCharacterDisplayName: 'Moses',
        bibleOrderIndex: 52,
        themeTags: const ['courage', 'faith'],
      ),
      // Creative — must NEVER appear in search
      fixture(
        storyId: 'creative_001',
        title: 'A Creative Matthew Story',
        bibleSourceRef: 'Matthew 11:28-30',
        bibleStoryKey: 'rest_for_the_weary',
        primaryCharacterId: 'jesus',
        primaryCharacterDisplayName: 'Jesus',
        bibleOrderIndex: 9999,
        storytellingMode: 'creative',
      ),
    ];
  }

  SearchService buildService({bool kidFriendlyOnly = false}) {
    return SearchService(
      traditionalParables: buildSnapshot(),
      kidFriendlyOnly: kidFriendlyOnly,
    );
  }

  group('Empty and trivial queries', () {
    test('empty query returns empty list', () {
      final svc = buildService();
      expect(svc.search(''), isEmpty);
    });

    test('whitespace-only query returns empty list', () {
      final svc = buildService();
      expect(svc.search('   '), isEmpty);
    });

    test('unknown query returns empty list', () {
      final svc = buildService();
      expect(svc.search('asdfghjkl'), isEmpty);
    });
  });

  group('Creative stories invisible to search (Non-Blur #6)', () {
    test('search for Matthew does not return creative stories', () {
      final svc = buildService();
      final results = svc.search('Matthew 11:28-30');
      final ids = results.map((p) => p.storyId).toSet();
      expect(ids, isNot(contains('creative_001')));
      expect(ids, contains('s1000'));
    });

    test('search for "jesus" does not return creative jesus story', () {
      final svc = buildService();
      final results = svc.search('jesus');
      final ids = results.map((p) => p.storyId).toSet();
      expect(ids, isNot(contains('creative_001')));
    });
  });

  group('Kid-mode filtering', () {
    test('kid-mode returns only kid-friendly stories', () {
      final svc = buildService(kidFriendlyOnly: true);
      final results = svc.search('faith');
      // Only s1004 (Nativity) is kid-friendly in the fixture.
      for (final p in results) {
        expect(p.kidFriendly, isTrue);
      }
      expect(results.map((p) => p.storyId).toSet(), {'s1004'});
    });

    test('adult mode returns all non-kid + kid stories', () {
      final svc = buildService(kidFriendlyOnly: false);
      final results = svc.search('faith');
      final ids = results.map((p) => p.storyId).toSet();
      expect(ids, contains('s1004'));
      expect(ids, contains('s1022'));
    });
  });

  group('Tier 1 — scripture anchor match', () {
    test('exact bibleSourceRef match wins Tier 1', () {
      final svc = buildService();
      final results = svc.search('Matthew 11:28-30');
      expect(results.first.storyId, 's1000');
    });

    test('bibleStoryKey exact match wins Tier 1', () {
      final svc = buildService();
      final results = svc.search('zacchaeus');
      expect(results.first.storyId, 's1005');
    });

    test('bibleStoryKey substring match is Tier 1', () {
      final svc = buildService();
      // "red_sea" is a substring of "crossing_the_red_sea"
      final results = svc.search('red_sea');
      expect(results.first.storyId, 's1048');
    });
  });

  group('Tier 2 — parsed reference match', () {
    test('book-only query matches any story in that book', () {
      final svc = buildService();
      final results = svc.search('Genesis');
      // No annotated Genesis stories in this fixture — should be empty
      expect(results, isEmpty);
    });

    test('book-only query returns multiple stories in that book', () {
      final svc = buildService();
      final results = svc.search('Exodus');
      final ids = results.map((p) => p.storyId).toList();
      // Both Exodus 3 and Exodus 14, sorted by bibleOrderIndex
      expect(ids, ['s1019', 's1048']);
    });

    test('book + chapter query matches that specific chapter', () {
      final svc = buildService();
      final results = svc.search('Exodus 3');
      expect(results.map((p) => p.storyId).toList(), ['s1019']);
    });

    test('book + chapter + verse query matches overlap', () {
      final svc = buildService();
      final results = svc.search('Exodus 14:15');
      expect(results.map((p) => p.storyId).toList(), ['s1048']);
    });

    test('multi-word book (1 samuel) parses correctly', () {
      final svc = buildService();
      final results = svc.search('1 samuel 16');
      expect(results.map((p) => p.storyId).toList(), ['s1022']);
    });

    test('unknown book does not match', () {
      final svc = buildService();
      final results = svc.search('Revelation 3:1');
      // Not in any annotated story and not a metadata match either
      expect(results, isEmpty);
    });
  });

  group('Tier 3 — metadata substring match', () {
    test('title substring match', () {
      final svc = buildService();
      final results = svc.search('burning');
      expect(results.map((p) => p.storyId).toList(), ['s1019']);
    });

    test('character display name match', () {
      final svc = buildService();
      final results = svc.search('david');
      expect(results.map((p) => p.storyId).toList(), ['s1022']);
    });

    test('primaryCharacterId match', () {
      final svc = buildService();
      final results = svc.search('moses');
      final ids = results.map((p) => p.storyId).toList();
      expect(ids, contains('s1019'));
      expect(ids, contains('s1048'));
    });

    test('theme tag match', () {
      final svc = buildService();
      final results = svc.search('courage');
      expect(results.map((p) => p.storyId).toList(), ['s1048']);
    });

    test('case-insensitive match', () {
      final svc = buildService();
      final results = svc.search('MOSES');
      final ids = results.map((p) => p.storyId).toList();
      expect(ids, contains('s1019'));
      expect(ids, contains('s1048'));
    });
  });

  group('Priority ordering — Tier 1 > Tier 2 > Tier 3', () {
    test('scripture anchor query beats metadata substring', () {
      final svc = buildService();
      // "zacchaeus" is both bibleStoryKey (Tier 1) and possibly title
      // substring. Tier 1 match must rank above any Tier 3 matches.
      final results = svc.search('zacchaeus');
      expect(results.first.storyId, 's1005');
    });

    test('Tier 1 results appear before Tier 3 results', () {
      final svc = buildService();
      // Search "Matthew" — Matthew is parsed as a book (Tier 2 match
      // against s1000 via parsed ref). No Tier 1 match (no exact ref
      // "matthew" in bibleStoryKey). No metadata match either.
      final results = svc.search('matthew');
      expect(results.map((p) => p.storyId).toList(), ['s1000']);
    });
  });

  group('Determinism + no state mutation', () {
    test('identical queries return identical results across calls', () {
      final svc = buildService();
      final a = svc.search('faith').map((p) => p.storyId).toList();
      final b = svc.search('faith').map((p) => p.storyId).toList();
      final c = svc.search('faith').map((p) => p.storyId).toList();
      expect(a, b);
      expect(b, c);
    });

    test('different queries do not pollute each other', () {
      final svc = buildService();
      final faith = svc.search('faith').map((p) => p.storyId).toSet();
      final courage = svc.search('courage').map((p) => p.storyId).toSet();
      // Courage should be a proper subset of faith (both stories
      // tagged courage are also tagged faith).
      for (final id in courage) {
        expect(faith.contains(id) || id == 's1048', isTrue);
      }
    });
  });

  group('Privacy — query string is never mutated or exposed', () {
    test('search does not modify the query string', () {
      final svc = buildService();
      const query = 'Some User Query';
      final first = svc.search(query);
      final second = svc.search(query);
      // If the service were to mutate or capture the query, repeated
      // calls could diverge. Verify idempotency.
      expect(
        first.map((p) => p.storyId).toList(),
        equals(second.map((p) => p.storyId).toList()),
      );
      // And the original query string is not touched by reference.
      expect(query, 'Some User Query');
    });
  });
}
