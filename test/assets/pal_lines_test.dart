import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/pal_voice_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pal_lines.json structure', () {
    late Map<String, dynamic> data;

    setUpAll(() async {
      final jsonStr =
          await rootBundle.loadString('assets/pal/pal_lines.json');
      data = jsonDecode(jsonStr) as Map<String, dynamic>;
    });

    test('has version field', () {
      expect(data['version'], isA<int>());
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

    test('has 20 greetings', () {
      final greetings = data['greetings'] as List<dynamic>;
      expect(greetings.length, 20);
    });

    test('all greeting IDs follow naming convention', () {
      final greetings = data['greetings'] as List<dynamic>;
      for (final g in greetings) {
        final id = g['id'] as String;
        expect(id, matches(RegExp(r'^greeting_\d{2}$')),
            reason: 'Greeting ID "$id" should match greeting_XX format');
      }
    });

    test('all greeting IDs are unique', () {
      final greetings = data['greetings'] as List<dynamic>;
      final ids = greetings.map((g) => g['id'] as String).toSet();
      expect(ids.length, greetings.length);
    });

    test('greetings do not say "I\'m PAL"', () {
      final greetings = data['greetings'] as List<dynamic>;
      for (final g in greetings) {
        final text = (g['text'] as String).toLowerCase();
        expect(text.contains("i'm pal"), false,
            reason:
                'Greeting "${g['id']}" should not contain "I\'m PAL" — use relational language');
      }
    });

    test('has 15 positive compassionate replies', () {
      final replies = data['compassionateReplies'] as Map<String, dynamic>;
      final positive = replies['positive'] as List<dynamic>;
      expect(positive.length, 15);
    });

    test('has 15 neutral compassionate replies', () {
      final replies = data['compassionateReplies'] as Map<String, dynamic>;
      final neutral = replies['neutral'] as List<dynamic>;
      expect(neutral.length, 15);
    });

    test('has 15 negative compassionate replies', () {
      final replies = data['compassionateReplies'] as Map<String, dynamic>;
      final negative = replies['negative'] as List<dynamic>;
      expect(negative.length, 15);
    });

    test('all compassionate reply IDs are unique across buckets', () {
      final replies = data['compassionateReplies'] as Map<String, dynamic>;
      final allIds = <String>{};
      for (final bucket in ['positive', 'neutral', 'negative']) {
        final lines = replies[bucket] as List<dynamic>;
        for (final line in lines) {
          final id = line['id'] as String;
          expect(allIds.add(id), true,
              reason: 'Duplicate compassionate reply ID: $id');
        }
      }
    });

    test('compassionate reply IDs follow naming convention', () {
      final replies = data['compassionateReplies'] as Map<String, dynamic>;
      final expectedPrefixes = {
        'positive': 'comp_pos_',
        'neutral': 'comp_neu_',
        'negative': 'comp_neg_',
      };
      for (final bucket in expectedPrefixes.keys) {
        final lines = replies[bucket] as List<dynamic>;
        for (final line in lines) {
          final id = line['id'] as String;
          expect(id, startsWith(expectedPrefixes[bucket]!),
              reason: '$bucket reply ID "$id" should start with "${expectedPrefixes[bucket]}"');
        }
      }
    });

    test('no line text is empty', () {
      // Check all categories
      final greetings = data['greetings'] as List<dynamic>;
      final preview = data['preview'] as List<dynamic>;
      final onboarding = data['onboarding'] as List<dynamic>;
      final replies = data['compassionateReplies'] as Map<String, dynamic>;

      for (final item in [...greetings, ...preview, ...onboarding]) {
        expect((item['text'] as String).trim().isNotEmpty, true,
            reason: 'Line ${item['id']} has empty text');
      }
      for (final bucket in ['positive', 'neutral', 'negative']) {
        for (final item in replies[bucket] as List<dynamic>) {
          expect((item['text'] as String).trim().isNotEmpty, true,
              reason: 'Line ${item['id']} has empty text');
        }
      }
    });
  });

  group('PAL audio asset paths', () {
    late Map<String, dynamic> data;

    setUpAll(() async {
      final jsonStr =
          await rootBundle.loadString('assets/pal/pal_lines.json');
      data = jsonDecode(jsonStr) as Map<String, dynamic>;
    });

    test('all expected asset paths are well-formed for all voices', () {
      // Collect all line IDs that should exist for each voice
      final lineIds = <String>[];

      final preview = data['preview'] as List<dynamic>;
      for (final item in preview) {
        lineIds.add(item['id'] as String);
      }

      final greetings = data['greetings'] as List<dynamic>;
      for (final item in greetings) {
        lineIds.add(item['id'] as String);
      }

      final replies = data['compassionateReplies'] as Map<String, dynamic>;
      for (final bucket in ['positive', 'neutral', 'negative']) {
        for (final item in replies[bucket] as List<dynamic>) {
          lineIds.add(item['id'] as String);
        }
      }

      // Verify path format for all voices x all lines
      for (final voice in PalVoiceRegistry.voices) {
        for (final lineId in lineIds) {
          final path =
              'assets/pal/audio/${voice.voiceKey}/$lineId.mp3';
          expect(path, contains(voice.voiceKey));
          expect(path, endsWith('.mp3'));
          expect(path, isNot(contains(' ')),
              reason: 'Path should not contain spaces: $path');
        }
      }
    });
  });
}
