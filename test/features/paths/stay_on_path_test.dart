import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/character_registry.dart';
import 'package:bible_pal/features/paths/path_launch_context.dart';
import 'package:bible_pal/features/paths/path_type.dart';
import 'package:bible_pal/features/pals_parables/parable_player_screen.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/services/path_service.dart';

/// Tests for PALs Paths completion-flow upgrade:
///
/// 1. NextInJourneyBlock rendering bug fix — PathService cache during
///    transient loading state (SPEC Feature 50.6)
/// 2. Stay on the Path toggle — session-scoped auto-advance (SPEC 50.6c)
/// 3. Pause for Reflection toggle — opt-in reflection autoplay (SPEC 50.6d)
/// 4. Add to Journal — always-visible action (SPEC Feature 40)
///
/// These tests validate the PathService-layer logic and constants.
/// Widget-level integration tests for the toggle UI require a full
/// ProviderScope + audio mocking setup that lives in the widget test
/// suite. The tests here focus on data-layer correctness.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    CharacterRegistry.resetForTest();
    await CharacterRegistry.ensureLoaded();
  });

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

  List<Parable> buildSnapshot() {
    return [
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
        storyId: 's1017',
        title: 'Binding of Isaac',
        bibleSourceRef: 'Genesis 22:1-18',
        primaryCharacterId: 'abraham',
        timelineEra: 'patriarchs',
        themeTags: ['faith', 'obedience'],
        bibleOrderIndex: 22,
        characterPathOrder: 2,
      ),
      fixture(
        storyId: 's1018',
        title: 'Abraham and Three Visitors',
        bibleSourceRef: 'Genesis 18:1-15',
        primaryCharacterId: 'abraham',
        timelineEra: 'patriarchs',
        themeTags: ['faith', 'hope'],
        bibleOrderIndex: 18,
        characterPathOrder: 3,
      ),
    ];
  }

  group('NextInJourneyBlock bug fix — PathService cache', () {
    test(
        'getNextInPath returns correct story regardless of completion set changes',
        () {
      // Build PathService with no completions — simulates initial state.
      final snapshot = buildSnapshot();
      final service1 = PathService(
        traditionalParables: snapshot,
        jesusLifeSequence: [],
        kidFriendlyOnly: false,
        completedStoryIds: {},
      );

      final next1 = service1.getNextInPath(
        PathType.characters,
        'abraham',
        0, // position 0 → should return position 1
      );
      expect(next1, isNotNull);
      expect(next1!.storyId, 's1017');

      // Rebuild PathService WITH s1016 completed — simulates the
      // invalidation that causes the transient loading state. The
      // getNextInPath result MUST be identical because path order
      // is sacred (SPEC 50.6 — never filtered by completion).
      final service2 = PathService(
        traditionalParables: snapshot,
        jesusLifeSequence: [],
        kidFriendlyOnly: false,
        completedStoryIds: {'s1016'},
      );

      final next2 = service2.getNextInPath(
        PathType.characters,
        'abraham',
        0,
      );
      expect(next2, isNotNull);
      expect(next2!.storyId, 's1017',
          reason: 'Path order is sacred — completion must not change next');
    });

    test('cached PathService value is safe for getNextInPath lookups', () {
      // Simulates the bug fix: using a stale PathService snapshot for
      // getNextInPath while the provider is loading. Since getNextInPath
      // does not depend on completion state, the stale snapshot produces
      // the same result.
      final snapshot = buildSnapshot();
      final staleService = PathService(
        traditionalParables: snapshot,
        jesusLifeSequence: [],
        kidFriendlyOnly: false,
        completedStoryIds: {},
      );

      final freshService = PathService(
        traditionalParables: snapshot,
        jesusLifeSequence: [],
        kidFriendlyOnly: false,
        completedStoryIds: {'s1016', 's1017'},
      );

      // Both services return the same next story at every position.
      for (int pos = 0; pos < 2; pos++) {
        final staleNext = staleService.getNextInPath(
          PathType.characters,
          'abraham',
          pos,
        );
        final freshNext = freshService.getNextInPath(
          PathType.characters,
          'abraham',
          pos,
        );
        expect(staleNext?.storyId, freshNext?.storyId,
            reason:
                'Stale and fresh services must agree on next at position $pos');
      }
    });
  });

  group('Stay on the Path — auto-advance sequencing (SPEC 50.6c)', () {
    test('getNextInPath returns null at end of path', () {
      final snapshot = buildSnapshot();
      final service = PathService(
        traditionalParables: snapshot,
        jesusLifeSequence: [],
        kidFriendlyOnly: false,
        completedStoryIds: {},
      );

      final stories =
          service.getPathStories(PathType.characters, 'abraham');
      final lastIndex = stories.length - 1;

      final next = service.getNextInPath(
        PathType.characters,
        'abraham',
        lastIndex,
      );
      expect(next, isNull,
          reason: 'No auto-advance at end of path');
    });

    test('getNextInPath never skips completed stories', () {
      final snapshot = buildSnapshot();
      final service = PathService(
        traditionalParables: snapshot,
        jesusLifeSequence: [],
        kidFriendlyOnly: false,
        completedStoryIds: {'s1017'}, // Middle story completed
      );

      final next = service.getNextInPath(
        PathType.characters,
        'abraham',
        0,
      );
      expect(next, isNotNull);
      expect(next!.storyId, 's1017',
          reason:
              'Path order is sacred — completed stories are NOT skipped');
    });

    test(
        'PathLaunchContext advances position correctly for auto-advance chain',
        () {
      const ctx = PathLaunchContext(
        pathType: PathType.characters,
        pathId: 'abraham',
        positionInPath: 0,
      );

      // Simulate what auto-advance does: position + 1
      final nextCtx = PathLaunchContext(
        pathType: ctx.pathType,
        pathId: ctx.pathId,
        positionInPath: ctx.positionInPath + 1,
      );

      expect(nextCtx.positionInPath, 1);
      expect(nextCtx.pathType, PathType.characters);
      expect(nextCtx.pathId, 'abraham');

      // Chain again
      final nextNextCtx = PathLaunchContext(
        pathType: nextCtx.pathType,
        pathId: nextCtx.pathId,
        positionInPath: nextCtx.positionInPath + 1,
      );
      expect(nextNextCtx.positionInPath, 2);
    });
  });

  group('Auto-advance constants', () {
    test('kAutoAdvanceDelay is 4 seconds', () {
      expect(kAutoAdvanceDelay, const Duration(seconds: 4));
    });
  });

  group('End-of-path safety', () {
    test('getNextInPath at every position returns null only at end', () {
      final snapshot = buildSnapshot();
      final service = PathService(
        traditionalParables: snapshot,
        jesusLifeSequence: [],
        kidFriendlyOnly: false,
        completedStoryIds: {},
      );

      final stories =
          service.getPathStories(PathType.characters, 'abraham');
      expect(stories.length, 3);

      // Positions 0 and 1 have a next story
      for (int i = 0; i < stories.length - 1; i++) {
        final next = service.getNextInPath(
          PathType.characters,
          'abraham',
          i,
        );
        expect(next, isNotNull, reason: 'Position $i should have a next');
      }

      // Last position has no next
      final last = service.getNextInPath(
        PathType.characters,
        'abraham',
        stories.length - 1,
      );
      expect(last, isNull,
          reason: 'Last position must return null (end of path)');
    });

    test('getNextInPath beyond path length returns null safely', () {
      final snapshot = buildSnapshot();
      final service = PathService(
        traditionalParables: snapshot,
        jesusLifeSequence: [],
        kidFriendlyOnly: false,
        completedStoryIds: {},
      );

      final beyondEnd = service.getNextInPath(
        PathType.characters,
        'abraham',
        999,
      );
      expect(beyondEnd, isNull,
          reason: 'Out-of-bounds position must not crash');
    });
  });

  group('No duplicate advance risk', () {
    test(
        'getNextInPath is deterministic across repeated calls with same inputs',
        () {
      final snapshot = buildSnapshot();
      final service = PathService(
        traditionalParables: snapshot,
        jesusLifeSequence: [],
        kidFriendlyOnly: false,
        completedStoryIds: {},
      );

      final first = service.getNextInPath(
        PathType.characters,
        'abraham',
        0,
      );
      final second = service.getNextInPath(
        PathType.characters,
        'abraham',
        0,
      );
      expect(first?.storyId, second?.storyId,
          reason:
              'Repeated calls must return the same result (no side effects)');
    });
  });
}
