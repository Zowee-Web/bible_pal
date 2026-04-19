import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/core/pal_transition_lines.dart';

void main() {
  late List<dynamic> lines;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final jsonStr =
        await rootBundle.loadString('assets/pal/pal_transition_lines.json');
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    lines = data['lines'] as List<dynamic>;
  });

  group('PAL Transition Lines — structure', () {
    test('has version field', () async {
      final jsonStr =
          await rootBundle.loadString('assets/pal/pal_transition_lines.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(data['version'], isA<int>());
    });

    test('has at least 10 lines', () {
      expect(lines.length, greaterThanOrEqualTo(10));
    });

    test('all lines are objects with id and text', () {
      for (final line in lines) {
        final obj = line as Map<String, dynamic>;
        expect(obj['id'], isA<String>());
        expect((obj['id'] as String).isNotEmpty, true);
        expect(obj['text'], isA<String>());
        expect((obj['text'] as String).isNotEmpty, true);
      }
    });

    test('all line IDs follow TRANS_{NN} convention', () {
      for (final line in lines) {
        final id = (line as Map<String, dynamic>)['id'] as String;
        expect(id, matches(RegExp(r'^TRANS_\d{2}$')),
            reason: 'ID "$id" does not match TRANS_NN pattern');
      }
    });

    test('all line IDs are unique', () {
      final ids = <String>{};
      for (final line in lines) {
        final id = (line as Map<String, dynamic>)['id'] as String;
        expect(ids.add(id), true, reason: 'Duplicate ID: $id');
      }
    });

    test('all texts are <= 65 characters (shorter than framing lines)', () {
      final violations = <String>[];
      for (final line in lines) {
        final text = (line as Map<String, dynamic>)['text'] as String;
        if (text.length > 65) {
          violations.add('"$text" (${text.length} chars)');
        }
      }
      expect(violations, isEmpty,
          reason: 'Transition lines over 65 chars:\n${violations.join('\n')}');
    });

    test('no duplicate texts', () {
      final texts = lines
          .map((l) => (l as Map<String, dynamic>)['text'] as String)
          .toSet();
      expect(texts.length, lines.length,
          reason: 'Duplicate transition lines found');
    });
  });

  group('PAL Transition Lines — tone', () {
    test('no line contains banned prescriptive patterns', () {
      final banned = [
        'god wants you',
        'god needs you',
        'you should',
        'you must',
        'the lesson is',
        'what this means is',
      ];
      final violations = <String>[];
      for (final line in lines) {
        final text = (line as Map<String, dynamic>)['text'] as String;
        final lower = text.toLowerCase();
        for (final pattern in banned) {
          if (lower.contains(pattern)) {
            violations.add('"$text" contains "$pattern"');
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'Banned patterns found:\n${violations.join('\n')}');
    });
  });

  group('PAL Transition Lines — Dart loader', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PalTransitionLines.resetForTesting();
    });

    test('ensureLoaded() populates lines', () async {
      await PalTransitionLines.ensureLoaded();
      expect(PalTransitionLines.lines, isNotEmpty);
    });

    test('ensureLoaded() is idempotent', () async {
      await PalTransitionLines.ensureLoaded();
      final count1 = PalTransitionLines.lines.length;
      await PalTransitionLines.ensureLoaded();
      expect(PalTransitionLines.lines.length, count1);
    });

    test('getLine returns null for null key', () async {
      await PalTransitionLines.ensureLoaded();
      expect(PalTransitionLines.getLine(null), isNull);
    });

    test('getLine returns a string for any key', () async {
      await PalTransitionLines.ensureLoaded();
      final line = PalTransitionLines.getLine('joseph_sold_by_brothers');
      expect(line, isNotNull);
      expect(line, isA<String>());
      expect(line!.isNotEmpty, true);
    });

    test('getLine returns different lines for different keys', () async {
      await PalTransitionLines.ensureLoaded();
      // With 12 lines, different story keys should hash to different indices
      final results = <String>{};
      final keys = [
        'joseph_sold_by_brothers',
        'david_anointed',
        'rest_for_the_weary',
        'burning_bush',
        'job_tested',
        'ruth_gleans_in_boaz_field',
      ];
      for (final key in keys) {
        results.add(PalTransitionLines.getLine(key)!);
      }
      // At least some variation (not all the same line)
      expect(results.length, greaterThan(1),
          reason: 'All keys returned the same transition line');
    });

    test('getLineRef returns PalLineRef with id and text', () async {
      await PalTransitionLines.ensureLoaded();
      final ref =
          PalTransitionLines.getLineRef('joseph_sold_by_brothers');
      expect(ref, isNotNull);
      expect(ref!.id, startsWith('TRANS_'));
      expect(ref.text.isNotEmpty, true);
    });

    test('getLineRef and getLine return consistent text', () async {
      await PalTransitionLines.ensureLoaded();
      final ref =
          PalTransitionLines.getLineRef('joseph_sold_by_brothers');
      expect(ref, isNotNull);
      expect(PalTransitionLines.lines, contains(ref!.text));
    });
  });
}
