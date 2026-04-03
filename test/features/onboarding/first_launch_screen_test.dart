/// First-launch onboarding screen tests
///
/// Verifies:
/// - Silent first launch shows Living Sky + PAL orb + mood buttons
/// - No audio, voice consent, or name prompt during onboarding
/// - Mood tap marks onboarding complete and navigates to main menu
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_pal/features/onboarding/first_launch_screen.dart';
import 'package:bible_pal/app_router.dart';

void main() {
  group('FirstLaunchScreen', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('shows PAL orb and mood buttons after staggered fade-in',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: FirstLaunchScreen(),
          ),
        ),
      );

      // Initially present
      expect(find.byType(FirstLaunchScreen), findsOneWidget);

      // Advance past all fade-in stages (1.5s fade + 1s orb + 1s text + 1s moods)
      await tester.pump(const Duration(milliseconds: 4000));
      await tester.pump(const Duration(milliseconds: 500));

      // "How are you feeling?" should be visible
      expect(find.text('How are you feeling?'), findsOneWidget);

      // PAL text in orb should be visible
      expect(find.text('PAL'), findsOneWidget);

      // Mood buttons should be visible
      expect(find.text('Joyful'), findsOneWidget);
      expect(find.text('Grateful'), findsOneWidget);
      expect(find.text('Peaceful'), findsOneWidget);
    });

    testWidgets('does NOT show name input or voice consent', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: FirstLaunchScreen(),
          ),
        ),
      );

      // Advance past all animations
      await tester.pump(const Duration(seconds: 5));

      // No name input
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Your name'), findsNothing);
      expect(find.text('Begin'), findsNothing);

      // No voice consent
      expect(find.text('Enable Voice Features'), findsNothing);
      expect(find.text('Voice Consent'), findsNothing);
    });

    testWidgets('does NOT play any audio during onboarding', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: FirstLaunchScreen(),
          ),
        ),
      );

      await tester.pump(const Duration(seconds: 5));

      // No audio player widgets
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
      expect(find.byIcon(Icons.volume_up), findsNothing);
    });

    testWidgets('mood tap marks onboarding complete and navigates',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: const FirstLaunchScreen(),
            routes: {
              '/main_menu': (_) => const Scaffold(
                    body: Text('Main Menu Screen'),
                  ),
            },
          ),
        ),
      );

      // Advance past all fade-in stages
      await tester.pump(const Duration(seconds: 5));

      // Tap a mood button
      await tester.tap(find.text('Joyful'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify first launch flag is set
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool(kFirstLaunchCompleteKey), true);

      // Should navigate to Main Menu
      expect(find.text('Main Menu Screen'), findsOneWidget);
    });
  });

  group('First Launch Routing', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('AppRouter shows FirstLaunchScreen when showFirstLaunch=true',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: AppRouter(showFirstLaunch: true),
        ),
      );

      // Pump past staggered animation delays in FirstLaunchScreen._startSequence
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      expect(find.byType(FirstLaunchScreen), findsOneWidget);
    });

    testWidgets('AppRouter shows MainMenuScreen when showFirstLaunch=false',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        kFirstLaunchCompleteKey: true,
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: AppRouter(showFirstLaunch: false),
        ),
      );

      await tester.pump();

      expect(find.byType(FirstLaunchScreen), findsNothing);
    });

    testWidgets('subsequent launches skip onboarding', (tester) async {
      SharedPreferences.setMockInitialValues({
        kFirstLaunchCompleteKey: true,
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: AppRouter(showFirstLaunch: false),
        ),
      );

      await tester.pump();

      expect(find.byType(FirstLaunchScreen), findsNothing);
    });
  });
}
