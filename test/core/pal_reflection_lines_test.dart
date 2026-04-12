import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/pal_reflection_lines.dart';

void main() {
  late Map<String, dynamic> moodsData;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final jsonStr =
        await rootBundle.loadString('assets/pal/pal_reflection_lines.json');
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    moodsData = data['moods'] as Map<String, dynamic>;
  });

  group('PAL Reflection Lines — structure', () {
    test('has version field', () async {
      final jsonStr =
          await rootBundle.loadString('assets/pal/pal_reflection_lines.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(data['version'], isA<int>());
    });

    test('covers all 8 app moods', () {
      const expectedMoods = [
        'joyful', 'grateful', 'weary', 'anxious',
        'hurting', 'brave_courage', 'calm_peaceful', 'encouraging',
      ];
      for (final mood in expectedMoods) {
        expect(moodsData.containsKey(mood), true,
            reason: 'Missing mood: $mood');
      }
    });

    test('each mood has 3-4 lines', () {
      for (final entry in moodsData.entries) {
        final lines = entry.value as List<dynamic>;
        expect(lines.length, inInclusiveRange(3, 4),
            reason: '${entry.key} has ${lines.length} lines (expected 3-4)');
      }
    });

    test('all lines are non-empty strings', () {
      for (final entry in moodsData.entries) {
        for (final line in entry.value as List<dynamic>) {
          expect(line, isA<String>());
          expect((line as String).isNotEmpty, true,
              reason: '${entry.key} has empty line');
        }
      }
    });

    test('all lines are <= 80 characters', () {
      final violations = <String>[];
      for (final entry in moodsData.entries) {
        for (final line in entry.value as List<dynamic>) {
          if ((line as String).length > 80) {
            violations.add('${entry.key}: "$line" (${line.length} chars)');
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'Lines over 80 chars:\n${violations.join('\n')}');
    });
  });

  group('PAL Reflection Lines — tone', () {
    test('no line contains banned patterns', () {
      final banned = [
        'you should', 'you must', 'the lesson is', 'what this means is',
        'god wants you', 'god needs you',
      ];
      final violations = <String>[];
      for (final entry in moodsData.entries) {
        for (final line in entry.value as List<dynamic>) {
          final lower = (line as String).toLowerCase();
          for (final pattern in banned) {
            if (lower.contains(pattern)) {
              violations.add('${entry.key}: "$line" contains "$pattern"');
            }
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'Banned patterns found:\n${violations.join('\n')}');
    });
  });

  group('PAL Reflection Lines — Dart loader', () {
    setUp(() {
      PalReflectionLines.resetForTesting();
    });

    test('ensureLoaded() populates moods', () async {
      await PalReflectionLines.ensureLoaded();
      expect(PalReflectionLines.moods, isNotEmpty);
      expect(PalReflectionLines.moods.length, 8);
    });

    test('ensureLoaded() is idempotent', () async {
      await PalReflectionLines.ensureLoaded();
      final count1 = PalReflectionLines.moods.length;
      await PalReflectionLines.ensureLoaded();
      expect(PalReflectionLines.moods.length, count1);
    });

    test('getLine returns null for null mood', () async {
      await PalReflectionLines.ensureLoaded();
      expect(PalReflectionLines.getLine(null), isNull);
    });

    test('getLine returns null for unknown mood', () async {
      await PalReflectionLines.ensureLoaded();
      expect(PalReflectionLines.getLine('nonexistent'), isNull);
    });

    test('getLine returns a string for each known mood', () async {
      await PalReflectionLines.ensureLoaded();
      for (final mood in PalReflectionLines.moods) {
        final line = PalReflectionLines.getLine(mood);
        expect(line, isNotNull, reason: '$mood returned null');
        expect(line!.isNotEmpty, true, reason: '$mood returned empty');
      }
    });

    test('linesForMood returns correct count', () async {
      await PalReflectionLines.ensureLoaded();
      final lines = PalReflectionLines.linesForMood('hurting');
      expect(lines.length, inInclusiveRange(3, 4));
    });
  });
}
