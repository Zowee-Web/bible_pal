import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_state_notifier.dart';
import '../../theme/app_theme.dart';
import '../settings/settings_screen.dart';

/// Main Menu Screen
/// Based on UI/UX Design Spec Section 4: Home Screen
///
/// Layout: Vertical, clean, centered, no scrolling required
/// - Daily Bread Verse (top, fixed, calm)
/// - PAL's Parables button (centerpiece, large, with gold outline)
/// - Favorites & History buttons (secondary, smaller, softer)
class MainMenuScreen extends ConsumerWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final appStateAsync = ref.watch(appStateProvider);

    return appStateAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppTheme.parchment,
        body: Center(
          child: CircularProgressIndicator(
            color: AppTheme.softSkyBlue,
          ),
        ),
      ),
      error: (error, stack) => Scaffold(
        backgroundColor: AppTheme.parchment,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: AppTheme.deepCharcoal.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'Unable to load app',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.deepCharcoal.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
      data: (appState) {
        final dailyVerse = appState.dailyBread;
        final dailyBread = dailyVerse != null
            ? '"${dailyVerse.verse}"'
            : '"In Your presence is fullness of joy."';
        final verseReference = dailyVerse?.reference ?? 'Psalm 16:11';

        return Scaffold(
      backgroundColor: AppTheme.parchment,
      body: SafeArea(
        child: Column(
          children: [
            // Settings Icon (top right, subtle)
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: IconButton(
                  icon: Icon(
                    Icons.settings_outlined,
                    color: AppTheme.deepCharcoal.withOpacity(0.6),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
              ),
            ),

            // Spacer to center content
            const Spacer(flex: 1),

            // Daily Bread Verse Section (Top Area - Fixed, Calm, Centered)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Text(
                    'Daily Bread',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppTheme.warmGold,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    dailyBread,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '— $verseReference',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.deepCharcoal.withOpacity(0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 48),

            // PAL's Parables Button (Centerpiece - Large, Gold Outline)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.warmGold,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.warmGold.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: AppTheme.softSkyBlue,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).pushNamed('/pals_parables');
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 28,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_stories_outlined,
                            size: 48,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'PAL\'s Stories',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to share how your day is going',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withOpacity(0.9),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Secondary Buttons (Favorites, History & My PALs - Smaller, Softer)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pushNamed('/favorites');
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(
                              color: AppTheme.lightBlue,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: Icon(
                            Icons.favorite_outline,
                            size: 20,
                            color: AppTheme.softSkyBlue,
                          ),
                          label: Text(
                            'Favorites',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: AppTheme.deepCharcoal,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pushNamed('/history');
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(
                              color: AppTheme.lightBlue,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: Icon(
                            Icons.history_outlined,
                            size: 20,
                            color: AppTheme.softSkyBlue,
                          ),
                          label: Text(
                            'History',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: AppTheme.deepCharcoal,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushNamed('/my_pals');
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(
                        color: AppTheme.lightBlue,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(
                      Icons.people_outline,
                      size: 20,
                      color: AppTheme.softSkyBlue,
                    ),
                    label: Text(
                      'My PALs',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppTheme.deepCharcoal,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Spacer to center content
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
      },
    );
  }
}
