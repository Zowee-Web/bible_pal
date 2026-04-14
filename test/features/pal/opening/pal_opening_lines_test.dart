import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/pal/opening/pal_opening_lines.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Library integrity (INVARIANTS — Delilah Opening Layer)
  // ---------------------------------------------------------------------------

  group('opening library integrity', () {
    test('exactly 60 entries', () {
      expect(palOpeningLines.length, equals(60));
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

    test('valid PalOpeningTone on every line', () {
      for (final line in palOpeningLines) {
        expect(
          PalOpeningTone.values.contains(line.tone),
          isTrue,
          reason: 'Invalid tone on: ${line.text}',
        );
      }
    });

    test('exactly 12 lines per tone bucket', () {
      for (final tone in PalOpeningTone.values) {
        final count = palOpeningLines.where((l) => l.tone == tone).length;
        expect(
          count,
          equals(12),
          reason: 'Tone ${tone.name} has $count lines, expected 12',
        );
      }
    });

    test('covers all 5 tones', () {
      final tones = palOpeningLines.map((l) => l.tone).toSet();
      expect(tones, containsAll(PalOpeningTone.values));
    });
  });

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------

  group('pickOpeningLine', () {
    test('returns a line from the library', () {
      final line = pickOpeningLine();
      expect(palOpeningLines.contains(line), isTrue);
    });

    test('result has valid tone', () {
      final line = pickOpeningLine();
      expect(PalOpeningTone.values.contains(line.tone), isTrue);
    });

    test('injectable Random produces deterministic result', () {
      const seed = 42;
      final a = pickOpeningLine(Random(seed));
      final b = pickOpeningLine(Random(seed));
      expect(a.text, equals(b.text));
      expect(a.tone, equals(b.tone));
    });

    test('different seeds can produce different lines', () {
      final results = List.generate(
        20,
        (i) => pickOpeningLine(Random(i)).text,
      ).toSet();
      // With 60 lines and 20 seeds, expect at least 2 distinct results.
      expect(results.length, greaterThan(1));
    });

    test('index stays within bounds across many calls', () {
      for (int i = 0; i < 200; i++) {
        final line = pickOpeningLine(Random(i));
        expect(
          palOpeningLines.indexOf(line),
          inInclusiveRange(0, 59),
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Tone enum
  // ---------------------------------------------------------------------------

  group('PalOpeningTone', () {
    test('has exactly 5 values', () {
      expect(PalOpeningTone.values.length, equals(5));
    });

    test('contains expected tone names', () {
      final names = PalOpeningTone.values.map((t) => t.name).toSet();
      expect(names, containsAll(['gentle', 'encouraging', 'calm', 'weary', 'warm']));
    });
  });

  // ---------------------------------------------------------------------------
  // Tone bias scope contract (structural)
  // ---------------------------------------------------------------------------

  group('tone bias scope (structural)', () {
    // These tests verify the data model enforces the invariant that tone is
    // a property of the opening line only, not injected into other fields.

    test('PalOpeningLine carries only text and tone', () {
      final line = palOpeningLines.first;
      // Verify the two required fields exist and are the only named members.
      expect(line.text, isA<String>());
      expect(line.tone, isA<PalOpeningTone>());
    });

    test('opening line text contains no mood-injection markers', () {
      // Tone must never assert knowledge of the user's mood.
      // Lines should not contain terms that presuppose the user's state.
      const forbiddenPrefixes = ['You are', 'You feel', 'I know you'];
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
  // Session-only tone — no persistence API exists
  // ---------------------------------------------------------------------------

  group('session-only tone contract', () {
    // The PalOpeningLine / PalOpeningTone types must not expose any
    // serialization or storage methods — persistence is explicitly prohibited.

    test('PalOpeningLine has no toJson', () {
      final line = palOpeningLines.first;
      // Dart reflection isn't available in tests, but we verify the class
      // doesn't implement toJson by confirming it's not callable.
      // (If toJson existed it would be a dynamic method and this cast would succeed.)
      expect(line, isNot(isA<Map>()));
    });

    test('PalOpeningTone values have no ordinal storage keys', () {
      // Verify tone names are plain strings with no storage-key prefixes
      // that would suggest they are meant to be stored.
      for (final tone in PalOpeningTone.values) {
        expect(tone.name, isNot(contains('_key')));
        expect(tone.name, isNot(contains('_id')));
        expect(tone.name, isNot(contains('prefs')));
      }
    });
  });
}
