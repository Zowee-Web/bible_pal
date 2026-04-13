// ignore: unnecessary_import
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/paths/next_in_journey_block.dart';
import 'package:bible_pal/features/paths/path_launch_context.dart';
import 'package:bible_pal/features/paths/path_type.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/providers/parable_player_notifier.dart';
import 'package:bible_pal/providers/service_providers.dart';
import 'package:bible_pal/services/path_service.dart';

/// Player notifier override that emits the requested state
/// deterministically. Does NOT instantiate real audio services.
class StaticPlayerNotifier extends ParablePlayerNotifier {
  StaticPlayerNotifier(this._state);
  final ParablePlayerState _state;

  @override
  ParablePlayerState build() => _state;

  @override
  Future<bool> loadParable(
    Parable parable, {
    PathLaunchContext? launchContext,
  }) async {
    // Record the load by updating state so the test can observe it.
    state = _state.copyWith(
      currentParable: parable,
      launchContext: launchContext,
      playbackCompleted: false,
    );
    return true;
  }
}

/// Phase 2 Slice 7 widget tests for NextInJourneyBlock (SPEC Feature 50.6).
///
/// Verifies the 3-condition rendering contract:
///   1. Renders nothing when launchContext == null
///   2. Renders nothing when playbackCompleted == false
///   3. Renders nothing when getNextInPath returns null
///   Full block renders when all 3 are true.
///
/// Tests use Riverpod provider overrides to avoid loading the real
/// manifest or constructing a full ParablePlayerNotifier.
void main() {
  Parable fixture({
    required String storyId,
    required String title,
    required String bibleSourceRef,
  }) {
    return Parable(
      storyId: storyId,
      title: title,
      mood: 'brave_courage',
      storytellingMode: 'traditional',
      kidFriendly: false,
      bibleSourceRef: bibleSourceRef,
      bibleStoryKey: '${storyId}_key',
      storyLength: 'short',
      narratorVoiceKey: 'VOICE_JAMES_HUSKY',
      primaryCharacterId: 'moses',
      primaryCharacterDisplayName: 'Moses',
      bibleOrderIndex: 50,
      timelineEra: 'exodus',
      themeTags: const ['faith'],
      characterPathOrder: 1,
    );
  }

  Widget wrap({
    required ParablePlayerState playerState,
    required PathService pathService,
  }) {
    return ProviderScope(
      overrides: [
        parablePlayerProvider.overrideWith(
          () => StaticPlayerNotifier(playerState),
        ),
        pathServiceProvider.overrideWith((ref) async => pathService),
      ],
      child: const MaterialApp(
        home: Scaffold(body: NextInJourneyBlock()),
      ),
    );
  }

  // --- Shared test PathService ---
  // Two-story Moses path: Burning Bush (pos 0) → Red Sea (pos 1)
  PathService buildMosesPathService({
    Set<String> completedStoryIds = const <String>{},
  }) {
    return PathService(
      traditionalParables: [
        fixture(
          storyId: 's1019',
          title: 'Moses and the Burning Bush',
          bibleSourceRef: 'Exodus 3:1-15',
        ),
        Parable(
          storyId: 's1048',
          title: 'The Crossing of the Red Sea',
          mood: 'anxious',
          storytellingMode: 'traditional',
          kidFriendly: false,
          bibleSourceRef: 'Exodus 14:10-31',
          bibleStoryKey: 'crossing_the_red_sea',
          storyLength: 'short',
          narratorVoiceKey: 'VOICE_ELIJAH_SAGE',
          primaryCharacterId: 'moses',
          primaryCharacterDisplayName: 'Moses',
          bibleOrderIndex: 52,
          timelineEra: 'exodus',
          themeTags: const ['courage', 'faith'],
          characterPathOrder: 2,
        ),
      ],
      jesusLifeSequence: const <String>[],
      kidFriendlyOnly: false,
      completedStoryIds: completedStoryIds,
    );
  }

  group('Rendering conditions (SPEC 50.6)', () {
    testWidgets('renders nothing when launchContext is null', (tester) async {
      await tester.pumpWidget(wrap(
        playerState: ParablePlayerState(
          currentParable: fixture(
            storyId: 's1019',
            title: 'Burning Bush',
            bibleSourceRef: 'Exodus 3:1-15',
          ),
          playbackCompleted: true,
          launchContext: null,
        ),
        pathService: buildMosesPathService(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Next in Your Journey'), findsNothing);
      expect(find.text('The Crossing of the Red Sea'), findsNothing);
      expect(find.byType(SizedBox), findsWidgets); // empty block = SizedBox.shrink
    });

    testWidgets('renders nothing when playbackCompleted == false',
        (tester) async {
      await tester.pumpWidget(wrap(
        playerState: ParablePlayerState(
          currentParable: fixture(
            storyId: 's1019',
            title: 'Burning Bush',
            bibleSourceRef: 'Exodus 3:1-15',
          ),
          playbackCompleted: false,
          launchContext: const PathLaunchContext(
            pathType: PathType.characters,
            pathId: 'moses',
            positionInPath: 0,
          ),
        ),
        pathService: buildMosesPathService(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Next in Your Journey'), findsNothing);
      expect(find.text('The Crossing of the Red Sea'), findsNothing);
    });

    testWidgets('renders nothing when at final position in path',
        (tester) async {
      await tester.pumpWidget(wrap(
        playerState: ParablePlayerState(
          currentParable: fixture(
            storyId: 's1048',
            title: 'Red Sea',
            bibleSourceRef: 'Exodus 14:10-31',
          ),
          playbackCompleted: true,
          launchContext: const PathLaunchContext(
            pathType: PathType.characters,
            pathId: 'moses',
            positionInPath: 1, // final position in the 2-story path
          ),
        ),
        pathService: buildMosesPathService(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Next in Your Journey'), findsNothing);
    });
  });

  group('Full block rendering', () {
    testWidgets(
        'renders title, scripture ref, and play button when all 3 conditions true',
        (tester) async {
      await tester.pumpWidget(wrap(
        playerState: ParablePlayerState(
          currentParable: fixture(
            storyId: 's1019',
            title: 'Burning Bush',
            bibleSourceRef: 'Exodus 3:1-15',
          ),
          playbackCompleted: true,
          launchContext: const PathLaunchContext(
            pathType: PathType.characters,
            pathId: 'moses',
            positionInPath: 0,
          ),
        ),
        pathService: buildMosesPathService(),
      ));
      await tester.pumpAndSettle();

      // Block header — exact locked copy
      expect(find.text('Next in Your Journey'), findsOneWidget);
      // Next story title (position 1 in Moses path — Red Sea)
      expect(find.text('The Crossing of the Red Sea'), findsOneWidget);
      // Next story scripture reference
      expect(find.text('Exodus 14:10-31'), findsOneWidget);
      // Play button
      expect(find.text('Play'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      // No completion marker by default (next story is not completed)
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });
  });

  group('Phase 3 completion marker (SPEC 50.6 — path order is sacred)', () {
    testWidgets(
        'renders completion marker when next story is already completed, '
        'and block still renders', (tester) async {
      await tester.pumpWidget(wrap(
        playerState: ParablePlayerState(
          currentParable: fixture(
            storyId: 's1019',
            title: 'Burning Bush',
            bibleSourceRef: 'Exodus 3:1-15',
          ),
          playbackCompleted: true,
          launchContext: const PathLaunchContext(
            pathType: PathType.characters,
            pathId: 'moses',
            positionInPath: 0,
          ),
        ),
        pathService: buildMosesPathService(
          completedStoryIds: const {'s1048'}, // next story is completed
        ),
      ));
      await tester.pumpAndSettle();

      // Block still renders (path order is sacred — completed stories
      // are NOT auto-skipped)
      expect(find.text('Next in Your Journey'), findsOneWidget);
      expect(find.text('The Crossing of the Red Sea'), findsOneWidget);
      // Completion marker is visible
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      // Play button still there
      expect(find.text('Play'), findsOneWidget);
    });

    testWidgets(
        'no completion marker when next story is NOT completed',
        (tester) async {
      await tester.pumpWidget(wrap(
        playerState: ParablePlayerState(
          currentParable: fixture(
            storyId: 's1019',
            title: 'Burning Bush',
            bibleSourceRef: 'Exodus 3:1-15',
          ),
          playbackCompleted: true,
          launchContext: const PathLaunchContext(
            pathType: PathType.characters,
            pathId: 'moses',
            positionInPath: 0,
          ),
        ),
        pathService: buildMosesPathService(
          completedStoryIds: const {'s1019'}, // current story, not next
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Next in Your Journey'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });
  });

  group('Async path service states', () {
    testWidgets('renders nothing while pathServiceProvider is loading',
        (tester) async {
      // Use a never-completing Completer so the provider stays in
      // loading state without scheduling a timer (Future.delayed would
      // leave a pending timer when the test widget tears down).
      final completer = Completer<PathService>();
      addTearDown(() {
        if (!completer.isCompleted) {
          completer.complete(buildMosesPathService());
        }
      });

      final widget = ProviderScope(
        overrides: [
          parablePlayerProvider.overrideWith(
            () => StaticPlayerNotifier(
              ParablePlayerState(
                currentParable: fixture(
                  storyId: 's1019',
                  title: 'Burning Bush',
                  bibleSourceRef: 'Exodus 3:1-15',
                ),
                playbackCompleted: true,
                launchContext: const PathLaunchContext(
                  pathType: PathType.characters,
                  pathId: 'moses',
                  positionInPath: 0,
                ),
              ),
            ),
          ),
          pathServiceProvider.overrideWith((ref) => completer.future),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NextInJourneyBlock()),
        ),
      );
      await tester.pumpWidget(widget);
      // Do not settle — let it stay in loading state.
      await tester.pump();

      expect(find.text('Next in Your Journey'), findsNothing);
    });
  });
}
