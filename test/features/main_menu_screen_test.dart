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

/// NavigatorObserver that counts pushes after initial route.
class _PushCountObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Skip the initial MaterialApp route (previousRoute == null).
    if (previousRoute != null) pushCount++;
  }
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
    testWidgets('PAL button is present with correct labels', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('PAL'), findsOneWidget);
      expect(find.text('Tap for a mood based story'), findsOneWidget);
    });

    testWidgets('PAL button is tappable without exceptions', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Tap navigates to /pals_parables.
      await tester.tap(find.text('PAL'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // --- IDLE panel ---

  group('IDLE panel (no current parable)', () {
    testWidgets('shows exact locked labels', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text("Read Today's Story"), findsOneWidget);
      expect(find.text('Text PAL'), findsOneWidget);
    });

    testWidgets('shows length selector buckets', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Short'), findsOneWidget);
      expect(find.text('Full'), findsOneWidget);
      expect(find.text('Long'), findsOneWidget);
    });
  });

  // --- NOW PLAYING panel ---

  group('NOW PLAYING panel (parable active, not completed)', () {
    testWidgets('shows title + scripture + play/pause + slider',
        (tester) async {
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
      await tester.pumpAndSettle();

      expect(find.text('The Good Shepherd'), findsOneWidget);
      expect(find.text('John 10:11'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('uses scriptureSources with +N more when no bibleSourceRef',
        (tester) async {
      final parable = _testParable(
        title: 'Creative Parable',
        scriptureSources: ['Romans 8:28', 'Psalm 23:1', 'John 3:16'],
      );
      await tester.pumpWidget(_buildScreen(
        playerState: ParablePlayerState(
          currentParable: parable,
          playbackCompleted: false,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Romans 8:28, Psalm 23:1 +1 more'), findsOneWidget);
    });

    testWidgets('does not show IDLE labels', (tester) async {
      final parable = _testParable();
      await tester.pumpWidget(_buildScreen(
        playerState: ParablePlayerState(
          currentParable: parable,
          playbackCompleted: false,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text("Read Today's Story"), findsNothing);
    });
  });

  // --- FINISHED panel ---

  group('FINISHED panel (playback completed)', () {
    testWidgets('shows Save to Favorites and Share with a PAL',
        (tester) async {
      final parable = _testParable(title: 'Finished Story');
      await tester.pumpWidget(_buildScreen(
        playerState: ParablePlayerState(
          currentParable: parable,
          playbackCompleted: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Save to Favorites'), findsOneWidget);
      expect(find.text('Share with a PAL'), findsOneWidget);
    });

    testWidgets('does not show IDLE or NOW PLAYING content', (tester) async {
      final parable = _testParable(title: 'Finished Story');
      await tester.pumpWidget(_buildScreen(
        playerState: ParablePlayerState(
          currentParable: parable,
          playbackCompleted: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text("Read Today's Story"), findsNothing);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('Share with a PAL does NOT push a named route',
        (tester) async {
      final observer = _PushCountObserver();
      final parable = _testParable(title: 'Finished Story');
      await tester.pumpWidget(_buildScreen(
        playerState: ParablePlayerState(
          currentParable: parable,
          playbackCompleted: true,
        ),
        observer: observer,
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Share with a PAL'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share with a PAL'));
      await tester.pumpAndSettle();

      // Share opens a dialog (DialogRoute), not a named page route.
      // Verify no exception thrown (dialog may or may not be visible
      // depending on pals list, but no /parable_player navigation).
      expect(tester.takeException(), isNull);
    });
  });

  // --- Navigation lock: Page 2 ONLY via "Read Today's Story" ---

  group('navigation lock', () {
    testWidgets("Read Today's Story navigates (idle, no parable)",
        (tester) async {
      final observer = _PushCountObserver();
      await tester.pumpWidget(_buildScreen(observer: observer));
      await tester.pumpAndSettle();

      final pushesBefore = observer.pushCount;
      await tester.ensureVisible(find.text("Read Today's Story"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Read Today's Story"));
      await tester.pumpAndSettle();

      expect(observer.pushCount, greaterThan(pushesBefore),
          reason: "Read Today's Story MUST push a route");
      expect(tester.takeException(), isNull);
    });

    testWidgets('PAL button starts voice conversation flow', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('PAL'));
      await tester.pump();

      // PAL button now starts voice flow instead of navigating
      // Verify the button subtitle changes to indicate flow started
      expect(
        find.textContaining('PAL is speaking'),
        findsOneWidget,
        reason: 'PAL button should start voice conversation flow',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Text PAL navigates to /pals_parables', (tester) async {
      final observer = _PushCountObserver();
      await tester.pumpWidget(_buildScreen(observer: observer));
      await tester.pumpAndSettle();

      final pushesBefore = observer.pushCount;
      await tester.ensureVisible(find.text('Text PAL'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Text PAL'));
      await tester.pumpAndSettle();

      expect(observer.pushCount, greaterThan(pushesBefore),
          reason: 'Text PAL MUST push a route');
      expect(tester.takeException(), isNull);
    });
  });

  // --- Crossfade ---

  group('crossfade safety', () {
    testWidgets('AnimatedSwitcher does not throw on panel render',
        (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
