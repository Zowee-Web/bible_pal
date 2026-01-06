import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/reflection_templates.dart';
import 'package:bible_pal/services/reflection_service.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/models/user_preferences.dart';

/// Tests for reflection language safety (INVARIANTS.md)
/// Ensures all reflections comply with safety constraints:
/// - Descriptive language only, no prescriptions
/// - No advice, diagnosis, or therapeutic claims
/// - Kid mode uses short, literal language
void main() {
  group('Reflection Language Safety', () {
    // Banned phrases that MUST NOT appear in any reflection
    final bannedPhrases = [
      // Advice
      'you should',
      'try to',
      'consider doing',
      'it helps to',
      'make sure to',
      // Diagnosis
      'you are feeling',
      'you seem',
      'this suggests you',
      'this means you',
      // Promises
      'will help you',
      "you'll feel",
      'this can heal',
      'this will make',
      // Therapy
      'cope with',
      'healing process',
      'therapy',
      'treatment',
      'process your',
      // Probing (note: questions are allowed, but not leading/probing ones)
      'how did that make you feel',
      'what came up for you',
      'what emotions are',
    ];

    test('CRITICAL: Adult mood reflections contain no banned phrases', () {
      for (final entry in adultReflectionsByMood.entries) {
        final mood = entry.key;
        final reflection = entry.value;
        final text = reflection.text.toLowerCase();
        final question = reflection.question?.toLowerCase() ?? '';

        for (final phrase in bannedPhrases) {
          expect(
            text.contains(phrase),
            isFalse,
            reason: 'Adult mood reflection "$mood" contains banned phrase "$phrase" in text',
          );
          expect(
            question.contains(phrase),
            isFalse,
            reason: 'Adult mood reflection "$mood" contains banned phrase "$phrase" in question',
          );
        }
      }
    });

    test('CRITICAL: Adult tag reflections contain no banned phrases', () {
      for (final entry in adultReflectionsByTag.entries) {
        final tag = entry.key;
        final reflection = entry.value;
        final text = reflection.text.toLowerCase();
        final question = reflection.question?.toLowerCase() ?? '';

        for (final phrase in bannedPhrases) {
          expect(
            text.contains(phrase),
            isFalse,
            reason: 'Adult tag reflection "$tag" contains banned phrase "$phrase" in text',
          );
          expect(
            question.contains(phrase),
            isFalse,
            reason: 'Adult tag reflection "$tag" contains banned phrase "$phrase" in question',
          );
        }
      }
    });

    test('CRITICAL: Kid mood reflections contain no banned phrases', () {
      for (final entry in kidReflectionsByMood.entries) {
        final mood = entry.key;
        final reflection = entry.value;
        final text = reflection.text.toLowerCase();

        for (final phrase in bannedPhrases) {
          expect(
            text.contains(phrase),
            isFalse,
            reason: 'Kid mood reflection "$mood" contains banned phrase "$phrase"',
          );
        }
      }
    });

    test('CRITICAL: Kid tag reflections contain no banned phrases', () {
      for (final entry in kidReflectionsByTag.entries) {
        final tag = entry.key;
        final reflection = entry.value;
        final text = reflection.text.toLowerCase();

        for (final phrase in bannedPhrases) {
          expect(
            text.contains(phrase),
            isFalse,
            reason: 'Kid tag reflection "$tag" contains banned phrase "$phrase"',
          );
        }
      }
    });
  });

  group('Kid Mode Reflection Constraints', () {
    test('CRITICAL: Kid reflections have no questions (age-appropriate)', () {
      for (final entry in kidReflectionsByMood.entries) {
        final mood = entry.key;
        final reflection = entry.value;
        expect(
          reflection.question,
          isNull,
          reason: 'Kid mood reflection "$mood" should not have a question',
        );
      }

      for (final entry in kidReflectionsByTag.entries) {
        final tag = entry.key;
        final reflection = entry.value;
        expect(
          reflection.question,
          isNull,
          reason: 'Kid tag reflection "$tag" should not have a question',
        );
      }
    });

    test('CRITICAL: Kid reflections are short (under 100 characters)', () {
      const maxLength = 100;

      for (final entry in kidReflectionsByMood.entries) {
        final mood = entry.key;
        final reflection = entry.value;
        expect(
          reflection.text.length,
          lessThanOrEqualTo(maxLength),
          reason: 'Kid mood reflection "$mood" is too long (${reflection.text.length} chars)',
        );
      }

      for (final entry in kidReflectionsByTag.entries) {
        final tag = entry.key;
        final reflection = entry.value;
        expect(
          reflection.text.length,
          lessThanOrEqualTo(maxLength),
          reason: 'Kid tag reflection "$tag" is too long (${reflection.text.length} chars)',
        );
      }
    });

    test('Kid reflections use simple "This story shows" pattern', () {
      for (final entry in kidReflectionsByMood.entries) {
        final mood = entry.key;
        final reflection = entry.value;
        expect(
          reflection.text.startsWith('This story shows'),
          isTrue,
          reason: 'Kid mood reflection "$mood" should start with "This story shows"',
        );
      }

      for (final entry in kidReflectionsByTag.entries) {
        final tag = entry.key;
        final reflection = entry.value;
        expect(
          reflection.text.startsWith('This story shows'),
          isTrue,
          reason: 'Kid tag reflection "$tag" should start with "This story shows"',
        );
      }
    });
  });

  group('ReflectionService', () {
    late ReflectionService service;

    setUp(() {
      service = ReflectionService();
    });

    test('returns reflection for parable with mood', () {
      final parable = Parable(
        storyId: 'test-1',
        title: 'Test Story',
        mood: 'joyful',
        length: 5,
        faithTradition: 'Non-Denominational',
        storytellingMode: 'creative',
        kidFriendly: false,
      );

      final reflection = service.getReflectionForParable(
        parable: parable,
        isKidMode: false,
      );

      expect(reflection, isNotNull);
      expect(reflection!.text, contains('joy'));
    });

    test('returns kid reflection when isKidMode is true', () {
      final parable = Parable(
        storyId: 'test-2',
        title: 'Test Story',
        mood: 'joyful',
        length: 5,
        faithTradition: 'Non-Denominational',
        storytellingMode: 'creative',
        kidFriendly: true,
      );

      final reflection = service.getReflectionForParable(
        parable: parable,
        isKidMode: true,
      );

      expect(reflection, isNotNull);
      expect(reflection!.text, startsWith('This story shows'));
      expect(reflection.question, isNull);
    });

    test('prioritizes emotional tags over mood', () {
      final parable = Parable(
        storyId: 'test-3',
        title: 'Test Story',
        mood: 'joyful',
        emotionalTags: ['grief'], // Tag should take priority
        length: 5,
        faithTradition: 'Non-Denominational',
        storytellingMode: 'creative',
        kidFriendly: false,
      );

      final reflection = service.getReflectionForParable(
        parable: parable,
        isKidMode: false,
      );

      expect(reflection, isNotNull);
      expect(reflection!.text.toLowerCase(), contains('grief'));
    });

    test('shouldShowReflection returns false when disabled', () {
      final parable = Parable(
        storyId: 'test-4',
        title: 'Test Story',
        mood: 'joyful',
        length: 5,
        faithTradition: 'Non-Denominational',
        storytellingMode: 'creative',
        kidFriendly: false,
      );

      final result = service.shouldShowReflection(
        showEverydayReflections: false,
        parable: parable,
        isKidMode: false,
      );

      expect(result, isFalse);
    });

    test('shouldShowReflection returns true when enabled and reflection exists', () {
      final parable = Parable(
        storyId: 'test-5',
        title: 'Test Story',
        mood: 'joyful',
        length: 5,
        faithTradition: 'Non-Denominational',
        storytellingMode: 'creative',
        kidFriendly: false,
      );

      final result = service.shouldShowReflection(
        showEverydayReflections: true,
        parable: parable,
        isKidMode: false,
      );

      expect(result, isTrue);
    });
  });

  group('UserPreferences showEverydayReflections', () {
    test('defaults to true on first launch', () {
      final prefs = UserPreferences.defaults();
      expect(prefs.showEverydayReflections, isTrue);
    });

    test('persists through JSON serialization', () {
      final prefs = UserPreferences(
        faithTradition: 'Protestant',
        bibleTranslation: 'WEB',
        showEverydayReflections: false,
      );

      final json = prefs.toJson();
      final restored = UserPreferences.fromJson(json);

      expect(restored.showEverydayReflections, isFalse);
    });

    test('persists true value through JSON serialization', () {
      final prefs = UserPreferences(
        faithTradition: 'Protestant',
        bibleTranslation: 'WEB',
        showEverydayReflections: true,
      );

      final json = prefs.toJson();
      final restored = UserPreferences.fromJson(json);

      expect(restored.showEverydayReflections, isTrue);
    });

    test('copyWith preserves showEverydayReflections', () {
      final prefs = UserPreferences(
        faithTradition: 'Protestant',
        bibleTranslation: 'WEB',
        showEverydayReflections: false,
      );

      final updated = prefs.copyWith(faithTradition: 'Catholic');

      expect(updated.showEverydayReflections, isFalse);
      expect(updated.faithTradition, 'Catholic');
    });

    test('copyWith can change showEverydayReflections', () {
      final prefs = UserPreferences(
        faithTradition: 'Protestant',
        bibleTranslation: 'WEB',
        showEverydayReflections: false,
      );

      final updated = prefs.copyWith(showEverydayReflections: true);

      expect(updated.showEverydayReflections, isTrue);
    });

    test('fromJson defaults to true when key is missing', () {
      final json = <String, dynamic>{
        'faithTradition': 'Protestant',
        'bibleTranslation': 'WEB',
        // showEverydayReflections not present
      };

      final prefs = UserPreferences.fromJson(json);

      expect(prefs.showEverydayReflections, isTrue);
    });
  });
}
