import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'features/onboarding/tradition_setup_screen.dart';
import 'features/main_menu/main_menu_screen.dart';
import 'features/pals_parables/pals_parables_screen.dart';
import 'features/pals_parables/parable_player_screen.dart';
import 'features/favorites/favorites_screen.dart';
import 'features/history/history_screen.dart';
import 'features/my_pals/my_pals_screen.dart';

class AppRouter extends StatelessWidget {
  final bool needsTradition;
  const AppRouter({super.key, required this.needsTradition});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bible PAL',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: needsTradition ? const TraditionSetupScreen() : const MainMenuScreen(),
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/pals_parables':
        return MaterialPageRoute(
          builder: (_) => const PalsParablesScreen(),
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
      default:
        return null;
    }
  }
}
