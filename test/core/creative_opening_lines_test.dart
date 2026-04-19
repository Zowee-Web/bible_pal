import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/core/creative_opening_lines.dart';
import 'package:bible_pal/services/pal_audio_service.dart';
import 'package:bible_pal/core/pal_voice_registry.dart';

void main() {
  late Map<String, dynamic> moodsData;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final jsonStr = await rootBundle
        .loadString('assets/pal/creative_opening_lines.json');
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    moodsData = data['moods'] as Map<String, dynamic>;
  });

  group('Creative Opening Lines — JSON structure', () {
    test('has version field', () async {
      final jsonStr = await rootBundle
          .loadString('assets/pal/creative_opening_lines.json');
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

    test('each mood has 2-4 lines', () {
      for (final entry in moodsData.entries) {
        final lines = entry.value as List<dynamic>;
        expect(lines.length, inInclusiveRange(2, 4),
            reason: '${entry.key} has ${lines.length} lines');
      }
    });

    test('all lines are objects with id and text', () {
      for (final entry in moodsData.entries) {
        for (final line in entry.value as List<dynamic>) {
          final obj = line as Map<String, dynamic>;
          expect(obj['id'], isA<String>());
          expect((obj['id'] as String).isNotEmpty, true);
          expect(obj['text'], isA<String>());
          expect((obj['text'] as String).isNotEmpty, true);
        }
      }
    });

    test('all IDs follow CREATIVE_{MOOD}_{NN} convention', () {
      for (final entry in moodsData.entries) {
        final moodUpper = entry.key.toUpperCase();
        for (final line in entry.value as List<dynamic>) {
          final id = (line as Map<String, dynamic>)['id'] as String;
          expect(id, startsWith('CREATIVE_${moodUpper}_'),
              reason: 'ID "$id" does not match mood "${entry.key}"');
        }
      }
    });

    test('all IDs are unique', () {
      final ids = <String>{};
      for (final entry in moodsData.entries) {
        for (final line in entry.value as List<dynamic>) {
          final id = (line as Map<String, dynamic>)['id'] as String;
          expect(ids.add(id), true, reason: 'Duplicate ID: $id');
        }
      }
    });
  });

  group('Creative Opening Lines — content safety', () {
    test('no Scripture-like language', () {
      final banned = [
        'saith', 'thus saith', 'the lord said', 'verse',
        'chapter', 'psalm', 'proverbs', 'genesis', 'exodus',
        'matthew', 'mark', 'luke', 'john', 'acts',
      ];
      final violations = <String>[];
      for (final entry in moodsData.entries) {
        for (final line in entry.value as List<dynamic>) {
          final text = (line as Map<String, dynamic>)['text'] as String;
          final lower = text.toLowerCase();
          for (final b in banned) {
            if (lower.contains(b)) {
              violations.add('${entry.key}: "$text" contains "$b"');
            }
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'Scripture-like language:\n${violations.join('\n')}');
    });

    test('no Bible character names', () {
      final banned = [
        'jesus', 'moses', 'david', 'abraham', 'joseph', 'peter',
        'paul', 'mary', 'noah', 'elijah', 'isaiah', 'daniel',
      ];
      final violations = <String>[];
      for (final entry in moodsData.entries) {
        for (final line in entry.value as List<dynamic>) {
          final text = (line as Map<String, dynamic>)['text'] as String;
          final lower = text.toLowerCase();
          for (final b in banned) {
            if (lower.contains(b)) {
              violations.add('${entry.key}: "$text" contains "$b"');
            }
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'Bible characters found:\n${violations.join('\n')}');
    });
  });

  group('Creative Opening Lines — Dart loader', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      CreativeOpeningLines.resetForTesting();
    });

    test('ensureLoaded() populates moods', () async {
      await CreativeOpeningLines.ensureLoaded();
      expect(CreativeOpeningLines.moods, isNotEmpty);
      expect(CreativeOpeningLines.moods.length, 8);
    });

    test('getLine returns non-null for each mood', () async {
      await CreativeOpeningLines.ensureLoaded();
      for (final mood in CreativeOpeningLines.moods) {
        final line = CreativeOpeningLines.getLine(mood);
        expect(line, isNotNull, reason: '$mood returned null');
        expect(line!.isNotEmpty, true);
      }
    });

    test('getLineRef returns PalLineRef with id and text', () async {
      await CreativeOpeningLines.ensureLoaded();
      final ref = CreativeOpeningLines.getLineRef('weary');
      expect(ref, isNotNull);
      expect(ref!.id, startsWith('CREATIVE_WEARY_'));
      expect(ref.text.isNotEmpty, true);
    });

    test('getLine returns null for null mood', () async {
      await CreativeOpeningLines.ensureLoaded();
      expect(CreativeOpeningLines.getLine(null), isNull);
    });

    test('getLine returns null for unknown mood', () async {
      await CreativeOpeningLines.ensureLoaded();
      expect(CreativeOpeningLines.getLine('nonexistent'), isNull);
    });

    test('audio asset paths are valid for all voices', () async {
      await CreativeOpeningLines.ensureLoaded();
      final ref = CreativeOpeningLines.getLineRef('anxious');
      expect(ref, isNotNull);
      for (final voice in PalVoiceRegistry.voices) {
        final path = PalAudioService.assetPath(voice.voiceKey, ref!.id);
        expect(path, endsWith('.mp3'));
        expect(path, contains(voice.voiceKey));
        expect(path, contains('CREATIVE_ANXIOUS_'));
      }
    });
  });
}
