import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/story_length_bucket.dart';
import 'package:bible_pal/widgets/story_length_radio_selector.dart';

/// Stateful wrapper so taps actually update the selected bucket in the tree.
class _SelectorHarness extends StatefulWidget {
  final StoryLengthBucket initialBucket;
  const _SelectorHarness({required this.initialBucket});

  @override
  State<_SelectorHarness> createState() => _SelectorHarnessState();
}

class _SelectorHarnessState extends State<_SelectorHarness> {
  late StoryLengthBucket _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialBucket;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: StoryLengthRadioSelector(
          selectedBucket: _selected,
          onBucketChanged: (bucket) => setState(() => _selected = bucket),
        ),
      ),
    );
  }
}

void main() {
  group('StoryLengthRadioSelector', () {
    testWidgets('renders all three bucket labels', (tester) async {
      await tester.pumpWidget(
        const _SelectorHarness(initialBucket: StoryLengthBucket.short),
      );

      expect(find.text('Short Story'), findsOneWidget);
      expect(find.text('Full Story'), findsOneWidget);
      expect(find.text('Long Story'), findsOneWidget);
    });

    testWidgets('default bucket (short) renders selected indicator',
        (tester) async {
      await tester.pumpWidget(
        const _SelectorHarness(initialBucket: StoryLengthBucket.short),
      );

      // The selected row's AnimatedScale should have scale 1.0 (inner dot visible).
      // Unselected rows should have scale 0.0.
      final scales = tester
          .widgetList<AnimatedScale>(find.byType(AnimatedScale))
          .toList();
      expect(scales.length, 3);

      // First row (Short) selected
      expect(scales[0].scale, 1.0);
      // Other rows not selected
      expect(scales[1].scale, 0.0);
      expect(scales[2].scale, 0.0);
    });

    testWidgets('tapping Full Story selects it and deselects others',
        (tester) async {
      await tester.pumpWidget(
        const _SelectorHarness(initialBucket: StoryLengthBucket.short),
      );

      // Tap "Full Story"
      await tester.tap(find.text('Full Story'));
      await tester.pump();

      final scales = tester
          .widgetList<AnimatedScale>(find.byType(AnimatedScale))
          .toList();

      // Short deselected
      expect(scales[0].scale, 0.0);
      // Full selected
      expect(scales[1].scale, 1.0);
      // Long deselected
      expect(scales[2].scale, 0.0);
    });

    testWidgets('tapping Long Story selects it and deselects others',
        (tester) async {
      await tester.pumpWidget(
        const _SelectorHarness(initialBucket: StoryLengthBucket.short),
      );

      // Tap "Long Story"
      await tester.tap(find.text('Long Story'));
      await tester.pump();

      final scales = tester
          .widgetList<AnimatedScale>(find.byType(AnimatedScale))
          .toList();

      // Short deselected
      expect(scales[0].scale, 0.0);
      // Full deselected
      expect(scales[1].scale, 0.0);
      // Long selected
      expect(scales[2].scale, 1.0);
    });

    testWidgets('animation widgets are present (AnimatedContainer + AnimatedScale)',
        (tester) async {
      await tester.pumpWidget(
        const _SelectorHarness(initialBucket: StoryLengthBucket.short),
      );

      // 3 rows × 2 AnimatedContainers each (row highlight + circle border) = 6
      expect(find.byType(AnimatedContainer), findsNWidgets(6));
      // 3 AnimatedScale widgets (one per row inner dot)
      expect(find.byType(AnimatedScale), findsNWidgets(3));
    });

    testWidgets('animation completes without exceptions after tap',
        (tester) async {
      await tester.pumpWidget(
        const _SelectorHarness(initialBucket: StoryLengthBucket.short),
      );

      // Tap to change selection
      await tester.tap(find.text('Long Story'));
      // Pump through the full animation duration (150ms)
      await tester.pump(const Duration(milliseconds: 150));

      // No exceptions — animation completed cleanly
      final scales = tester
          .widgetList<AnimatedScale>(find.byType(AnimatedScale))
          .toList();
      expect(scales[2].scale, 1.0);
    });

    testWidgets('Semantics widgets are present for accessibility', (tester) async {
      await tester.pumpWidget(
        const _SelectorHarness(initialBucket: StoryLengthBucket.full),
      );

      // Each row wraps content in a Semantics widget
      final semanticsWidgets = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((s) => s.properties.label != null)
          .toList();

      final labels = semanticsWidgets.map((s) => s.properties.label).toSet();
      expect(labels, contains('Short Story'));
      expect(labels, contains('Full Story'));
      expect(labels, contains('Long Story'));
    });
  });
}
