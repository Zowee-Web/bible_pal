import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/models/parable.dart';

/// Tests for reflectionQuestion field (SPEC.md Feature 37, STORY_FACTORY.md Section 6.1).
void main() {
  /// Helper to build a minimal valid Parable JSON map.
  Map<String, dynamic> baseJson({String? reflectionQuestion}) {
    final json = <String, dynamic>{
      'storyId': 'test_001',
      'title': 'Test Story',
      'mood': 'joyful',
      'emotionalTags': <String>['grateful'],
      'length': 5,
      'storyLength': 'short',
      'storytellingMode': 'traditional',
      'translationId': 'WEB',
      'languageStyle': 'WEB',
      'kidFriendly': false,
      'scriptureSources': <String>[],
      'narratorVoiceKey': 'VOICE_JAMES_HUSKY',
      'bibleSourceRef': 'Psalm 23',
      'bibleStoryKey': 'psalm_23',
    };
    if (reflectionQuestion != null) {
      json['reflectionQuestion'] = reflectionQuestion;
    }
    return json;
  }

  group('Parable.reflectionQuestion — SPEC Feature 37', () {
    test('parses reflectionQuestion when present', () {
      final p = Parable.fromJson(
          baseJson(reflectionQuestion: 'Have you ever found rest in an unexpected place?'));
      expect(p.reflectionQuestion,
          equals('Have you ever found rest in an unexpected place?'));
    });

    test('reflectionQuestion is null when absent from JSON', () {
      final p = Parable.fromJson(baseJson());
      expect(p.reflectionQuestion, isNull);
    });

    test('reflectionQuestion empty string is preserved', () {
      final p = Parable.fromJson(baseJson(reflectionQuestion: ''));
      expect(p.reflectionQuestion, equals(''));
    });

    test('toJson includes reflectionQuestion', () {
      final p = Parable.fromJson(
          baseJson(reflectionQuestion: 'Where in your life do you see this pattern?'));
      final json = p.toJson();
      expect(json['reflectionQuestion'],
          equals('Where in your life do you see this pattern?'));
    });

    test('toJson includes null reflectionQuestion when absent', () {
      final p = Parable.fromJson(baseJson());
      final json = p.toJson();
      expect(json.containsKey('reflectionQuestion'), isTrue);
      expect(json['reflectionQuestion'], isNull);
    });

    test('roundtrip: fromJson -> toJson -> fromJson preserves reflectionQuestion', () {
      const question = 'Is there a moment today where you noticed something like this?';
      final original = Parable.fromJson(baseJson(reflectionQuestion: question));
      final json = original.toJson();
      final restored = Parable.fromJson(json);
      expect(restored.reflectionQuestion, equals(question));
    });

    test('copyWith can set reflectionQuestion', () {
      final p = Parable.fromJson(baseJson());
      final updated = p.copyWith(reflectionQuestion: 'Have you ever felt this way?');
      expect(updated.reflectionQuestion, equals('Have you ever felt this way?'));
      expect(p.reflectionQuestion, isNull); // original unchanged
    });

    test('backwards compatibility: old manifest entries without reflectionQuestion still parse', () {
      // Simulates a legacy manifest entry with no reflectionQuestion field
      final legacyJson = <String, dynamic>{
        'storyId': 'parable_001_joyful_5min',
        'title': 'The Shepherds Gratitude',
        'mood': 'joyful',
        'emotionalTags': <String>['grateful'],
        'length': 5,
        'storytellingMode': 'creative',
        'kidFriendly': false,
        'translationId': 'WEB',
        'narratorVoiceKey': 'VOICE_PETER_BOLD',
        'storyLength': 'short',
      };
      final p = Parable.fromJson(legacyJson);
      expect(p.reflectionQuestion, isNull);
      expect(p.storyId, equals('parable_001_joyful_5min'));
    });
  });
}
