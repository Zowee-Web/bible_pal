import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/features/paths/paths_page.dart';
import 'package:bible_pal/providers/service_providers.dart';
import 'package:bible_pal/services/path_service.dart';
import 'package:bible_pal/services/search_service.dart';

/// Widget tests for the PALs Paths page shell after Phase 2 wiring
/// (SPEC Feature 48 page 2 + Feature 50).
///
/// Phase 2 changed the pill taps from local-state selection to
/// navigation into [PathInstanceListScreen]. These tests therefore
/// verify the *structural* shell (featured tile + 4 pills + bottom-
/// anchored search + empty hint) and use provider overrides so no
/// real manifest loads during the test.
///
/// Navigation flow tests (pill tap → instance list → detail) live in
/// `path_service_test.dart` and will be covered at the integration
/// level when we have real story content wired.
void main() {
  /// Builds a minimal PathService with zero parables — enough to
  /// satisfy the provider without loading the real manifest.
  PathService emptyPathService() => PathService(
        traditionalParables: const [],
        jesusLifeSequence: const [],
        kidFriendlyOnly: false,
      );

  SearchService emptySearchService() => SearchService(
        traditionalParables: const [],
        kidFriendlyOnly: false,
      );

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [
        pathServiceProvider.overrideWith((ref) async => emptyPathService()),
        searchServiceProvider.overrideWith(
          (ref) async => emptySearchService(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('Featured Life of Jesus tile renders at the top', (tester) async {
    await tester.pumpWidget(wrap(PathsPage(theme: ThemeData.dark())));
    await tester.pumpAndSettle();

    // Featured tile renders
    expect(find.text('The Life of Jesus'), findsOneWidget);
    expect(find.text('A guided journey'), findsOneWidget);
  });

  testWidgets('All four standard path-type pills render', (tester) async {
    await tester.pumpWidget(wrap(PathsPage(theme: ThemeData.dark())));
    await tester.pumpAndSettle();

    expect(find.text('Bible Order'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Themes'), findsOneWidget);
    expect(find.text('Characters'), findsOneWidget);
  });

  testWidgets('Bottom-anchored search input has spec placeholder',
      (tester) async {
    await tester.pumpWidget(wrap(PathsPage(theme: ThemeData.dark())));
    await tester.pumpAndSettle();

    // SPEC Feature 50.7: exact placeholder text
    expect(
      find.text('Search Scripture'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Empty-query content area shows hint, not results',
      (tester) async {
    await tester.pumpWidget(wrap(PathsPage(theme: ThemeData.dark())));
    await tester.pumpAndSettle();

    expect(find.text('Pick a path above, or search below.'), findsOneWidget);
    expect(find.text('No stories matched.'), findsNothing);
  });

  testWidgets('Typing a query replaces hint with search results area',
      (tester) async {
    await tester.pumpWidget(wrap(PathsPage(theme: ThemeData.dark())));
    await tester.pumpAndSettle();

    // Initially hint is visible
    expect(find.text('Pick a path above, or search below.'), findsOneWidget);

    // Type a query — empty SearchService has nothing to return
    await tester.enterText(find.byType(TextField), 'Moses');
    await tester.pumpAndSettle();

    // Hint disappears, "No stories matched." appears (empty snapshot)
    expect(find.text('Pick a path above, or search below.'), findsNothing);
    expect(find.text('No stories matched.'), findsOneWidget);
  });

  testWidgets('Clearing the query restores the hint', (tester) async {
    await tester.pumpWidget(wrap(PathsPage(theme: ThemeData.dark())));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Moses');
    await tester.pumpAndSettle();
    expect(find.text('No stories matched.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('Pick a path above, or search below.'), findsOneWidget);
  });
}
