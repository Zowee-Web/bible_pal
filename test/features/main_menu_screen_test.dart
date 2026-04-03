import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_pal/features/main_menu/main_menu_screen.dart';
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
  @override
  Future<AppState> build() async {
    return AppState(
      userPreferences: UserPreferences.defaults(),
      favorites: [],
      history: [],
      pals: [],
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
  Future<void> loadParable(Parable p) async {}
  @override
  Future<void> clear() async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildScreen({
  ParablePlayerState? playerState,
  NavigatorObserver? observer,
}) {
  final state = playerState ?? const ParablePlayerState();
  return ProviderScope(
    overrides: [
      appStateProvider.overrideWith(() => _TestAppStateNotifier()),
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
      await tester.pumpWidget(_buildScreen());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('PAL'));
      await tester.pump();

      // PAL button starts voice flow
      expect(
        find.textContaining('PAL is speaking'),
        findsOneWidget,
        reason: 'PAL button should start voice conversation flow',
      );
      expect(tester.takeException(), isNull);
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
}
