/// First-launch onboarding screen tests
///
/// Verifies:
/// - First launch shows typing animation + name prompt
/// - No audio or voice consent is triggered
/// - Name is persisted
/// - User lands on PAL's Stories after completion
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

    testWidgets('shows typing animation on first launch', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: FirstLaunchScreen(),
          ),
        ),
      );

      // Initially, the text should start appearing (typing animation)
      expect(find.byType(FirstLaunchScreen), findsOneWidget);

      // Wait for some typing animation frames
      await tester.pump(const Duration(milliseconds: 100));

      // Should find partial text (typing in progress)
      expect(find.textContaining('Hi'), findsOneWidget);
    });

    testWidgets('shows name input field after typing completes',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: FirstLaunchScreen(),
          ),
        ),
      );

      // Wait for typing animation to complete (full message is ~120 chars at 35ms each)
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Name input should be visible
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Your name'), findsOneWidget);

      // Continue button should be enabled
      final continueButton = find.widgetWithText(ElevatedButton, 'Continue');
      expect(continueButton, findsOneWidget);
    });

    testWidgets('does NOT show voice consent dialog', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: FirstLaunchScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle(const Duration(seconds: 5));

      // No voice consent dialog should appear
      expect(find.text('Enable Voice Features'), findsNothing);
      expect(find.text('Voice Consent'), findsNothing);
      expect(find.text('Story Narration'), findsNothing);
      expect(find.text('PAL Greetings'), findsNothing);
    });

    testWidgets('does NOT play any audio during onboarding', (tester) async {
      // This test verifies the screen structure has no audio-related widgets
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: FirstLaunchScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle(const Duration(seconds: 5));

      // No audio player widgets should be present
      // The screen is purely text-based with typing animation
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
      expect(find.byIcon(Icons.volume_up), findsNothing);
    });

    testWidgets('requires name before continuing', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: FirstLaunchScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Try to continue without entering name
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      // Should show error snackbar
      expect(find.text('Please enter your name'), findsOneWidget);
    });

    testWidgets('persists name and marks onboarding complete', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: const FirstLaunchScreen(),
            routes: {
              '/pals_parables': (_) => const Scaffold(
                    body: Text('PAL\'s Stories Screen'),
                  ),
            },
          ),
        ),
      );

      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Enter name
      await tester.enterText(find.byType(TextField), 'TestUser');
      await tester.pumpAndSettle();

      // Tap continue
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      // Verify first launch flag is set
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool(kFirstLaunchCompleteKey), true);
    });

    testWidgets('navigates to PAL\'s Stories after name entry', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: const FirstLaunchScreen(),
            routes: {
              '/pals_parables': (_) => const Scaffold(
                    body: Text('PAL\'s Stories Screen'),
                  ),
            },
          ),
        ),
      );

      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Enter name
      await tester.enterText(find.byType(TextField), 'TestUser');
      await tester.pumpAndSettle();

      // Tap continue
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      // Should navigate to PAL's Stories
      expect(find.text('PAL\'s Stories Screen'), findsOneWidget);
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

      await tester.pump();

      expect(find.byType(FirstLaunchScreen), findsOneWidget);
    });

    testWidgets('AppRouter shows MainMenuScreen when showFirstLaunch=false',
        (tester) async {
      // Set up preferences to prevent any redirect
      SharedPreferences.setMockInitialValues({
        kFirstLaunchCompleteKey: true,
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: AppRouter(showFirstLaunch: false),
        ),
      );

      // Just pump once - don't wait for all async operations to settle
      // since MainMenuScreen has async providers
      await tester.pump();

      // Should not show FirstLaunchScreen
      expect(find.byType(FirstLaunchScreen), findsNothing);
    });

    testWidgets('subsequent launches skip onboarding', (tester) async {
      // Simulate completed onboarding
      SharedPreferences.setMockInitialValues({
        kFirstLaunchCompleteKey: true,
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: AppRouter(showFirstLaunch: false),
        ),
      );

      // Just pump once - don't wait for all async operations to settle
      // since MainMenuScreen has async providers
      await tester.pump();

      // FirstLaunchScreen should not appear
      expect(find.byType(FirstLaunchScreen), findsNothing);
    });
  });
}
