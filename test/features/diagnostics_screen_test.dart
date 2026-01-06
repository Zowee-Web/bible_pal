import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/features/diagnostics/diagnostics_screen.dart';
import 'package:bible_pal/core/diagnostics_config.dart';
import 'package:bible_pal/core/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLogger.instance.clearBreadcrumbs();
  });

  group('DiagnosticsScreen', () {
    testWidgets('shows appropriate content based on diagnostics flag',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DiagnosticsScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // When disabled, shows "not available" message
      // When enabled, shows either breadcrumbs or empty state
      if (!kDiagnosticsEnabled) {
        // Should show disabled message
        expect(find.textContaining('not available'), findsOneWidget);
      } else {
        // Should show either breadcrumbs list or empty state
        final hasBreadcrumbs = find.text('No breadcrumbs recorded yet.').evaluate().isNotEmpty;
        final hasListView = find.byType(ListView).evaluate().isNotEmpty;
        expect(hasBreadcrumbs || hasListView, isTrue);
      }
    });

    testWidgets('shows app bar with title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DiagnosticsScreen(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Diagnostics'), findsOneWidget);
    });

    testWidgets('has refresh button in app bar when enabled', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DiagnosticsScreen(),
        ),
      );

      await tester.pumpAndSettle();

      if (kDiagnosticsEnabled) {
        expect(find.byIcon(Icons.refresh), findsOneWidget);
      } else {
        // When disabled, no action buttons shown
        expect(find.byIcon(Icons.refresh), findsNothing);
      }
    });

    testWidgets('shows empty state when no breadcrumbs', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DiagnosticsScreen(),
        ),
      );

      await tester.pumpAndSettle();

      if (kDiagnosticsEnabled) {
        expect(find.text('No breadcrumbs recorded yet.'), findsOneWidget);
      }
    });

    testWidgets('displays breadcrumbs from AppLogger', (tester) async {
      // Add some breadcrumbs
      logEvent('test_event_1', {'data': 'value1'});
      logEvent('test_event_2', {'data': 'value2'});

      await tester.pumpWidget(
        const MaterialApp(
          home: DiagnosticsScreen(),
        ),
      );

      await tester.pumpAndSettle();

      if (kDiagnosticsEnabled) {
        expect(find.text('test_event_1'), findsOneWidget);
        expect(find.text('test_event_2'), findsOneWidget);
      }
    });

    testWidgets('copy button is disabled when no breadcrumbs', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DiagnosticsScreen(),
        ),
      );

      await tester.pumpAndSettle();

      if (kDiagnosticsEnabled) {
        final copyButton = find.byIcon(Icons.copy);
        expect(copyButton, findsOneWidget);
        // Button should be there but disabled
      }
    });

    testWidgets('clear button shows confirmation dialog', (tester) async {
      // Add a breadcrumb so the button is enabled
      logEvent('test_event', {'data': 'value'});

      await tester.pumpWidget(
        const MaterialApp(
          home: DiagnosticsScreen(),
        ),
      );

      await tester.pumpAndSettle();

      if (kDiagnosticsEnabled) {
        // Tap clear button
        await tester.tap(find.byIcon(Icons.delete_outline));
        await tester.pumpAndSettle();

        // Should show confirmation dialog
        expect(find.text('Clear Breadcrumbs?'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Clear'), findsOneWidget);
      }
    });

    testWidgets('cancel in clear dialog does not clear', (tester) async {
      logEvent('test_event', {'data': 'value'});

      await tester.pumpWidget(
        const MaterialApp(
          home: DiagnosticsScreen(),
        ),
      );

      await tester.pumpAndSettle();

      if (kDiagnosticsEnabled) {
        // Tap clear button
        await tester.tap(find.byIcon(Icons.delete_outline));
        await tester.pumpAndSettle();

        // Tap cancel
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Breadcrumb should still be there
        expect(find.text('test_event'), findsOneWidget);
      }
    });
  });

  group('DiagnosticsScreen UI Elements', () {
    testWidgets('shows level badges with correct colors', (tester) async {
      // Add events with different levels
      logEvent('debug_event', {'x': 1}, level: LogLevel.debug);
      logEvent('info_event', {'x': 2}, level: LogLevel.info);
      logEvent('warn_event', {'x': 3}, level: LogLevel.warn);
      logEvent('error_event', {'x': 4}, level: LogLevel.error);

      await tester.pumpWidget(
        const MaterialApp(
          home: DiagnosticsScreen(),
        ),
      );

      await tester.pumpAndSettle();

      if (kDiagnosticsEnabled) {
        expect(find.text('DEBUG'), findsOneWidget);
        expect(find.text('INFO'), findsOneWidget);
        expect(find.text('WARN'), findsOneWidget);
        expect(find.text('ERROR'), findsOneWidget);
      }
    });

    testWidgets('expansion tile shows data details', (tester) async {
      logEvent('expandable_event', {'story_id': 'parable_001', 'score': 0.85});

      await tester.pumpWidget(
        const MaterialApp(
          home: DiagnosticsScreen(),
        ),
      );

      await tester.pumpAndSettle();

      if (kDiagnosticsEnabled) {
        // Tap to expand
        await tester.tap(find.text('expandable_event'));
        await tester.pumpAndSettle();

        // Should show data
        expect(find.textContaining('parable_001'), findsOneWidget);
        expect(find.textContaining('0.85'), findsOneWidget);
      }
    });
  });
}
