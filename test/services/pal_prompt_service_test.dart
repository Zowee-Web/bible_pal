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

  group('PalPromptService.getNeutralCheckInPrompt', () {
    // Cold-open contract: time-aware, varied, never probing. A curated
    // pool per time window is drawn from with anti-repeat. Every line in
    // every pool must (a) match an existing pre-bundled audio file across
    // all active PAL voices and (b) pass the forbidden-token guard.

    PalPromptService neutralServiceForHour(int hour, {int seed = 0}) {
      return PalPromptService(
        now: () => DateTime(2025, 1, 1, hour, 0),
        random: Random(seed),
      );
    }

    const expectedTimeWindows = {
      5: 'morning',
      11: 'morning',
      12: 'afternoon',
      16: 'afternoon',
      17: 'evening',
      21: 'evening',
      22: 'lateNight',
      4: 'lateNight',
      0: 'lateNight',
    };

    for (final entry in expectedTimeWindows.entries) {
      test('hour ${entry.key} -> time window ${entry.value}', () {
        final prompt = neutralServiceForHour(entry.key).getNeutralCheckInPrompt();
        expect(prompt.timeWindow, entry.value);
        expect(prompt.category, 'neutral_check_in');
        expect(prompt.id, isNotEmpty);
        expect(prompt.text, isNotEmpty);
      });
    }

    // The forbidden-token guard is the locked principle from
    // feedback_pal_cold_open_neutrality.md. If it ever fails, the cold-open
    // pool has drifted into emotionally presumptive territory.
    final forbiddenTokens = [
      'heavy',
      'burden',
      'carrying',
      'hurt',
      'weighing',
      'pressure',
      'worry',
      'tired',
      'restless',
      'stressful',
    ];

    test('every line in every time window pool passes forbidden-token guard',
        () {
      // Drive the service across many seeds + a full ring per time window
      // so we exercise every pool entry at least once.
      for (final hour in [8, 14, 19, 23]) {
        for (int seed = 0; seed < 100; seed++) {
          final service = neutralServiceForHour(hour, seed: seed);
          // Pick 10× the largest pool size to guarantee coverage + reset
          // cycles.
          for (int i = 0; i < 50; i++) {
            final text =
                service.getNeutralCheckInPrompt().text.toLowerCase();
            for (final token in forbiddenTokens) {
              expect(text.contains(token), false,
                  reason: 'Hour $hour seed $seed pick $i — pool line '
                      '"$text" contains forbidden token "$token". See '
                      'feedback_pal_cold_open_neutrality.md');
            }
          }
        }
      }
    });

    test('anti-repeat: no duplicate within a single ring', () {
      // For each time window, pick (poolSize) consecutive prompts and
      // assert all IDs are unique.
      // Pool sizes per time window (strict "how's your X" subset):
      //   morning=4, afternoon=3, evening=3, lateNight=2.
      const poolSizesByHour = {8: 4, 14: 3, 19: 3, 23: 2};
      for (final entry in poolSizesByHour.entries) {
        final service = neutralServiceForHour(entry.key, seed: 1);
        final picks = <String>{};
        for (int i = 0; i < entry.value; i++) {
          picks.add(service.getNeutralCheckInPrompt().id);
        }
        expect(picks.length, entry.value,
            reason:
                'Hour ${entry.key}: expected ${entry.value} unique IDs in a '
                'single ring, got ${picks.length}: $picks');
      }
    });

    test('ring resets after exhaustion (pool.length + 1 picks succeed)', () {
      for (final hour in [8, 14, 19, 23]) {
        final service = neutralServiceForHour(hour, seed: 7);
        // Exhaust the pool then pick once more.
        for (int i = 0; i < 6; i++) {
          final prompt = service.getNeutralCheckInPrompt();
          expect(prompt.id, isNotEmpty);
        }
      }
    });

    test('every hour 0-23 produces a non-empty neutral prompt', () {
      for (int h = 0; h < 24; h++) {
        final prompt = neutralServiceForHour(h).getNeutralCheckInPrompt();
        expect(prompt.text.isNotEmpty, true,
            reason: 'Hour $h returned empty text');
        expect(prompt.category, 'neutral_check_in',
            reason: 'Hour $h has wrong category');
      }
    });

    test('all pool IDs follow the DAY-bucket audio naming convention', () {
      // Sanity guard: cold-open audio IDs must look like
      // {prefix}_DAY_{NN}, where prefix ∈ {MORNING, AFT, EVE, LN}.
      // This catches accidental drift into BURDEN/HEART/GRAT buckets.
      final allowedPrefixes = ['MORNING_DAY_', 'AFT_DAY_', 'EVE_DAY_', 'LN_DAY_'];
      for (final hour in [8, 14, 19, 23]) {
        for (int seed = 0; seed < 30; seed++) {
          final service = neutralServiceForHour(hour, seed: seed);
          for (int i = 0; i < 30; i++) {
            final id = service.getNeutralCheckInPrompt().id;
            final ok = allowedPrefixes.any((p) => id.startsWith(p));
            expect(ok, true,
                reason:
                    'Cold-open ID "$id" does not match an allowed DAY-bucket '
                    'prefix. Hour $hour seed $seed pick $i.');
          }
        }
      }
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
