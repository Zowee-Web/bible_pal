import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/features/paths/path_type.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/services/path_service.dart';

/// Phase 3 Slice 2 tests for PathService.getResumePoint (SPEC Feature 50.6b).
///
/// The resume heuristic is the ONE path-related affordance that filters
/// by completion state. Contracts verified:
///
/// - Empty path → returns null
/// - Zero completed → returns first story (Phase 3 UI hides the CYJ
///   affordance in this case, but the service must always produce a
///   deterministic result for any caller)
/// - Partial completion → returns the first uncompleted story in
///   canonical path order
/// - All completed → returns the first story for replay from the
///   beginning
/// - Kid-mode filter applied at snapshot layer (adult-only stories
///   never surface as a resume point for kid-mode users)
/// - Completing a story that is NOT in the path does not affect the
///   resume point
void main() {
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
  }) {
    return Parable(
      storyId: storyId,
      title: title,
      mood: 'brave_courage',
      storytellingMode: 'traditional',
      kidFriendly: kidFriendly,
      bibleSourceRef: bibleSourceRef,
      bibleStoryKey: '${storyId}_key',
      storyLength: 'short',
      narratorVoiceKey: 'VOICE_JAMES_HUSKY',
      primaryCharacterId: primaryCharacterId,
      primaryCharacterDisplayName: primaryCharacterId,
      bibleOrderIndex: bibleOrderIndex,
      timelineEra: timelineEra,
      themeTags: themeTags,
      characterPathOrder: characterPathOrder,
    );
  }

  /// Moses path with 2 stories (Burning Bush pos 0 → Red Sea pos 1)
  List<Parable> mosesSnapshot() {
    return [
      fixture(
        storyId: 's1019',
        title: 'Burning Bush',
        bibleSourceRef: 'Exodus 3:1-15',
        primaryCharacterId: 'moses',
        timelineEra: 'exodus',
        themeTags: const ['obedience', 'faith'],
        bibleOrderIndex: 50,
        characterPathOrder: 1,
      ),
      fixture(
        storyId: 's1048',
        title: 'Red Sea',
        bibleSourceRef: 'Exodus 14:10-31',
        primaryCharacterId: 'moses',
        timelineEra: 'exodus',
        themeTags: const ['courage', 'faith'],
        bibleOrderIndex: 52,
        characterPathOrder: 2,
      ),
    ];
  }

  PathService buildService({
    Set<String> completedStoryIds = const <String>{},
    bool kidFriendlyOnly = false,
  }) {
    return PathService(
      traditionalParables: mosesSnapshot(),
      jesusLifeSequence: const <String>[],
      kidFriendlyOnly: kidFriendlyOnly,
      completedStoryIds: completedStoryIds,
    );
  }

  group('Empty path edge case', () {
    test('empty path returns null', () {
      final svc = PathService(
        traditionalParables: const <Parable>[],
        jesusLifeSequence: const <String>[],
        kidFriendlyOnly: false,
      );
      expect(svc.getResumePoint(PathType.characters, 'moses'), isNull);
      expect(svc.getResumePoint(PathType.jesusLife, 'default'), isNull);
    });

    test('unknown pathId returns null', () {
      final svc = buildService();
      expect(svc.getResumePoint(PathType.characters, 'nobody'), isNull);
      expect(svc.getResumePoint(PathType.timeline, 'unknown_era'), isNull);
    });
  });

  group('Zero completed (fresh user)', () {
    test('returns the first story in canonical path order', () {
      final svc = buildService(completedStoryIds: const <String>{});
      final resume = svc.getResumePoint(PathType.characters, 'moses');
      expect(resume?.storyId, 's1019');
    });

    test('works for every path type with zero completions', () {
      final svc = buildService();
      expect(
        svc.getResumePoint(PathType.timeline, 'exodus')?.storyId,
        's1019',
      );
      expect(
        svc.getResumePoint(PathType.themes, 'faith')?.storyId,
        's1019',
      );
    });
  });

  group('Partial completion — first uncompleted wins', () {
    test('first story completed → resume on second', () {
      final svc = buildService(completedStoryIds: const {'s1019'});
      final resume = svc.getResumePoint(PathType.characters, 'moses');
      expect(resume?.storyId, 's1048');
    });

    test('only last story completed → resume on first (first uncompleted)',
        () {
      // Unusual but possible if the user jumps ahead.
      final svc = buildService(completedStoryIds: const {'s1048'});
      final resume = svc.getResumePoint(PathType.characters, 'moses');
      expect(resume?.storyId, 's1019');
    });

    test('middle of larger path completed → first uncompleted in order',
        () {
      // Build a 4-story timeline path: order 1-2-3-4.
      final parables = [
        fixture(
          storyId: 'a',
          title: 'A',
          bibleSourceRef: 'Exodus 1:1',
          primaryCharacterId: 'moses',
          timelineEra: 'exodus',
          themeTags: const ['faith'],
          bibleOrderIndex: 40,
          characterPathOrder: 1,
        ),
        fixture(
          storyId: 'b',
          title: 'B',
          bibleSourceRef: 'Exodus 2:1',
          primaryCharacterId: 'moses',
          timelineEra: 'exodus',
          themeTags: const ['faith'],
          bibleOrderIndex: 45,
          characterPathOrder: 2,
        ),
        fixture(
          storyId: 'c',
          title: 'C',
          bibleSourceRef: 'Exodus 3:1',
          primaryCharacterId: 'moses',
          timelineEra: 'exodus',
          themeTags: const ['faith'],
          bibleOrderIndex: 50,
          characterPathOrder: 3,
        ),
        fixture(
          storyId: 'd',
          title: 'D',
          bibleSourceRef: 'Exodus 14:1',
          primaryCharacterId: 'moses',
          timelineEra: 'exodus',
          themeTags: const ['faith'],
          bibleOrderIndex: 52,
          characterPathOrder: 4,
        ),
      ];
      final svc = PathService(
        traditionalParables: parables,
        jesusLifeSequence: const <String>[],
        kidFriendlyOnly: false,
        completedStoryIds: const {'a', 'b'}, // first 2 complete
      );
      // Timeline path order = bibleOrderIndex asc → a, b, c, d
      expect(
        svc.getResumePoint(PathType.timeline, 'exodus')?.storyId,
        'c',
      );
    });
  });

  group('All completed — replay mode', () {
    test('returns the first story when every entry is completed', () {
      final svc = buildService(
        completedStoryIds: const {'s1019', 's1048'},
      );
      final resume = svc.getResumePoint(PathType.characters, 'moses');
      expect(resume?.storyId, 's1019');
    });

    test('replay works across path types', () {
      final svc = buildService(
        completedStoryIds: const {'s1019', 's1048'},
      );
      expect(
        svc.getResumePoint(PathType.timeline, 'exodus')?.storyId,
        's1019',
      );
      expect(
        svc.getResumePoint(PathType.themes, 'faith')?.storyId,
        's1019',
      );
    });
  });

  group('Kid-mode filter honored at snapshot layer', () {
    test('kid mode excludes adult-only stories from resume candidates', () {
      // Burning Bush = adult, Red Sea = kid-friendly
      final parables = [
        fixture(
          storyId: 's1019',
          title: 'Burning Bush',
          bibleSourceRef: 'Exodus 3:1-15',
          primaryCharacterId: 'moses',
          timelineEra: 'exodus',
          themeTags: const ['faith'],
          bibleOrderIndex: 50,
          characterPathOrder: 1,
          kidFriendly: false,
        ),
        fixture(
          storyId: 's1048',
          title: 'Red Sea (kid)',
          bibleSourceRef: 'Exodus 14:10-31',
          primaryCharacterId: 'moses',
          timelineEra: 'exodus',
          themeTags: const ['faith'],
          bibleOrderIndex: 52,
          characterPathOrder: 2,
          kidFriendly: true,
        ),
      ];
      final svc = PathService(
        traditionalParables: parables,
        jesusLifeSequence: const <String>[],
        kidFriendlyOnly: true,
        completedStoryIds: const <String>{},
      );
      // Kid-mode user only sees Red Sea → resume on it even though it's
      // canonically the second story in the adult path.
      final resume = svc.getResumePoint(PathType.characters, 'moses');
      expect(resume?.storyId, 's1048');
    });
  });

  group('Out-of-path completions do not affect resume', () {
    test('completing a story not in the path is ignored', () {
      final svc = buildService(
        completedStoryIds: const {'some_other_story_id'},
      );
      // Moses path still starts fresh.
      expect(
        svc.getResumePoint(PathType.characters, 'moses')?.storyId,
        's1019',
      );
    });
  });
}
