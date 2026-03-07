import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/pal_voice_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pal_lines.json v2 structure', () {
    late Map<String, dynamic> data;

    setUpAll(() async {
      final jsonStr =
          await rootBundle.loadString('assets/pal/pal_lines.json');
      data = jsonDecode(jsonStr) as Map<String, dynamic>;
    });

    test('version is 2', () {
      expect(data['version'], 2);
    });

    test('has onboarding lines', () {
      final onboarding = data['onboarding'] as List<dynamic>;
      expect(onboarding.isNotEmpty, true);
      for (final item in onboarding) {
        expect(item['id'], isNotNull);
        expect(item['text'], isNotNull);
        expect((item['text'] as String).isNotEmpty, true);
      }
    });

    test('has preview lines', () {
      final preview = data['preview'] as List<dynamic>;
      expect(preview.isNotEmpty, true);
      for (final item in preview) {
        expect(item['id'], isNotNull);
        expect(item['text'], isNotNull);
      }
    });

    // --- Creep-back prevention ---
    test('does NOT contain "greetings" key', () {
      expect(data.containsKey('greetings'), false,
          reason: 'PAL V2 removed greetings — creep-back detected');
    });

    test('does NOT contain "compassionateReplies" key', () {
      expect(data.containsKey('compassionateReplies'), false,
          reason:
              'PAL V2 removed compassionateReplies — creep-back detected');
    });

    // --- Prompts ---
    test('has 16 prompt buckets (4 time windows x 4 categories)', () {
      final prompts = data['prompts'] as Map<String, dynamic>;
      expect(prompts.length, 16);
    });

    test('each prompt bucket has exactly 6 lines', () {
      final prompts = data['prompts'] as Map<String, dynamic>;
      for (final entry in prompts.entries) {
        final lines = entry.value as List<dynamic>;
        expect(lines.length, 6,
            reason: 'Bucket "${entry.key}" should have 6 lines');
      }
    });

    test('total prompt count is 96', () {
      final prompts = data['prompts'] as Map<String, dynamic>;
      int total = 0;
      for (final bucket in prompts.values) {
        total += (bucket as List<dynamic>).length;
      }
      expect(total, 96);
    });

    test('prompt bucket keys follow timeWindow_category naming', () {
      final prompts = data['prompts'] as Map<String, dynamic>;
      const expectedBuckets = [
        'morning_day',
        'morning_heart',
        'morning_burden',
        'morning_gratitude',
        'afternoon_day',
        'afternoon_heart',
        'afternoon_burden',
        'afternoon_gratitude',
        'evening_day',
        'evening_heart',
        'evening_burden',
        'evening_gratitude',
        'lateNight_day',
        'lateNight_heart',
        'lateNight_burden',
        'lateNight_gratitude',
      ];
      for (final key in expectedBuckets) {
        expect(prompts.containsKey(key), true,
            reason: 'Missing prompt bucket: $key');
      }
    });

    test('all prompt IDs are unique', () {
      final prompts = data['prompts'] as Map<String, dynamic>;
      final allIds = <String>{};
      for (final bucket in prompts.values) {
        for (final line in bucket as List<dynamic>) {
          final id = line['id'] as String;
          expect(allIds.add(id), true,
              reason: 'Duplicate prompt ID: $id');
        }
      }
    });

    // --- Micro-responses ---
    test('has 5 micro-response mood buckets', () {
      final responses = data['microResponses'] as Map<String, dynamic>;
      expect(responses.length, 5);
    });

    test('micro-response bucket keys match mood IDs', () {
      final responses = data['microResponses'] as Map<String, dynamic>;
      const expectedMoods = [
        'joyful',
        'weary',
        'anxious',
        'hurting',
        'neutral',
      ];
      for (final mood in expectedMoods) {
        expect(responses.containsKey(mood), true,
            reason: 'Missing micro-response bucket: $mood');
      }
    });

    test('each micro-response bucket has exactly 6 lines', () {
      final responses = data['microResponses'] as Map<String, dynamic>;
      for (final entry in responses.entries) {
        final lines = entry.value as List<dynamic>;
        expect(lines.length, 6,
            reason:
                'Micro-response bucket "${entry.key}" should have 6 lines');
      }
    });

    test('total micro-response count is 30', () {
      final responses = data['microResponses'] as Map<String, dynamic>;
      int total = 0;
      for (final bucket in responses.values) {
        total += (bucket as List<dynamic>).length;
      }
      expect(total, 30);
    });

    test('all micro-response IDs are unique', () {
      final responses = data['microResponses'] as Map<String, dynamic>;
      final allIds = <String>{};
      for (final bucket in responses.values) {
        for (final line in bucket as List<dynamic>) {
          final id = line['id'] as String;
          expect(allIds.add(id), true,
              reason: 'Duplicate micro-response ID: $id');
        }
      }
    });

    test('micro-response IDs follow RESP_ naming convention', () {
      final responses = data['microResponses'] as Map<String, dynamic>;
      for (final bucket in responses.values) {
        for (final line in bucket as List<dynamic>) {
          final id = line['id'] as String;
          expect(id, startsWith('RESP_'),
              reason: 'Micro-response ID "$id" should start with RESP_');
        }
      }
    });

    test('all micro-responses are 12 words or fewer', () {
      final responses = data['microResponses'] as Map<String, dynamic>;
      final violations = <String>[];
      for (final entry in responses.entries) {
        for (final line in entry.value as List<dynamic>) {
          final id = line['id'] as String;
          final text = line['text'] as String;
          final wordCount = text.split(RegExp(r'\s+')).length;
          if (wordCount > 12) {
            violations.add('$id: $wordCount words ("$text")');
          }
        }
      }
      expect(violations, isEmpty,
          reason:
              'Micro-responses exceeding 12 words: ${violations.join(', ')}');
    });

    // --- No empty text ---
    test('no line text is empty', () {
      final preview = data['preview'] as List<dynamic>;
      final onboarding = data['onboarding'] as List<dynamic>;
      final prompts = data['prompts'] as Map<String, dynamic>;
      final responses = data['microResponses'] as Map<String, dynamic>;

      for (final item in [...preview, ...onboarding]) {
        expect((item['text'] as String).trim().isNotEmpty, true,
            reason: 'Line ${item['id']} has empty text');
      }
      for (final bucket in prompts.values) {
        for (final item in bucket as List<dynamic>) {
          expect((item['text'] as String).trim().isNotEmpty, true,
              reason: 'Prompt ${item['id']} has empty text');
        }
      }
      for (final bucket in responses.values) {
        for (final item in bucket as List<dynamic>) {
          expect((item['text'] as String).trim().isNotEmpty, true,
              reason: 'Micro-response ${item['id']} has empty text');
        }
      }
    });
  });

  group('PAL V2 audio asset paths', () {
    late Map<String, dynamic> data;

    setUpAll(() async {
      final jsonStr =
          await rootBundle.loadString('assets/pal/pal_lines.json');
      data = jsonDecode(jsonStr) as Map<String, dynamic>;
    });

    test('all expected asset paths are well-formed for all voices', () {
      final lineIds = <String>[];

      // Collect preview IDs
      final preview = data['preview'] as List<dynamic>;
      for (final item in preview) {
        lineIds.add(item['id'] as String);
      }

      // Collect prompt IDs
      final prompts = data['prompts'] as Map<String, dynamic>;
      for (final bucket in prompts.values) {
        for (final item in bucket as List<dynamic>) {
          lineIds.add(item['id'] as String);
        }
      }

      // Collect micro-response IDs
      final responses = data['microResponses'] as Map<String, dynamic>;
      for (final bucket in responses.values) {
        for (final item in bucket as List<dynamic>) {
          lineIds.add(item['id'] as String);
        }
      }

      // Verify path format for all voices x all lines
      for (final voice in PalVoiceRegistry.voices) {
        for (final lineId in lineIds) {
          final path = 'assets/pal/audio/${voice.voiceKey}/$lineId.mp3';
          expect(path, contains(voice.voiceKey));
          expect(path, endsWith('.mp3'));
          expect(path, isNot(contains(' ')),
              reason: 'Path should not contain spaces: $path');
        }
      }
    });
  });
}
