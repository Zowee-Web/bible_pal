import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/features/paths/path_type.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/services/path_service.dart';

/// Phase 3 Slice 2 tests for PathService.getCompletionPercentage
/// (SPEC Feature 50.5).
///
/// Contracts verified:
/// - Empty path → 0.0 (never NaN)
/// - 0 completed → 0.0
/// - Partial completion → exact ratio
/// - All completed → 1.0
/// - Kid-mode denominator: adult-only stories never count toward either
///   the numerator or the denominator for kid-mode users
/// - Out-of-path completions are ignored
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

  /// Moses path with 4 stories for precise fraction checks.
  List<Parable> mosesSnapshot({bool allKidFriendly = false}) {
    return [
      fixture(
        storyId: 'm1',
        title: 'M1',
        bibleSourceRef: 'Exodus 1:1',
        primaryCharacterId: 'moses',
        timelineEra: 'exodus',
        themeTags: const ['faith'],
        bibleOrderIndex: 40,
        characterPathOrder: 1,
        kidFriendly: allKidFriendly,
      ),
      fixture(
        storyId: 'm2',
        title: 'M2',
        bibleSourceRef: 'Exodus 2:1',
        primaryCharacterId: 'moses',
        timelineEra: 'exodus',
        themeTags: const ['faith'],
        bibleOrderIndex: 45,
        characterPathOrder: 2,
        kidFriendly: allKidFriendly,
      ),
      fixture(
        storyId: 'm3',
        title: 'M3',
        bibleSourceRef: 'Exodus 3:1',
        primaryCharacterId: 'moses',
        timelineEra: 'exodus',
        themeTags: const ['faith'],
        bibleOrderIndex: 50,
        characterPathOrder: 3,
        kidFriendly: allKidFriendly,
      ),
      fixture(
        storyId: 'm4',
        title: 'M4',
        bibleSourceRef: 'Exodus 14:1',
        primaryCharacterId: 'moses',
        timelineEra: 'exodus',
        themeTags: const ['faith'],
        bibleOrderIndex: 52,
        characterPathOrder: 4,
        kidFriendly: allKidFriendly,
      ),
    ];
  }

  PathService buildService({
    Set<String> completedStoryIds = const <String>{},
    bool kidFriendlyOnly = false,
    List<Parable>? parables,
  }) {
    return PathService(
      traditionalParables: parables ?? mosesSnapshot(),
      jesusLifeSequence: const <String>[],
      kidFriendlyOnly: kidFriendlyOnly,
      completedStoryIds: completedStoryIds,
    );
  }

  group('Basic fraction math', () {
    test('empty path → 0.0', () {
      final svc = PathService(
        traditionalParables: const <Parable>[],
        jesusLifeSequence: const <String>[],
        kidFriendlyOnly: false,
      );
      expect(svc.getCompletionPercentage(PathType.characters, 'moses'), 0.0);
    });

    test('unknown pathId → 0.0', () {
      final svc = buildService();
      expect(svc.getCompletionPercentage(PathType.characters, 'ghost'), 0.0);
    });

    test('zero completed → 0.0', () {
      final svc = buildService(completedStoryIds: const <String>{});
      expect(
        svc.getCompletionPercentage(PathType.characters, 'moses'),
        0.0,
      );
    });

    test('one of four completed → 0.25', () {
      final svc = buildService(completedStoryIds: const {'m1'});
      expect(
        svc.getCompletionPercentage(PathType.characters, 'moses'),
        0.25,
      );
    });

    test('two of four completed → 0.5', () {
      final svc = buildService(completedStoryIds: const {'m1', 'm2'});
      expect(
        svc.getCompletionPercentage(PathType.characters, 'moses'),
        0.5,
      );
    });

    test('three of four completed → 0.75', () {
      final svc = buildService(completedStoryIds: const {'m1', 'm2', 'm3'});
      expect(
        svc.getCompletionPercentage(PathType.characters, 'moses'),
        0.75,
      );
    });

    test('all four completed → 1.0', () {
      final svc = buildService(
        completedStoryIds: const {'m1', 'm2', 'm3', 'm4'},
      );
      expect(
        svc.getCompletionPercentage(PathType.characters, 'moses'),
        1.0,
      );
    });
  });

  group('Kid-mode denominator (SPEC 50.5 + INVARIANTS #3a)', () {
    test(
        'kid-mode user sees 100% when they complete all kid-eligible stories',
        () {
      // Build a mixed path: 2 kid-friendly, 2 adult-only
      final parables = [
        fixture(
          storyId: 'kid1',
          title: 'Kid 1',
          bibleSourceRef: 'Exodus 1:1',
          primaryCharacterId: 'moses',
          timelineEra: 'exodus',
          themeTags: const ['faith'],
          bibleOrderIndex: 40,
          characterPathOrder: 1,
          kidFriendly: true,
        ),
        fixture(
          storyId: 'adult1',
          title: 'Adult 1',
          bibleSourceRef: 'Exodus 2:1',
          primaryCharacterId: 'moses',
          timelineEra: 'exodus',
          themeTags: const ['faith'],
          bibleOrderIndex: 45,
          characterPathOrder: 2,
          kidFriendly: false,
        ),
        fixture(
          storyId: 'kid2',
          title: 'Kid 2',
          bibleSourceRef: 'Exodus 3:1',
          primaryCharacterId: 'moses',
          timelineEra: 'exodus',
          themeTags: const ['faith'],
          bibleOrderIndex: 50,
          characterPathOrder: 3,
          kidFriendly: true,
        ),
        fixture(
          storyId: 'adult2',
          title: 'Adult 2',
          bibleSourceRef: 'Exodus 14:1',
          primaryCharacterId: 'moses',
          timelineEra: 'exodus',
          themeTags: const ['faith'],
          bibleOrderIndex: 52,
          characterPathOrder: 4,
          kidFriendly: false,
        ),
      ];
      // Kid-mode user, completed both kid-eligible stories.
      final svc = buildService(
        parables: parables,
        kidFriendlyOnly: true,
        completedStoryIds: const {'kid1', 'kid2'},
      );
      // Denominator is 2 (kid-eligible only), numerator is 2 → 1.0
      expect(
        svc.getCompletionPercentage(PathType.characters, 'moses'),
        1.0,
      );
    });

    test(
        'adult-mode user sees 0.5 on the same path completing the same 2 stories',
        () {
      // Adult mode (kidFriendlyOnly == false) does NOT filter out
      // kid-friendly stories — adult users see BOTH kid and adult
      // stories. This matches ParableService behavior and matches
      // SPEC 50.5 (kid-mode strictness is one-way).
      final parables = [
        fixture(
          storyId: 'kid1',
          title: 'Kid 1',
          bibleSourceRef: 'Exodus 1:1',
          primaryCharacterId: 'moses',
          timelineEra: 'exodus',
          themeTags: const ['faith'],
          bibleOrderIndex: 40,
          characterPathOrder: 1,
          kidFriendly: true,
        ),
        fixture(
          storyId: 'adult1',
          title: 'Adult 1',
          bibleSourceRef: 'Exodus 2:1',
          primaryCharacterId: 'moses',
          timelineEra: 'exodus',
          themeTags: const ['faith'],
          bibleOrderIndex: 45,
          characterPathOrder: 2,
          kidFriendly: false,
        ),
        fixture(
          storyId: 'kid2',
          title: 'Kid 2',
          bibleSourceRef: 'Exodus 3:1',
          primaryCharacterId: 'moses',
          timelineEra: 'exodus',
          themeTags: const ['faith'],
          bibleOrderIndex: 50,
          characterPathOrder: 3,
          kidFriendly: true,
        ),
        fixture(
          storyId: 'adult2',
          title: 'Adult 2',
          bibleSourceRef: 'Exodus 14:1',
          primaryCharacterId: 'moses',
          timelineEra: 'exodus',
          themeTags: const ['faith'],
          bibleOrderIndex: 52,
          characterPathOrder: 4,
          kidFriendly: false,
        ),
      ];
      // Adult mode: denominator is 4 (all 4 visible to adult user).
      // Completing kid1 and kid2 → 2/4 → 0.5.
      final svc = buildService(
        parables: parables,
        kidFriendlyOnly: false,
        completedStoryIds: const {'kid1', 'kid2'},
      );
      expect(
        svc.getCompletionPercentage(PathType.characters, 'moses'),
        0.5,
      );
    });
  });

  group('Out-of-path completions are ignored', () {
    test('completing stories not in the path does not inflate the ratio',
        () {
      final svc = buildService(
        completedStoryIds: const {'not_in_moses_1', 'not_in_moses_2'},
      );
      expect(
        svc.getCompletionPercentage(PathType.characters, 'moses'),
        0.0,
      );
    });

    test('mix of in-path and out-of-path completions only counts in-path',
        () {
      final svc = buildService(
        completedStoryIds: const {'m1', 'not_in_moses'},
      );
      // Denominator = 4 (moses path), numerator = 1 (only m1)
      expect(
        svc.getCompletionPercentage(PathType.characters, 'moses'),
        0.25,
      );
    });
  });

  group('Return value is bounded [0.0, 1.0]', () {
    test('ratio is never negative', () {
      final svc = buildService();
      final pct = svc.getCompletionPercentage(PathType.characters, 'moses');
      expect(pct, greaterThanOrEqualTo(0.0));
    });

    test('ratio is never greater than 1.0', () {
      final svc = buildService(
        completedStoryIds: const {
          'm1',
          'm2',
          'm3',
          'm4',
          'extra1',
          'extra2'
        },
      );
      final pct = svc.getCompletionPercentage(PathType.characters, 'moses');
      expect(pct, lessThanOrEqualTo(1.0));
      expect(pct, 1.0);
    });
  });
}
