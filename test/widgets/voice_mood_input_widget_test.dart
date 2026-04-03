import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/features/pals_parables/pals_parables_screen.dart';
import 'package:bible_pal/services/stt_service.dart';
import 'package:bible_pal/providers/service_providers.dart';
import 'package:bible_pal/services/storage_service.dart';

/// Widget tests for voice mood input UI states (Feature 2.2).
///
/// Tests that the mic button, listening indicator, partial transcript,
/// and fallback typing are rendered correctly per SPEC.md Feature 2.2.
void main() {
  late SttService mockSttService;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Use a real SttService — in test env, STT is unavailable,
    // which is the correct behavior for testing disabled state.
    mockSttService = SttService();
  });

  /// Build a minimal widget tree with PalsParablesScreen + required providers.
  Widget buildTestApp({SttService? sttService}) {
    return ProviderScope(
      overrides: [
        storageServiceProvider.overrideWith((ref) async {
          final prefs = await SharedPreferences.getInstance();
          return StorageService(prefs);
        }),
      ],
      child: MaterialApp(
        home: PalsParablesScreen(sttService: sttService ?? mockSttService),
      ),
    );
  }

  group('Voice mood input widget', () {
    testWidgets('mic button is visible on PalsParablesScreen', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(seconds: 1));

      // Mic button should be present (key: voice_mic_button)
      expect(find.byKey(const Key('voice_mic_button')), findsOneWidget);
    });

    testWidgets('mic button shows mic icon', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('TextField is always visible regardless of voice state',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(seconds: 1));

      // TextField should be present for typing
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('"or" label is visible in idle state', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('or'), findsOneWidget);
    });

    testWidgets('Continue button is visible', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('prompt subtitle is rendered', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(seconds: 1));

      // Subtitle text should be present
      expect(find.textContaining('Share how you\'re really doing'),
          findsOneWidget);
    });

    testWidgets('TextField hint text is correct in idle state', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(seconds: 1));

      // Hint text rotates between time-aware prompts; verify the TextField has one
      final textField = tester.widget<TextField>(find.byType(TextField));
      final hintText = textField.decoration?.hintText ?? '';
      expect(hintText.isNotEmpty, isTrue,
          reason: 'TextField should have a rotating hint');
    });

    testWidgets('mic button has correct tooltip when STT unavailable',
        (tester) async {
      // In test environment, STT is unavailable
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(seconds: 1));

      final micButton = tester.widget<IconButton>(
        find.byKey(const Key('voice_mic_button')),
      );
      expect(micButton.tooltip, 'Voice input not available on this platform');
    });

    testWidgets('tapping mic when STT unavailable shows snackbar',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(seconds: 1));

      // Scroll to make mic button visible (mood buttons push it off-screen)
      await tester.ensureVisible(find.byKey(const Key('voice_mic_button')));
      await tester.pump(const Duration(seconds: 1));

      // Tap the mic button
      await tester.tap(find.byKey(const Key('voice_mic_button')));
      await tester.pump();

      // Should show "not available" snackbar
      expect(find.text('Voice input not available on this platform'),
          findsOneWidget);
    });
  });
}
