import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/pal_prompt_service.dart';

void main() {
  group('PalPromptService.getTimeWindow', () {
    test('maps all 24 hours to correct time windows', () {
      // Morning: 05:00–11:59
      for (int h = 5; h < 12; h++) {
        expect(PalPromptService.getTimeWindow(h), 'morning',
            reason: 'Hour $h should be morning');
      }

      // Afternoon: 12:00–16:59
      for (int h = 12; h < 17; h++) {
        expect(PalPromptService.getTimeWindow(h), 'afternoon',
            reason: 'Hour $h should be afternoon');
      }

      // Evening: 17:00–21:59
      for (int h = 17; h < 22; h++) {
        expect(PalPromptService.getTimeWindow(h), 'evening',
            reason: 'Hour $h should be evening');
      }

      // LateNight: 22:00–04:59
      for (int h = 22; h < 24; h++) {
        expect(PalPromptService.getTimeWindow(h), 'lateNight',
            reason: 'Hour $h should be lateNight');
      }
      for (int h = 0; h < 5; h++) {
        expect(PalPromptService.getTimeWindow(h), 'lateNight',
            reason: 'Hour $h should be lateNight');
      }
    });

    test('boundary hours are correct', () {
      expect(PalPromptService.getTimeWindow(4), 'lateNight');
      expect(PalPromptService.getTimeWindow(5), 'morning');
      expect(PalPromptService.getTimeWindow(11), 'morning');
      expect(PalPromptService.getTimeWindow(12), 'afternoon');
      expect(PalPromptService.getTimeWindow(16), 'afternoon');
      expect(PalPromptService.getTimeWindow(17), 'evening');
      expect(PalPromptService.getTimeWindow(21), 'evening');
      expect(PalPromptService.getTimeWindow(22), 'lateNight');
    });
  });

  group('PalPromptService weighted category distribution', () {
    test('morning weights favor day category', () async {
      await _verifyDistribution(
        timeWindow: 'morning',
        hour: 8,
        expectedWeights: {'day': 0.35, 'heart': 0.25, 'burden': 0.15, 'gratitude': 0.25},
      );
    });

    test('afternoon weights balance day and heart', () async {
      await _verifyDistribution(
        timeWindow: 'afternoon',
        hour: 14,
        expectedWeights: {'day': 0.30, 'heart': 0.30, 'burden': 0.25, 'gratitude': 0.15},
      );
    });

    test('evening weights favor heart and burden', () async {
      await _verifyDistribution(
        timeWindow: 'evening',
        hour: 19,
        expectedWeights: {'day': 0.20, 'heart': 0.35, 'burden': 0.30, 'gratitude': 0.15},
      );
    });

    test('lateNight weights heavily favor heart and burden', () async {
      await _verifyDistribution(
        timeWindow: 'lateNight',
        hour: 23,
        expectedWeights: {'day': 0.15, 'heart': 0.40, 'burden': 0.35, 'gratitude': 0.10},
      );
    });
  });

  group('PalPromptService non-repeat behavior', () {
    test('no repeats within a 6-line bucket until exhausted', () async {
      // Single bucket so all prompts come from morning_day
      final prompts = {'morning_day': _makeBucket('morning', 'day', 6)};
      final service = PalPromptService(
        now: () => DateTime(2025, 1, 1, 8, 0),
        random: Random(42),
      );
      service.initWithPrompts(prompts);

      // Draw all 6 lines — should all be unique
      final drawn = <String>{};
      for (int i = 0; i < 6; i++) {
        final prompt = await service.getPrompt();
        expect(drawn.add(prompt.id), true,
            reason: 'Draw $i should be unique, got duplicate: ${prompt.id}');
      }
      expect(drawn.length, 6);
    });

    test('ring resets after exhaustion and lines can repeat', () async {
      final prompts = {'morning_day': _makeBucket('morning', 'day', 6)};
      final service = PalPromptService(
        now: () => DateTime(2025, 1, 1, 8, 0),
        random: Random(42),
      );
      service.initWithPrompts(prompts);

      // Exhaust the bucket
      for (int i = 0; i < 6; i++) {
        await service.getPrompt();
      }

      // 7th draw should succeed (ring resets)
      final seventh = await service.getPrompt();
      expect(seventh.id, isNotEmpty);
    });
  });

  group('PalPromptService.getPrompt', () {
    test('returns valid PalPrompt for morning', () async {
      final service = _serviceForHour(8);
      final prompt = await service.getPrompt();
      expect(prompt.timeWindow, 'morning');
      expect(prompt.id, isNotEmpty);
      expect(prompt.text, isNotEmpty);
      expect(['day', 'heart', 'burden', 'gratitude'], contains(prompt.category));
    });

    test('returns valid PalPrompt for afternoon', () async {
      final service = _serviceForHour(14);
      final prompt = await service.getPrompt();
      expect(prompt.timeWindow, 'afternoon');
      expect(prompt.id, isNotEmpty);
      expect(prompt.text, isNotEmpty);
    });

    test('returns valid PalPrompt for evening', () async {
      final service = _serviceForHour(19);
      final prompt = await service.getPrompt();
      expect(prompt.timeWindow, 'evening');
      expect(prompt.id, isNotEmpty);
      expect(prompt.text, isNotEmpty);
    });

    test('returns valid PalPrompt for lateNight', () async {
      final service = _serviceForHour(23);
      final prompt = await service.getPrompt();
      expect(prompt.timeWindow, 'lateNight');
      expect(prompt.id, isNotEmpty);
      expect(prompt.text, isNotEmpty);
    });

    test('returns fallback prompt when no buckets loaded', () async {
      final service = PalPromptService(
        now: () => DateTime(2025, 1, 1, 8, 0),
        random: Random(0),
      );
      service.initWithPrompts({});
      final prompt = await service.getPrompt();
      expect(prompt.id, 'fallback');
      expect(prompt.text, 'How are you doing today?');
    });
  });

  group('PalPrompt data class', () {
    test('holds all fields correctly', () {
      const prompt = PalPrompt(
        id: 'MORNING_DAY_01',
        timeWindow: 'morning',
        category: 'day',
        text: 'How\'s your morning starting out?',
      );
      expect(prompt.id, 'MORNING_DAY_01');
      expect(prompt.timeWindow, 'morning');
      expect(prompt.category, 'day');
      expect(prompt.text, 'How\'s your morning starting out?');
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Verify weighted distribution within ±6% tolerance over 2000 iterations.
Future<void> _verifyDistribution({
  required String timeWindow,
  required int hour,
  required Map<String, double> expectedWeights,
}) async {
  const iterations = 2000;
  final counts = <String, int>{};
  for (final cat in expectedWeights.keys) {
    counts[cat] = 0;
  }

  // Build prompts with all 4 category buckets for this time window
  final prompts = <String, List<PalPrompt>>{};
  for (final cat in expectedWeights.keys) {
    prompts['${timeWindow}_$cat'] = _makeBucket(timeWindow, cat, 6);
  }

  for (int seed = 0; seed < iterations; seed++) {
    final service = PalPromptService(
      now: () => DateTime(2025, 1, 1, hour, 0),
      random: Random(seed),
    );
    service.initWithPrompts(prompts);

    final prompt = await service.getPrompt();
    counts[prompt.category] = (counts[prompt.category] ?? 0) + 1;
  }

  for (final entry in expectedWeights.entries) {
    final observed = counts[entry.key]! / iterations;
    final expected = entry.value;
    expect(
      (observed - expected).abs(),
      lessThan(0.06), // 6% tolerance
      reason:
          '$timeWindow ${entry.key}: expected ~${(expected * 100).toStringAsFixed(0)}%, '
          'got ${(observed * 100).toStringAsFixed(1)}%',
    );
  }
}

/// Build test prompts covering all 16 buckets.
Map<String, List<PalPrompt>> _buildTestPrompts() {
  final prompts = <String, List<PalPrompt>>{};
  const windows = ['morning', 'afternoon', 'evening', 'lateNight'];
  const categories = ['day', 'heart', 'burden', 'gratitude'];

  for (final tw in windows) {
    for (final cat in categories) {
      prompts['${tw}_$cat'] = _makeBucket(tw, cat, 6);
    }
  }
  return prompts;
}

/// Make a test bucket of prompts.
List<PalPrompt> _makeBucket(String timeWindow, String category, int count) {
  return List.generate(
    count,
    (i) => PalPrompt(
      id: '${timeWindow.toUpperCase()}_${category.toUpperCase()}_${(i + 1).toString().padLeft(2, '0')}',
      timeWindow: timeWindow,
      category: category,
      text: 'Test prompt $timeWindow $category ${i + 1}',
    ),
  );
}

/// Create a service pre-loaded with test prompts for a given hour.
PalPromptService _serviceForHour(int hour) {
  final service = PalPromptService(
    now: () => DateTime(2025, 1, 1, hour, 0),
    random: Random(42),
  );
  service.initWithPrompts(_buildTestPrompts());
  return service;
}
