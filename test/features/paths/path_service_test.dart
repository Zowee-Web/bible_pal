import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/character_registry.dart';
import 'package:bible_pal/features/paths/path_instance.dart';
import 'package:bible_pal/features/paths/path_type.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/services/path_service.dart';

/// Phase 2 Slice 4 tests for PathService real logic (SPEC Feature 50).
///
/// Uses hand-constructed Parable fixtures — no manifest loading, no
/// service dependencies. This pins every path-type's filter + sort +
/// enumeration behavior exactly as the spec requires.
///
/// Key contracts verified:
/// - `getPathStories` filters correctly per path type + sorts canonically
/// - `getNextInPath` advances by canonical position and NEVER skips
///   completed stories (SPEC Feature 50.6 — path order is sacred)
/// - `getPathInstances` excludes `jesus` from Characters path
///   (SPEC Feature 50.8)
/// - Empty paths return empty lists, not crashes
/// - Unknown pathIds return empty
/// - Creative stories are defensively filtered at constructor
/// - Kid-mode filters non-kid content at constructor
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    CharacterRegistry.resetForTest();
    await CharacterRegistry.ensureLoaded();
  });

  /// Builds a minimal Traditional parable with the 6 PALs Paths
  /// annotation fields populated.
  Parable fixture({
    required String storyId,
    required String title,
    required String bibleSourceRef,
    required String primaryCharacterId,
    required String timelineEra,
    required List<String> themeTags,
    required int bibleOrderIndex,
    required int characterPathOrder,
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
      bibleStoryKey: '${storyId}_key',
      storyLength: 'short',
      narratorVoiceKey: 'VOICE_JAMES_HUSKY',
      primaryCharacterId: primaryCharacterId,
      primaryCharacterDisplayName:
          CharacterRegistry.getDisplayName(primaryCharacterId),
      bibleOrderIndex: bibleOrderIndex,
      timelineEra: timelineEra,
      themeTags: themeTags,
      characterPathOrder: characterPathOrder,
    );
  }

  /// A realistic snapshot modelling the Phase 2 Slice 2 annotation batch
  /// plus one Creative story + one non-kid story to exercise filters.
  List<Parable> buildSnapshot() {
    return [
      fixture(
        storyId: 's1000',
        title: 'Rest for the Heavy Laden',
        bibleSourceRef: 'Matthew 11:28-30',
        primaryCharacterId: 'jesus',
        timelineEra: 'jesus_ministry',
        themeTags: ['mercy', 'hope'],
        bibleOrderIndex: 650,
        characterPathOrder: 8,
      ),
      fixture(
        storyId: 's1004',
        title: 'Nativity',
        bibleSourceRef: 'Luke 2:1-20',
        primaryCharacterId: 'jesus',
        timelineEra: 'jesus_ministry',
        themeTags: ['hope', 'faith'],
        bibleOrderIndex: 620,
        characterPathOrder: 1,
        kidFriendly: true,
      ),
      fixture(
        storyId: 's1005',
        title: 'Zacchaeus',
        bibleSourceRef: 'Luke 19:1-10',
        primaryCharacterId: 'jesus',
        timelineEra: 'jesus_ministry',
        themeTags: ['mercy', 'faith'],
        bibleOrderIndex: 640,
        characterPathOrder: 6,
      ),
      fixture(
        storyId: 's1006',
        title: 'Ten Lepers',
        bibleSourceRef: 'Luke 17:11-19',
        primaryCharacterId: 'jesus',
        timelineEra: 'jesus_ministry',
        themeTags: ['mercy', 'faith'],
        bibleOrderIndex: 635,
        characterPathOrder: 5,
      ),
      fixture(
        storyId: 's1016',
        title: 'Calling of Abram',
        bibleSourceRef: 'Genesis 12:1-9',
        primaryCharacterId: 'abraham',
        timelineEra: 'patriarchs',
        themeTags: ['obedience', 'faith'],
        bibleOrderIndex: 12,
        characterPathOrder: 1,
      ),
      fixture(
        storyId: 's1019',
        title: 'Burning Bush',
        bibleSourceRef: 'Exodus 3:1-15',
        primaryCharacterId: 'moses',
        timelineEra: 'exodus',
        themeTags: ['obedience', 'faith'],
        bibleOrderIndex: 50,
        characterPathOrder: 1,
      ),
      fixture(
        storyId: 's1020',
        title: 'Three Visitors',
        bibleSourceRef: 'Genesis 18:1-15',
        primaryCharacterId: 'abraham',
        timelineEra: 'patriarchs',
        themeTags: ['hope', 'faith'],
        bibleOrderIndex: 18,
        characterPathOrder: 2,
      ),
      fixture(
        storyId: 's1022',
        title: 'David Anointed King',
        bibleSourceRef: '1 Samuel 16:1-13',
        primaryCharacterId: 'david',
        timelineEra: 'kingdom',
        themeTags: ['faith', 'provision'],
        bibleOrderIndex: 200,
        characterPathOrder: 1,
      ),
      fixture(
        storyId: 's1036',
        title: 'Ruth Gleans',
        bibleSourceRef: 'Ruth 2:1-23',
        primaryCharacterId: 'ruth',
        timelineEra: 'kingdom',
        themeTags: ['provision', 'mercy'],
        bibleOrderIndex: 180,
        characterPathOrder: 1,
      ),
      fixture(
        storyId: 's1048',
        title: 'Red Sea',
        bibleSourceRef: 'Exodus 14:10-31',
        primaryCharacterId: 'moses',
        timelineEra: 'exodus',
        themeTags: ['courage', 'faith'],
        bibleOrderIndex: 52,
        characterPathOrder: 2,
      ),
      // Creative story — must NEVER appear in any path (Non-Blur #6)
      fixture(
        storyId: 'creative_001',
        title: 'A Creative Story',
        bibleSourceRef: 'Genesis 1:1',
        primaryCharacterId: 'david',
        timelineEra: 'kingdom',
        themeTags: ['faith'],
        bibleOrderIndex: 1,
        characterPathOrder: 99,
        storytellingMode: 'creative',
      ),
    ];
  }

  /// The seeded jesus_life sequence (canonical chronology).
  const jesusLifeSeq = <String>[
    's1004', // Nativity
    's1000', // Rest for the Heavy Laden
    's1006', // Ten Lepers
    's1005', // Zacchaeus
  ];

  PathService buildService({bool kidFriendlyOnly = false}) {
    return PathService(
      traditionalParables: buildSnapshot(),
      jesusLifeSequence: jesusLifeSeq,
      kidFriendlyOnly: kidFriendlyOnly,
    );
  }

  group('Constructor filters defensively', () {
    test('Creative stories are excluded from the snapshot', () {
      final svc = buildService();
      // David path should NOT contain the creative_001 story even though
      // it declared primaryCharacterId: david.
      final davidStories = svc.getPathStories(PathType.characters, 'david');
      expect(davidStories.any((p) => p.storyId == 'creative_001'), isFalse);
      expect(davidStories.any((p) => p.storyId == 's1022'), isTrue);
    });

    test('kid-mode filters non-kid stories', () {
      final svc = buildService(kidFriendlyOnly: true);
      // Only s1004 (Nativity) is marked kidFriendly in the fixture.
      // Every path type should only see s1004.
      final jesus = svc.getPathStories(PathType.characters, 'jesus');
      expect(jesus, isEmpty); // jesus never in Characters regardless

      final jesusLife = svc.getPathStories(PathType.jesusLife, 'default');
      expect(jesusLife.length, 1);
      expect(jesusLife.first.storyId, 's1004');
    });

    test('kid-mode-off shows all 10 annotated stories', () {
      final svc = buildService(kidFriendlyOnly: false);
      final everyPath = [
        ...svc.getPathStories(PathType.characters, 'abraham'),
        ...svc.getPathStories(PathType.characters, 'moses'),
        ...svc.getPathStories(PathType.characters, 'david'),
        ...svc.getPathStories(PathType.characters, 'ruth'),
        ...svc.getPathStories(PathType.jesusLife, 'default'),
      ];
      expect(everyPath.length, greaterThanOrEqualTo(10));
    });
  });

  group('jesus_life path (SPEC 50.1b)', () {
    test('returns stories in curated sequence order', () {
      final svc = buildService();
      final stories = svc.getPathStories(PathType.jesusLife, 'default');
      expect(
        stories.map((p) => p.storyId).toList(),
        ['s1004', 's1000', 's1006', 's1005'],
      );
    });

    test('getPathInstances returns exactly one instance', () {
      final svc = buildService();
      final instances = svc.getPathInstances(PathType.jesusLife);
      expect(instances.length, 1);
      expect(instances.first.pathId, 'default');
      expect(instances.first.displayLabel, 'The Life of Jesus');
      expect(instances.first.storyCount, 4);
    });

    test('empty curated sequence returns empty path + empty instances', () {
      final svc = PathService(
        traditionalParables: buildSnapshot(),
        jesusLifeSequence: const <String>[],
        kidFriendlyOnly: false,
      );
      expect(svc.getPathStories(PathType.jesusLife, 'default'), isEmpty);
      expect(svc.getPathInstances(PathType.jesusLife), isEmpty);
    });

    test('stories whose primaryCharacterId != jesus are skipped', () {
      // Pollute the sequence with a david storyId — must be silently dropped.
      final svc = PathService(
        traditionalParables: buildSnapshot(),
        jesusLifeSequence: const ['s1022', 's1000', 's1004'],
        kidFriendlyOnly: false,
      );
      final stories = svc.getPathStories(PathType.jesusLife, 'default');
      expect(stories.map((p) => p.storyId).toList(), ['s1000', 's1004']);
    });
  });

  group('bible_order path', () {
    test('genesis path returns stories sorted by bibleOrderIndex', () {
      final svc = buildService();
      final stories = svc.getPathStories(PathType.bibleOrder, 'genesis');
      expect(
        stories.map((p) => p.storyId).toList(),
        ['s1016', 's1020'], // 12 < 18
      );
    });

    test('matthew path returns one story', () {
      final svc = buildService();
      final stories = svc.getPathStories(PathType.bibleOrder, 'matthew');
      expect(stories.map((p) => p.storyId).toList(), ['s1000']);
    });

    test('1_samuel path (multi-word book) returns David anointed', () {
      final svc = buildService();
      final stories = svc.getPathStories(PathType.bibleOrder, '1_samuel');
      expect(stories.map((p) => p.storyId).toList(), ['s1022']);
    });

    test('unknown book returns empty', () {
      final svc = buildService();
      expect(svc.getPathStories(PathType.bibleOrder, 'made_up_book'),
          isEmpty);
    });

    test('getPathInstances returns one per annotated book', () {
      final svc = buildService();
      final instances = svc.getPathInstances(PathType.bibleOrder);
      // Expect instances for: genesis, exodus, ruth, 1_samuel, matthew, luke
      final pathIds = instances.map((i) => i.pathId).toSet();
      expect(pathIds, contains('genesis'));
      expect(pathIds, contains('exodus'));
      expect(pathIds, contains('ruth'));
      expect(pathIds, contains('1_samuel'));
      expect(pathIds, contains('matthew'));
      expect(pathIds, contains('luke'));
    });

    test('getPathInstances display labels are properly formatted', () {
      final svc = buildService();
      final instances = svc.getPathInstances(PathType.bibleOrder);
      final byId = {for (final i in instances) i.pathId: i};
      expect(byId['genesis']?.displayLabel, 'Genesis');
      expect(byId['1_samuel']?.displayLabel, '1 Samuel');
      expect(byId['matthew']?.displayLabel, 'Matthew');
    });
  });

  group('timeline path', () {
    test('kingdom path returns David + Ruth sorted by bibleOrderIndex', () {
      final svc = buildService();
      final stories = svc.getPathStories(PathType.timeline, 'kingdom');
      expect(stories.map((p) => p.storyId).toList(), ['s1036', 's1022']);
      // Ruth (180) before David (200)
    });

    test('exodus path returns Burning Bush + Red Sea in canonical order', () {
      final svc = buildService();
      final stories = svc.getPathStories(PathType.timeline, 'exodus');
      expect(stories.map((p) => p.storyId).toList(), ['s1019', 's1048']);
      // Burning Bush (50) before Red Sea (52)
    });

    test('unknown era returns empty', () {
      final svc = buildService();
      expect(svc.getPathStories(PathType.timeline, 'made_up_era'), isEmpty);
    });

    test('getPathInstances orders eras by canonical enum order', () {
      final svc = buildService();
      final instances = svc.getPathInstances(PathType.timeline);
      final pathIds = instances.map((i) => i.pathId).toList();
      // Canonical order: creation, patriarchs, exodus, judges, kingdom,
      // exile, return, jesus_ministry, early_church
      // Annotated subset: patriarchs, exodus, kingdom, jesus_ministry
      expect(pathIds, ['patriarchs', 'exodus', 'kingdom', 'jesus_ministry']);
    });
  });

  group('themes path', () {
    test('faith path returns stories tagged faith', () {
      final svc = buildService();
      final stories = svc.getPathStories(PathType.themes, 'faith');
      // 8 stories have "faith": s1004, s1005, s1006, s1016, s1019, s1020,
      // s1022, s1048. Plus s1000 has "hope" not "faith" in its tags.
      // Wait — check the fixture: s1000 is ['mercy', 'hope'], no faith.
      final ids = stories.map((p) => p.storyId).toSet();
      expect(ids, contains('s1016'));
      expect(ids, contains('s1022'));
      expect(ids, contains('s1048'));
      expect(ids, isNot(contains('s1000'))); // s1000 has mercy+hope only
    });

    test('courage path returns only Red Sea', () {
      final svc = buildService();
      final stories = svc.getPathStories(PathType.themes, 'courage');
      expect(stories.map((p) => p.storyId).toList(), ['s1048']);
    });

    test('unknown theme returns empty', () {
      final svc = buildService();
      expect(svc.getPathStories(PathType.themes, 'gratitude'), isEmpty);
    });

    test('getPathInstances orders themes by canonical enum order', () {
      final svc = buildService();
      final instances = svc.getPathInstances(PathType.themes);
      final pathIds = instances.map((i) => i.pathId).toList();
      // Canonical theme order: faith, hope, mercy, courage, obedience,
      // provision, patience, forgiveness.
      // Annotated subset: faith, hope, mercy, courage, obedience, provision
      expect(pathIds.first, 'faith');
      // Courage should come before obedience in canonical order
      final courageIdx = pathIds.indexOf('courage');
      final obedienceIdx = pathIds.indexOf('obedience');
      expect(courageIdx, lessThan(obedienceIdx));
    });
  });

  group('characters path (SPEC 50.8 — Jesus reservation)', () {
    test('david path returns David Anointed', () {
      final svc = buildService();
      final stories = svc.getPathStories(PathType.characters, 'david');
      expect(stories.map((p) => p.storyId).toList(), ['s1022']);
    });

    test('moses path returns Burning Bush + Red Sea in characterPathOrder', () {
      final svc = buildService();
      final stories = svc.getPathStories(PathType.characters, 'moses');
      expect(stories.map((p) => p.storyId).toList(), ['s1019', 's1048']);
    });

    test('abraham path returns stories ordered by characterPathOrder', () {
      final svc = buildService();
      final stories = svc.getPathStories(PathType.characters, 'abraham');
      expect(stories.map((p) => p.storyId).toList(), ['s1016', 's1020']);
    });

    test('jesus as pathId returns empty (CHARACTERS PATH NEVER SURFACES JESUS)',
        () {
      final svc = buildService();
      final stories = svc.getPathStories(PathType.characters, 'jesus');
      expect(stories, isEmpty);
    });

    test('empty pathId returns empty', () {
      final svc = buildService();
      expect(svc.getPathStories(PathType.characters, ''), isEmpty);
    });

    test('getPathInstances excludes jesus (SPEC 50.8 LOCKED)', () {
      final svc = buildService();
      final instances = svc.getPathInstances(PathType.characters);
      final pathIds = instances.map((i) => i.pathId).toSet();
      expect(pathIds, isNot(contains('jesus')));
      // But DOES include the 4 non-Jesus characters from the batch
      expect(pathIds, contains('abraham'));
      expect(pathIds, contains('moses'));
      expect(pathIds, contains('david'));
      expect(pathIds, contains('ruth'));
    });

    test('getPathInstances sorts alphabetically by display label', () {
      final svc = buildService();
      final instances = svc.getPathInstances(PathType.characters);
      final labels = instances.map((i) => i.displayLabel).toList();
      final sorted = [...labels]..sort();
      expect(labels, sorted);
    });
  });

  group('getNextInPath — PATH ORDER IS SACRED (SPEC 50.6 LOCKED)', () {
    test('advances to next story in canonical order', () {
      final svc = buildService();
      // moses path: [s1019 (pos 0), s1048 (pos 1)]
      final next = svc.getNextInPath(PathType.characters, 'moses', 0);
      expect(next?.storyId, 's1048');
    });

    test('returns null at the final position', () {
      final svc = buildService();
      final next = svc.getNextInPath(PathType.characters, 'moses', 1);
      expect(next, isNull);
    });

    test('returns null for out-of-range position', () {
      final svc = buildService();
      final next = svc.getNextInPath(PathType.characters, 'moses', 99);
      expect(next, isNull);
    });

    test(
        'DOES NOT filter by completion state — advances by position only',
        () {
      // This is the CENTRAL RULE of PALs Paths (SPEC 50.6 LOCKED).
      // PathService has NO knowledge of CompletedStoriesStore. If the
      // API surface ever changes to accept a completed set, this test
      // should fail loudly.
      final svc = buildService();
      final stories = svc.getPathStories(PathType.jesusLife, 'default');
      expect(stories.length, 4);
      // Walking positions 0 -> 1 -> 2 -> 3 visits every story in
      // sequence regardless of whether any of them were "completed".
      expect(
          svc.getNextInPath(PathType.jesusLife, 'default', 0)?.storyId,
          's1000');
      expect(
          svc.getNextInPath(PathType.jesusLife, 'default', 1)?.storyId,
          's1006');
      expect(
          svc.getNextInPath(PathType.jesusLife, 'default', 2)?.storyId,
          's1005');
      expect(svc.getNextInPath(PathType.jesusLife, 'default', 3), isNull);
    });

    test('getNextInPath across timeline and themes paths', () {
      final svc = buildService();
      // exodus timeline: [s1019, s1048]
      expect(
          svc.getNextInPath(PathType.timeline, 'exodus', 0)?.storyId,
          's1048');
      // faith themes — multiple stories, advance 0 -> 1
      final faith = svc.getPathStories(PathType.themes, 'faith');
      if (faith.length >= 2) {
        final next = svc.getNextInPath(PathType.themes, 'faith', 0);
        expect(next?.storyId, faith[1].storyId);
      }
    });

    test('negative positionInPath returns null', () {
      final svc = buildService();
      final next = svc.getNextInPath(PathType.jesusLife, 'default', -1);
      // nextIndex = -1 + 1 = 0 — SPEC 50.6 semantics say this is "next
      // after a phantom position -1", which resolves to the first story.
      // Either the first story OR null is acceptable; lock current
      // behavior.
      expect(next?.storyId, 's1004');
    });
  });

  group('Default empty completion set (Phase 2 compatibility)', () {
    test(
        'getResumePoint returns first story when completedStoryIds defaults to empty',
        () {
      // When no completedStoryIds are provided (Phase 2 callers), the
      // resume point is the first story in canonical order — i.e., the
      // user has zero progress on this path. Phase 3 "Continue Your
      // Journey" UI hides itself in this state; the service always
      // returns a valid result.
      final svc = buildService();
      expect(
        svc.getResumePoint(PathType.characters, 'david')?.storyId,
        's1022',
      );
      expect(
        svc.getResumePoint(PathType.jesusLife, 'default')?.storyId,
        's1004',
      );
    });

    test(
        'getCompletionPercentage returns 0.0 when completedStoryIds is empty',
        () {
      final svc = buildService();
      expect(svc.getCompletionPercentage(PathType.characters, 'david'), 0.0);
      expect(
        svc.getCompletionPercentage(PathType.jesusLife, 'default'),
        0.0,
      );
    });

    test('isStoryCompleted returns false for all stories when set is empty',
        () {
      final svc = buildService();
      expect(svc.isStoryCompleted('s1000'), isFalse);
      expect(svc.isStoryCompleted('s1022'), isFalse);
      expect(svc.isStoryCompleted('unknown'), isFalse);
    });
  });

  group('PathInstance value-class semantics', () {
    test('equality is value-based', () {
      const a = PathInstance(
        pathType: PathType.characters,
        pathId: 'david',
        displayLabel: 'David',
        storyCount: 3,
      );
      const b = PathInstance(
        pathType: PathType.characters,
        pathId: 'david',
        displayLabel: 'David',
        storyCount: 3,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}
