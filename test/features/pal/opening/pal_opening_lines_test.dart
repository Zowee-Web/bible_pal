import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/pal/opening/pal_opening_lines.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Library integrity (Feature 2.0 — time-bucketed opening greeting)
  // ---------------------------------------------------------------------------

  group('opening library integrity', () {
    test('exactly 12 entries', () {
      expect(palOpeningLines.length, equals(12));
    });

    test('all text non-empty', () {
      for (final line in palOpeningLines) {
        expect(
          line.text.trim().isNotEmpty,
          isTrue,
          reason: 'Found empty text in entry: $line',
        );
      }
    });

    test('all text unique', () {
      final texts = palOpeningLines.map((l) => l.text).toList();
      final unique = texts.toSet();
      expect(
        unique.length,
        equals(texts.length),
        reason: 'Duplicate lines found',
      );
    });

    test('valid OpeningTimeBucket on every line', () {
      for (final line in palOpeningLines) {
        expect(
          OpeningTimeBucket.values.contains(line.bucket),
          isTrue,
          reason: 'Invalid bucket on: ${line.text}',
        );
      }
    });

    test('valid OpeningLineType on every line', () {
      for (final line in palOpeningLines) {
        expect(
          OpeningLineType.values.contains(line.type),
          isTrue,
          reason: 'Invalid type on: ${line.text}',
        );
      }
    });

    test('exactly 3 lines per time bucket', () {
      for (final bucket in OpeningTimeBucket.values) {
        final count = palOpeningLines.where((l) => l.bucket == bucket).length;
        expect(
          count,
          equals(3),
          reason: 'Bucket ${bucket.name} has $count lines, expected 3',
        );
      }
    });

    test('covers all 4 time buckets', () {
      final buckets = palOpeningLines.map((l) => l.bucket).toSet();
      expect(buckets, containsAll(OpeningTimeBucket.values));
    });
  });

  // ---------------------------------------------------------------------------
  // ID convention (matches asset filenames at assets/pal/audio/{voice}/{id}.mp3)
  // ---------------------------------------------------------------------------

  group('opening line IDs', () {
    test('all IDs non-empty and unique', () {
      final ids = <String>{};
      for (final line in palOpeningLines) {
        expect(line.id.trim().isNotEmpty, isTrue);
        expect(ids.add(line.id), isTrue, reason: 'Duplicate ID: ${line.id}');
      }
    });

    test('IDs follow OPENING_{BUCKET}_{NN} convention and match bucket', () {
      const bucketCode = {
        OpeningTimeBucket.morning: 'MORN',
        OpeningTimeBucket.afternoon: 'AFTN',
        OpeningTimeBucket.evening: 'EVEN',
        OpeningTimeBucket.night: 'NIGHT',
      };
      for (final line in palOpeningLines) {
        final code = bucketCode[line.bucket];
        expect(line.id, startsWith('OPENING_${code}_'),
            reason:
                'ID "${line.id}" does not match bucket "${line.bucket.name}"');
        final parts = line.id.split('_');
        final suffix = parts.last;
        expect(suffix.length, 2,
            reason: 'ID "${line.id}" suffix is not 2 digits');
        expect(int.tryParse(suffix), isNotNull,
            reason: 'ID "${line.id}" suffix is not numeric');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Time-bucket boundary mapping
  // ---------------------------------------------------------------------------

  group('bucketForHour', () {
    test('night covers 22:00–04:59 inclusive', () {
      for (final hour in [22, 23, 0, 1, 2, 3, 4]) {
        expect(bucketForHour(hour), OpeningTimeBucket.night,
            reason: 'hour=$hour should be night');
      }
    });

    test('morning covers 05:00–11:59 inclusive', () {
      for (final hour in [5, 6, 8, 11]) {
        expect(bucketForHour(hour), OpeningTimeBucket.morning,
            reason: 'hour=$hour should be morning');
      }
    });

    test('afternoon covers 12:00–16:59 inclusive', () {
      for (final hour in [12, 13, 15, 16]) {
        expect(bucketForHour(hour), OpeningTimeBucket.afternoon,
            reason: 'hour=$hour should be afternoon');
      }
    });

    test('evening covers 17:00–21:59 inclusive', () {
      for (final hour in [17, 18, 20, 21]) {
        expect(bucketForHour(hour), OpeningTimeBucket.evening,
            reason: 'hour=$hour should be evening');
      }
    });

    test('every hour 0–23 maps to a bucket', () {
      for (var h = 0; h < 24; h++) {
        final b = bucketForHour(h);
        expect(OpeningTimeBucket.values.contains(b), isTrue);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // linesForBucket
  // ---------------------------------------------------------------------------

  group('linesForBucket', () {
    test('returns exactly 3 lines for each bucket', () {
      for (final bucket in OpeningTimeBucket.values) {
        expect(linesForBucket(bucket).length, 3);
      }
    });

    test('returned lines all match the requested bucket', () {
      for (final bucket in OpeningTimeBucket.values) {
        for (final line in linesForBucket(bucket)) {
          expect(line.bucket, bucket);
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // No-inference content guardrail (durable lint)
  // ---------------------------------------------------------------------------

  group('no pre-input emotional inference', () {
    // The opening greeting must be mood-blind. These keywords presupposed
    // the user's emotional state in the retired 60-line library — they
    // must never reappear.
    const forbiddenKeywords = [
      'tired',
      'heavy',
      'weighing',
      'weighed',
      'draining',
      'drained',
      'exhausting',
      'exhausted',
      'bright spot',
      'glad happened',
      'worth holding',
      'really doing',
      'carry it alone',
      'pressing on',
      'pulling at',
      'hard to shake',
      'wearing on',
    ];

    test('no opening line contains a forbidden inference keyword', () {
      for (final line in palOpeningLines) {
        final lower = line.text.toLowerCase();
        for (final kw in forbiddenKeywords) {
          expect(
            lower.contains(kw),
            isFalse,
            reason:
                'Line "${line.text}" (id=${line.id}) contains forbidden keyword "$kw" — opening must be mood-blind.',
          );
        }
      }
    });

    test('no opening line starts with presupposed-knowledge prefix', () {
      const forbiddenPrefixes = ['You are', 'You feel', 'I know you', 'You sound'];
      for (final line in palOpeningLines) {
        for (final prefix in forbiddenPrefixes) {
          expect(
            line.text.startsWith(prefix),
            isFalse,
            reason:
                'Line "${line.text}" starts with presupposed-knowledge prefix "$prefix"',
          );
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Mood screen passive placeholder rotation (Feature 2.0 sub-section)
  // ---------------------------------------------------------------------------

  group('buildShuffledOpeningLineTexts', () {
    test('returns the full library size', () {
      final pool = buildShuffledOpeningLineTexts(random: Random(1));
      expect(pool.length, equals(palOpeningLines.length));
    });

    test('returns the full library with no additional strings', () {
      final pool = buildShuffledOpeningLineTexts(random: Random(2));
      final libraryTexts = palOpeningLines.map((l) => l.text).toSet();
      expect(pool.toSet(), equals(libraryTexts));
    });

    test('contains no old hardcoded placeholder strings', () {
      const oldPlaceholders = [
        'Tell me how you’re feeling…',
        'What’s on your heart today?',
        'How are you starting your day?',
        'What are you grateful for today?',
        'How’s your spirit doing?',
        'What’s on your heart tonight?',
        'How did your day go?',
        'What’s ahead for you today?',
        'What’s on your mind tonight?',
        'What’s weighing on you?',
        'Anything you need to lay down today?',
      ];
      final pool = buildShuffledOpeningLineTexts(random: Random(3));
      for (final old in oldPlaceholders) {
        expect(
          pool,
          isNot(contains(old)),
          reason:
              'Old placeholder "$old" must not appear in the mood screen rotation pool',
        );
      }
    });

    test('deterministic under seeded Random', () {
      final a = buildShuffledOpeningLineTexts(random: Random(42));
      final b = buildShuffledOpeningLineTexts(random: Random(42));
      expect(a, equals(b));
    });

    test('avoidFirst moves matching first element out of index 0', () {
      final base = buildShuffledOpeningLineTexts(random: Random(42));
      final target = base.first;
      final guarded = buildShuffledOpeningLineTexts(
        random: Random(42),
        avoidFirst: target,
      );
      expect(
        guarded.first,
        isNot(equals(target)),
        reason: 'avoidFirst="$target" still appeared at index 0',
      );
      expect(guarded, contains(target));
    });

    test('avoidFirst has no effect when first element already differs', () {
      final base = buildShuffledOpeningLineTexts(random: Random(7));
      final notFirst = base[5];
      final guarded = buildShuffledOpeningLineTexts(
        random: Random(7),
        avoidFirst: notFirst,
      );
      expect(guarded, equals(base));
    });

    test('full cycle visits every line before any repeat', () {
      final pool = buildShuffledOpeningLineTexts(random: Random(11));
      final seen = <String>{};
      for (final line in pool) {
        expect(
          seen.contains(line),
          isFalse,
          reason: 'Line "$line" appeared twice before cycle wrap',
        );
        seen.add(line);
      }
      expect(seen.length, equals(palOpeningLines.length));
    });
  });
}
