import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_pal/features/main_menu/main_menu_screen.dart';
import 'package:bible_pal/features/paths/path_launch_context.dart';
import 'package:bible_pal/providers/app_state_notifier.dart';
import 'package:bible_pal/providers/parable_player_notifier.dart';
import 'package:bible_pal/services/audio_service.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/models/parable.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// AppStateNotifier that returns default state without real services.
class _TestAppStateNotifier extends AppStateNotifier {
  _TestAppStateNotifier({this.kidFriendlyOnly = false});

  final bool kidFriendlyOnly;

  @override
  Future<AppState> build() async {
    return AppState(
      userPreferences:
          UserPreferences.defaults().copyWith(kidFriendlyOnly: kidFriendlyOnly),
      favorites: [],
      history: [],
      pals: [],
    );
  }

  // Update in-memory only — avoids the real persistence services that
  // aren't wired in tests. Lets the Kid Mode gate flip state observably.
  @override
  Future<void> updateKidFriendlyOnly(bool value) async {
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(
        userPreferences:
            current.userPreferences.copyWith(kidFriendlyOnly: value),
      ),
    );
  }
}

/// ParablePlayerNotifier that returns a predetermined state without
/// touching AudioService or native plugins.
class _TestPlayerNotifier extends ParablePlayerNotifier {
  final ParablePlayerState _initial;
  _TestPlayerNotifier(this._initial);

  @override
  ParablePlayerState build() => _initial;

  // --- audio-related overrides (avoid late-init of _audioService) ---
  @override
  bool get isPlaying => false;
  @override
  bool get isPaused => false;
  @override
  Duration get position => Duration.zero;
  @override
  Duration? get duration => const Duration(minutes: 5);
  @override
  Stream<Duration> get positionStream => Stream.value(Duration.zero);
  @override
  Stream<Duration?> get durationStream =>
      Stream.value(const Duration(minutes: 5));
  @override
  AudioService get audioService => throw UnimplementedError('Not in test');
  @override
  Future<VoicePlayResult> play() async => VoicePlayResult.played;
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration p) async {}
  @override
  Future<void> setSpeed(double s) async {}
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<bool> loadParable(
    Parable p, {
    PathLaunchContext? launchContext,
  }) async =>
      true;
  @override
  Future<void> clear() async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildScreen({
  ParablePlayerState? playerState,
  NavigatorObserver? observer,
  bool kidMode = false,
}) {
  final state = playerState ?? const ParablePlayerState();
  return ProviderScope(
    overrides: [
      appStateProvider
          .overrideWith(() => _TestAppStateNotifier(kidFriendlyOnly: kidMode)),
      parablePlayerProvider.overrideWith(() => _TestPlayerNotifier(state)),
    ],
    child: MaterialApp(
      home: const MainMenuScreen(),
      navigatorObservers: [if (observer != null) observer],
      // Catch-all route so button taps don't crash the test.
      onGenerateRoute: (_) =>
          MaterialPageRoute(builder: (_) => const Scaffold()),
    ),
  );
}

Parable _testParable({
  String title = 'The Good Shepherd',
  String? bibleSourceRef,
  List<String> scriptureSources = const [],
}) {
  return Parable(
    storyId: 'test-001',
    title: title,
    mood: 'peaceful',
    length: 10,
    storytellingMode: 'traditional',
    kidFriendly: false,
    bibleSourceRef: bibleSourceRef,
    scriptureSources: scriptureSources,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Skip first-launch intro by marking it as already shown.
    SharedPreferences.setMockInitialValues({'pal_intro_shown': true});
  });

  // --- PAL constant ---

  group('PAL constant', () {
    testWidgets('PAL button is present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // PAL orb text is on Sanctuary page (page 1)
      expect(find.text('PAL'), findsOneWidget);
    });

    testWidgets('PAL button is tappable without exceptions', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('PAL'));
      // Pump past voice flow timers (STT permission check has 8s timeout)
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    });
  });

  // --- Study page (IDLE panel) ---

  group('IDLE panel (no current parable)', () {
    testWidgets('shows mood heading and mood buttons on Study page',
        (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Swipe to Study page
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('How are you feeling?'), findsOneWidget);
      // Mood buttons present
      expect(find.text('Joyful'), findsOneWidget);
    });
  });

  // --- NOW PLAYING panel ---

  group('NOW PLAYING panel (parable active, not completed)', () {
    testWidgets('shows title + play/pause + slider', (tester) async {
      final parable = _testParable(
        title: 'The Good Shepherd',
        bibleSourceRef: 'John 10:11',
      );
      await tester.pumpWidget(_buildScreen(
        playerState: ParablePlayerState(
          currentParable: parable,
          playbackCompleted: false,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Swipe to Study page where the panel is
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('The Good Shepherd'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });
  });

  // --- FINISHED panel ---

  group('FINISHED panel (playback completed)', () {
    testWidgets('shows Save and Replay buttons', (tester) async {
      final parable = _testParable(title: 'Finished Story');
      await tester.pumpWidget(_buildScreen(
        playerState: ParablePlayerState(
          currentParable: parable,
          playbackCompleted: true,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Swipe to Study page
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Replay'), findsOneWidget);
    });
  });

  // --- Voice flow ---

  group('voice flow', () {
    testWidgets('PAL button starts voice conversation flow', (tester) async {
      // Use a generous surface so the opening line text (Feature 2.0)
      // doesn't cause RenderFlex overflow in the constrained test viewport.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildScreen());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('PAL'));
      await tester.pump(); // starts _startConversation; enters playingOpeningLine

      // Opening line state shows subtitle immediately.
      expect(
        find.textContaining('PAL is speaking'),
        findsOneWidget,
        reason: 'PAL button should start voice conversation flow',
      );
      expect(tester.takeException(), isNull);

      // Drain the 1800ms opening-line display timer (Feature 2.0) so no
      // pending timers remain when the test ends.
      await tester.pump(const Duration(milliseconds: 1800));
    });
  });

  // --- Crossfade ---

  group('crossfade safety', () {
    testWidgets('AnimatedSwitcher does not throw on panel render',
        (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });

  // --- Parent gate (SPEC Feature 51.2) ---
  //
  // These assert the two gate VISUAL states (the contract a child/parent
  // sees). The hold-3s interaction itself is verified manually per SPEC —
  // tap/gesture interaction on page 1 is intercepted by the PageView/route
  // transition AbsorbPointer in the widget-test harness.

  group('parent gate (Feature 51.2)', () {
    Future<void> openMoodPage(WidgetTester tester) async {
      // Tall surface so the Kid Mode pill (bottom of the non-scrolling
      // Mood page) is laid out on-screen.
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // The Kid Mode pill lives on the Mood page (page 1).
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('OFF: pill reads OFF with no exit gate hint', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await openMoodPage(tester);

      expect(find.textContaining('Kid Mode: OFF', findRichText: true),
          findsOneWidget);
      // No parent gate when off — entering is a plain tap.
      expect(find.text('Hold to exit'), findsNothing);
      expect(find.text('Keep holding to exit…'), findsNothing);
    });

    testWidgets('ON: pill reads ON and surfaces the hold-to-exit gate hint',
        (tester) async {
      await tester.pumpWidget(_buildScreen(kidMode: true));
      await openMoodPage(tester);

      expect(find.textContaining('Kid Mode: ON', findRichText: true),
          findsOneWidget);
      // The exit gate is advertised: a tap won't exit, only a 3s hold.
      expect(find.text('Hold to exit'), findsOneWidget);
    });
  });
}
