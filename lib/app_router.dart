import 'dart:async';
import 'package:flutter/material.dart';
import 'theme/living_sky.dart';
import 'features/onboarding/first_launch_screen.dart';
import 'features/main_menu/main_menu_screen.dart';
import 'features/pals_parables/pals_parables_screen.dart';
import 'features/pals_parables/parable_player_screen.dart';
import 'features/favorites/favorites_screen.dart';
import 'features/history/history_screen.dart';
import 'features/my_pals/my_pals_screen.dart';
import 'features/story_reader/story_reader_screen.dart';
import 'features/journal/journal_screen.dart';
import 'features/length_picker/length_picker_screen.dart';
import 'features/diagnostics/diagnostics_screen.dart';
import 'core/diagnostics_config.dart';

class AppRouter extends StatefulWidget {
  final bool showFirstLaunch;
  const AppRouter({super.key, required this.showFirstLaunch});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> with WidgetsBindingObserver {
  SkyPhase _phase = LivingSky.getPhase();
  Timer? _phaseTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check for phase changes every 60 seconds
    _phaseTimer = Timer.periodic(const Duration(seconds: 60), (_) => _checkPhase());
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check phase when app returns to foreground
    if (state == AppLifecycleState.resumed) {
      _checkPhase();
    }
  }

  void _checkPhase() {
    final newPhase = LivingSky.getPhase();
    if (newPhase != _phase) {
      setState(() => _phase = newPhase);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bible PAL',
      debugShowCheckedModeBanner: false,
      theme: LivingSky.buildTheme(_phase),
      home:
          widget.showFirstLaunch ? const FirstLaunchScreen() : const MainMenuScreen(),
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/pals_parables':
        final args = settings.arguments as Map<String, dynamic>?;
        final textOnly = args?['textOnly'] as bool? ?? false;
        final navigateToReader = args?['navigateToReader'] as bool? ?? false;
        final initialText = args?['initialText'] as String?;
        return MaterialPageRoute(
          builder: (_) => PalsParablesScreen(textOnly: textOnly, navigateToReader: navigateToReader, initialText: initialText),
        );
      case '/parable_player':
        return MaterialPageRoute(
          builder: (_) => const ParablePlayerScreen(),
        );
      case '/favorites':
        return MaterialPageRoute(
          builder: (_) => const FavoritesScreen(),
        );
      case '/history':
        return MaterialPageRoute(
          builder: (_) => const HistoryScreen(),
        );
      case '/my_pals':
        return MaterialPageRoute(
          builder: (_) => const MyPalsScreen(),
        );
      case '/main_menu':
        return MaterialPageRoute(
          builder: (_) => const MainMenuScreen(),
        );
      case '/story_reader':
        return MaterialPageRoute(
          builder: (_) => const StoryReaderScreen(),
        );
      case '/first_launch':
        return MaterialPageRoute(
          builder: (_) => const FirstLaunchScreen(),
        );
      case '/journal':
        return MaterialPageRoute(
          builder: (_) => const JournalScreen(),
        );
      case '/length_picker':
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => LengthPickerScreen(
            mood: args['mood'] as String,
            userText: args['userText'] as String? ?? '',
          ),
        );
      case '/diagnostics':
        // Only allow navigation when diagnostics are enabled
        if (!kDiagnosticsEnabled) return null;
        return MaterialPageRoute(
          builder: (_) => const DiagnosticsScreen(),
        );
      default:
        return null;
    }
  }
}
