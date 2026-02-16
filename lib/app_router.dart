import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'features/onboarding/first_launch_screen.dart';
import 'features/main_menu/main_menu_screen.dart';
import 'features/pals_parables/pals_parables_screen.dart';
import 'features/pals_parables/parable_player_screen.dart';
import 'features/favorites/favorites_screen.dart';
import 'features/history/history_screen.dart';
import 'features/my_pals/my_pals_screen.dart';
import 'features/diagnostics/diagnostics_screen.dart';
import 'core/diagnostics_config.dart';

class AppRouter extends StatelessWidget {
  final bool showFirstLaunch;
  const AppRouter({super.key, required this.showFirstLaunch});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bible PAL',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home:
          showFirstLaunch ? const FirstLaunchScreen() : const MainMenuScreen(),
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/pals_parables':
        final args = settings.arguments as Map<String, dynamic>?;
        final textOnly = args?['textOnly'] as bool? ?? false;
        return MaterialPageRoute(
          builder: (_) => PalsParablesScreen(textOnly: textOnly),
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
      case '/first_launch':
        return MaterialPageRoute(
          builder: (_) => const FirstLaunchScreen(),
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
