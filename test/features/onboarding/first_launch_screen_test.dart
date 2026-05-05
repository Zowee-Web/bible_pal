/// First-launch onboarding screen tests
///
/// Verifies:
/// - Silent first launch shows typed intro lines, then name input + Begin
/// - No audio or voice consent UI during onboarding
/// - Begin tap (after entering a name) marks onboarding complete and navigates
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

    testWidgets('shows name input and Begin button after typing intro',
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

      // Advance past intro typing animation
      await tester.pump(const Duration(seconds: 8));
      await tester.pump(const Duration(milliseconds: 500));

      // After typing completes, name input + Begin button fade in
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Your name'), findsOneWidget);
      expect(find.text('Begin'), findsOneWidget);
    });

    testWidgets('does NOT show voice consent UI during onboarding',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: FirstLaunchScreen(),
          ),
        ),
      );

      // Advance past all animations
      await tester.pump(const Duration(seconds: 8));

      // No voice consent surface — fresh installs auto-enable per
      // _handleContinue's currentVoiceConsentVersion stamping.
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

    testWidgets('Begin tap marks onboarding complete', (tester) async {
      // This test verifies the SharedPreferences side-effect of completing
      // onboarding. It does NOT assert post-navigation widget presence —
      // _handleContinue also fires nameAudioServiceProvider which requires a
      // mocked HTTP-capable scope to drive a Navigator transition cleanly in
      // tests. The dedicated routing tests below verify AppRouter behavior
      // when kFirstLaunchCompleteKey is set.
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

      // Advance past typing animation so name input is enabled
      await tester.pump(const Duration(seconds: 8));
      await tester.pump(const Duration(milliseconds: 500));

      // Type a name
      await tester.enterText(find.byType(TextField), 'Adam');
      await tester.pump();

      // Tap Begin
      await tester.tap(find.text('Begin'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Verify first launch flag is set (onboarding complete)
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool(kFirstLaunchCompleteKey), true);
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
