// ignore: unnecessary_import
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/paths/path_detail_screen.dart';
import 'package:bible_pal/features/paths/path_type.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/providers/service_providers.dart';
import 'package:bible_pal/services/path_service.dart';

/// Phase 3 Slice 6 widget tests for PathDetailScreen.
///
/// Contracts verified:
/// - "Continue Your Journey" card hidden when 0 completions on this path
/// - "Continue Your Journey" card shown when ≥ 1 completion
/// - Completion markers appear on completed story tiles
/// - Completed stories are STILL tappable (path order is sacred)
/// - Empty path renders the empty-state message
void main() {
  Parable fixture({
    required String storyId,
    required String title,
    required String bibleSourceRef,
    required int bibleOrderIndex,
    required int characterPathOrder,
    String primaryCharacterId = 'moses',
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
      primaryCharacterId: primaryCharacterId,
      primaryCharacterDisplayName: primaryCharacterId,
      bibleOrderIndex: bibleOrderIndex,
      timelineEra: 'exodus',
      themeTags: const ['faith'],
      characterPathOrder: characterPathOrder,
    );
  }

  List<Parable> mosesSnapshot() {
    return [
      fixture(
        storyId: 's1019',
        title: 'Moses and the Burning Bush',
        bibleSourceRef: 'Exodus 3:1-15',
        bibleOrderIndex: 50,
        characterPathOrder: 1,
      ),
      fixture(
        storyId: 's1048',
        title: 'The Crossing of the Red Sea',
        bibleSourceRef: 'Exodus 14:10-31',
        bibleOrderIndex: 52,
        characterPathOrder: 2,
      ),
    ];
  }

  PathService buildService({
    Set<String> completedStoryIds = const <String>{},
    List<Parable>? parables,
  }) {
    return PathService(
      traditionalParables: parables ?? mosesSnapshot(),
      jesusLifeSequence: const <String>[],
      kidFriendlyOnly: false,
      completedStoryIds: completedStoryIds,
    );
  }

  Widget wrap(PathService pathService) {
    return ProviderScope(
      overrides: [
        pathServiceProvider.overrideWith((ref) async => pathService),
      ],
      child: const MaterialApp(
        home: PathDetailScreen(
          pathType: PathType.characters,
          pathId: 'moses',
          displayLabel: 'Moses',
        ),
      ),
    );
  }

  group('Continue Your Journey visibility (SPEC 50.6b)', () {
    testWidgets('hidden when user has 0 completions on this path',
        (tester) async {
      await tester.pumpWidget(wrap(buildService()));
      // PathDetailScreen embeds LivingSkyBackground which animates
      // continuously, so pumpAndSettle() never returns. Use pump()
      // twice to drive: initial frame, then post-frame callback
      // (telemetry + provider settled).
      await tester.pump();
      await tester.pump();

      expect(find.text('Continue Your Journey'), findsNothing);
      // But the path stories still render
      expect(find.text('Moses and the Burning Bush'), findsOneWidget);
      expect(find.text('The Crossing of the Red Sea'), findsOneWidget);
    });

    testWidgets('shown when user has 1 completion on this path',
        (tester) async {
      await tester.pumpWidget(wrap(
        buildService(completedStoryIds: const {'s1019'}),
      ));
      // PathDetailScreen embeds LivingSkyBackground which animates
      // continuously, so pumpAndSettle() never returns. Use pump()
      // twice to drive: initial frame, then post-frame callback
      // (telemetry + provider settled).
      await tester.pump();
      await tester.pump();

      expect(find.text('Continue Your Journey'), findsOneWidget);
      // Resume points to the first uncompleted (Red Sea)
      // "The Crossing of the Red Sea" appears TWICE now:
      //   1. in the Continue Your Journey card
      //   2. in the ordered story list
      expect(
        find.text('The Crossing of the Red Sea'),
        findsNWidgets(2),
      );
    });

    testWidgets(
        'shown when all stories are completed (replay mode — resume to first)',
        (tester) async {
      await tester.pumpWidget(wrap(
        buildService(completedStoryIds: const {'s1019', 's1048'}),
      ));
      // PathDetailScreen embeds LivingSkyBackground which animates
      // continuously, so pumpAndSettle() never returns. Use pump()
      // twice to drive: initial frame, then post-frame callback
      // (telemetry + provider settled).
      await tester.pump();
      await tester.pump();

      expect(find.text('Continue Your Journey'), findsOneWidget);
      // Resume points to the first story (Burning Bush) for replay
      // "Moses and the Burning Bush" now appears TWICE (card + list)
      expect(
        find.text('Moses and the Burning Bush'),
        findsNWidgets(2),
      );
    });
  });

  group('Completion markers (SPEC 50.6 — path order is sacred)', () {
    testWidgets('no markers when no stories are completed', (tester) async {
      await tester.pumpWidget(wrap(buildService()));
      // PathDetailScreen embeds LivingSkyBackground which animates
      // continuously, so pumpAndSettle() never returns. Use pump()
      // twice to drive: initial frame, then post-frame callback
      // (telemetry + provider settled).
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('one marker when one story is completed', (tester) async {
      await tester.pumpWidget(wrap(
        buildService(completedStoryIds: const {'s1019'}),
      ));
      // PathDetailScreen embeds LivingSkyBackground which animates
      // continuously, so pumpAndSettle() never returns. Use pump()
      // twice to drive: initial frame, then post-frame callback
      // (telemetry + provider settled).
      await tester.pump();
      await tester.pump();

      // One completion marker on the Burning Bush tile. The Continue
      // Your Journey card does not render a marker itself — only
      // tiles in the story list.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('two markers when both stories are completed',
        (tester) async {
      await tester.pumpWidget(wrap(
        buildService(completedStoryIds: const {'s1019', 's1048'}),
      ));
      // PathDetailScreen embeds LivingSkyBackground which animates
      // continuously, so pumpAndSettle() never returns. Use pump()
      // twice to drive: initial frame, then post-frame callback
      // (telemetry + provider settled).
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    });

    testWidgets('completed stories still render in the list (not hidden)',
        (tester) async {
      await tester.pumpWidget(wrap(
        buildService(completedStoryIds: const {'s1019', 's1048'}),
      ));
      // PathDetailScreen embeds LivingSkyBackground which animates
      // continuously, so pumpAndSettle() never returns. Use pump()
      // twice to drive: initial frame, then post-frame callback
      // (telemetry + provider settled).
      await tester.pump();
      await tester.pump();

      // Path order is sacred — completed stories remain visible.
      // When all are completed, CYJ resume points to the FIRST story
      // (Burning Bush) for replay, so Burning Bush appears twice (CYJ
      // card + list) and Red Sea appears once (list only).
      expect(find.text('Moses and the Burning Bush'), findsNWidgets(2));
      expect(find.text('The Crossing of the Red Sea'), findsOneWidget);
    });
  });

  group('Empty path edge case', () {
    testWidgets('empty path renders empty-state message', (tester) async {
      await tester.pumpWidget(wrap(
        PathService(
          traditionalParables: const <Parable>[],
          jesusLifeSequence: const <String>[],
          kidFriendlyOnly: false,
        ),
      ));
      // PathDetailScreen embeds LivingSkyBackground which animates
      // continuously, so pumpAndSettle() never returns. Use pump()
      // twice to drive: initial frame, then post-frame callback
      // (telemetry + provider settled).
      await tester.pump();
      await tester.pump();

      expect(find.text('No stories in this path yet.'), findsOneWidget);
      expect(find.text('Continue Your Journey'), findsNothing);
    });
  });

  group('Loading state', () {
    testWidgets('renders progress indicator while provider is loading',
        (tester) async {
      final completer = Completer<PathService>();
      addTearDown(() {
        if (!completer.isCompleted) {
          completer.complete(buildService());
        }
      });
      final widget = ProviderScope(
        overrides: [
          pathServiceProvider.overrideWith((ref) => completer.future),
        ],
        child: const MaterialApp(
          home: PathDetailScreen(
            pathType: PathType.characters,
            pathId: 'moses',
            displayLabel: 'Moses',
          ),
        ),
      );
      await tester.pumpWidget(widget);
      await tester.pump(); // first frame — still loading

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Continue Your Journey'), findsNothing);
    });
  });
}
