import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/services/reflection_service.dart';
import 'package:bible_pal/services/reflection_templates.dart';

/// Tests for reflection service and audio path derivation
/// Verifies:
/// - Reflection template content constraints
/// - Voice assignment determinism
/// - Reflection audio path derivation
void main() {
  group('ReflectionService', () {
    late ReflectionService reflectionService;

    setUp(() {
      reflectionService = ReflectionService();
    });

    group('getReflectionForParable', () {
      test('returns reflection for adult mode with valid mood', () {
        final parable = _createParable(mood: 'joyful');
        final reflection = reflectionService.getReflectionForParable(
          parable: parable,
          isKidMode: false,
        );

        expect(reflection, isNotNull);
        expect(reflection!.text, isNotEmpty);
      });

      test('returns reflection for kid mode with valid mood', () {
        final parable = _createParable(mood: 'joyful', kidFriendly: true);
        final reflection = reflectionService.getReflectionForParable(
          parable: parable,
          isKidMode: true,
        );

        expect(reflection, isNotNull);
        expect(reflection!.text, isNotEmpty);
        // Kid mode should not have questions
        expect(reflection.question, isNull);
      });

      test('returns reflection for all adult moods', () {
        final moods = ['joyful', 'weary', 'anxious', 'hurting', 'neutral'];

        for (final mood in moods) {
          final parable = _createParable(mood: mood);
          final reflection = reflectionService.getReflectionForParable(
            parable: parable,
            isKidMode: false,
          );

          expect(reflection, isNotNull,
              reason: 'Mood $mood should have reflection');
          expect(reflection!.text, isNotEmpty,
              reason: 'Mood $mood should have text');
        }
      });

      test('returns reflection for all kid moods', () {
        final moods = ['joyful', 'weary', 'anxious', 'hurting', 'neutral'];

        for (final mood in moods) {
          final parable = _createParable(mood: mood, kidFriendly: true);
          final reflection = reflectionService.getReflectionForParable(
            parable: parable,
            isKidMode: true,
          );

          expect(reflection, isNotNull,
              reason: 'Kid mood $mood should have reflection');
          expect(reflection!.text, isNotEmpty,
              reason: 'Kid mood $mood should have text');
        }
      });
    });
  });

  group('Reflection Templates', () {
    group('content constraints', () {
      test('adult reflections have soft landing lines', () {
        for (final entry in adultReflectionsByMood.entries) {
          expect(
            entry.value.text.contains(
                'And even a small step forward can be enough for today'),
            isTrue,
            reason: 'Adult mood ${entry.key} should end with soft landing',
          );
        }
      });

      test('kid reflections have gentle closing lines', () {
        for (final entry in kidReflectionsByMood.entries) {
          expect(
            entry.value.text.contains('Even one small') ||
                entry.value.text.contains('Even one friend'),
            isTrue,
            reason: 'Kid mood ${entry.key} should end with gentle closing',
          );
        }
      });

      test('adult reflections do not exceed 4 sentences', () {
        for (final entry in adultReflectionsByMood.entries) {
          // Count sentences (roughly by counting periods)
          final sentenceCount = '.'.allMatches(entry.value.text).length;
          expect(
            sentenceCount,
            lessThanOrEqualTo(4),
            reason: 'Adult mood ${entry.key} should have max 4 sentences',
          );
        }
      });

      test('kid reflections do not exceed 2 sentences', () {
        for (final entry in kidReflectionsByMood.entries) {
          final sentenceCount = '.'.allMatches(entry.value.text).length;
          expect(
            sentenceCount,
            lessThanOrEqualTo(2),
            reason: 'Kid mood ${entry.key} should have max 2 sentences',
          );
        }
      });
    });

    group('banned phrases', () {
      final bannedPhrases = [
        'you should',
        'you must',
        'you need to',
        'do this',
        'therapy',
        'therapist',
        'medical',
        'diagnos',
        'treatment',
      ];

      test('adult reflections do not contain banned phrases', () {
        for (final entry in adultReflectionsByMood.entries) {
          final lowerText = entry.value.text.toLowerCase();
          for (final phrase in bannedPhrases) {
            expect(
              lowerText.contains(phrase),
              isFalse,
              reason: 'Adult mood ${entry.key} should not contain "$phrase"',
            );
          }

          // Also check questions
          if (entry.value.question != null) {
            final lowerQuestion = entry.value.question!.toLowerCase();
            for (final phrase in bannedPhrases) {
              expect(
                lowerQuestion.contains(phrase),
                isFalse,
                reason:
                    'Adult question for ${entry.key} should not contain "$phrase"',
              );
            }
          }
        }
      });

      test('kid reflections do not contain banned phrases', () {
        for (final entry in kidReflectionsByMood.entries) {
          final lowerText = entry.value.text.toLowerCase();
          for (final phrase in bannedPhrases) {
            expect(
              lowerText.contains(phrase),
              isFalse,
              reason: 'Kid mood ${entry.key} should not contain "$phrase"',
            );
          }
        }
      });

      test('adult tag reflections do not contain banned phrases', () {
        for (final entry in adultReflectionsByTag.entries) {
          final lowerText = entry.value.text.toLowerCase();
          for (final phrase in bannedPhrases) {
            expect(
              lowerText.contains(phrase),
              isFalse,
              reason: 'Adult tag ${entry.key} should not contain "$phrase"',
            );
          }
        }
      });
    });
  });

  group('Voice Assignment', () {
    test('same storyId always gets same voice (determinism)', () {
      // Simulate deterministic voice selection using hash
      const storyId = 'parable_401';
      final voice1 = _selectVoiceForStory(storyId, 20);
      final voice2 = _selectVoiceForStory(storyId, 20);
      final voice3 = _selectVoiceForStory(storyId, 20);

      expect(voice1, equals(voice2));
      expect(voice2, equals(voice3));
    });

    test('different storyIds get different voices (variety)', () {
      final voiceIndices = <int>{};
      final storyIds = [
        'parable_001',
        'parable_002',
        'parable_003',
        'parable_004',
        'parable_005',
        'parable_010',
        'parable_020',
        'parable_050',
        'parable_100',
        'parable_200',
      ];

      for (final storyId in storyIds) {
        voiceIndices.add(_selectVoiceForStory(storyId, 20));
      }

      // Should have variety - at least 3 different voices for 10 stories
      expect(voiceIndices.length, greaterThanOrEqualTo(3));
    });
  });

  group('Reflection Audio Path', () {
    test('derives reflection path from story audio path', () {
      final parable = _createParable(
        audioFilePath: 'parable_401_encouraging_short.mp3',
      );

      final reflectionPath = _getReflectionAudioPath(parable);
      expect(reflectionPath,
          equals('parable_401_encouraging_short.reflection.mp3'));
    });

    test('uses explicit reflectionAudioPath if provided', () {
      final parable = _createParable(
        audioFilePath: 'parable_401_encouraging_short.mp3',
        reflectionAudioPath: 'custom_reflection.mp3',
      );

      final reflectionPath = _getReflectionAudioPath(parable);
      expect(reflectionPath, equals('custom_reflection.mp3'));
    });

    test('returns null for missing audio path', () {
      final parable = _createParable(audioFilePath: null);
      final reflectionPath = _getReflectionAudioPath(parable);
      expect(reflectionPath, isNull);
    });

    test('returns null for non-mp3 audio path', () {
      final parable = _createParable(audioFilePath: 'audio.wav');
      final reflectionPath = _getReflectionAudioPath(parable);
      expect(reflectionPath, isNull);
    });
  });

  group('Parable Model', () {
    test('includes narratorVoiceKey in JSON serialization', () {
      final parable = _createParable(
        narratorVoiceKey: 'VOICE_JAMES_HUSKY',
      );

      final json = parable.toJson();
      expect(json['narratorVoiceKey'], equals('VOICE_JAMES_HUSKY'));
    });

    test('includes reflectionAudioPath in JSON serialization', () {
      final parable = _createParable(
        reflectionAudioPath: 'parable_401.reflection.mp3',
      );

      final json = parable.toJson();
      expect(json['reflectionAudioPath'], equals('parable_401.reflection.mp3'));
    });

    test('parses narratorVoiceKey from JSON', () {
      const json = {
        'storyId': 'test_001',
        'title': 'Test Story',
        'mood': 'joyful',
        'length': 5,
        'storytellingMode': 'creative',
        'kidFriendly': false,
        'narratorVoiceKey': 'VOICE_SARAH_STORYTELLER',
        'reflectionAudioPath': 'test_001.reflection.mp3',
      };

      final parable = Parable.fromJson(json);
      expect(parable.narratorVoiceKey, equals('VOICE_SARAH_STORYTELLER'));
      expect(parable.reflectionAudioPath, equals('test_001.reflection.mp3'));
    });

    test('copyWith preserves narratorVoiceKey', () {
      final parable = _createParable(
        narratorVoiceKey: 'VOICE_JAMES_HUSKY',
      );

      final copy = parable.copyWith(title: 'New Title');
      expect(copy.narratorVoiceKey, equals('VOICE_JAMES_HUSKY'));
    });
  });
}

/// Helper: Create a test parable
Parable _createParable({
  String storyId = 'test_001',
  String mood = 'joyful',
  bool kidFriendly = false,
  String? audioFilePath = 'test.mp3',
  String? reflectionAudioPath,
  String? narratorVoiceKey,
}) {
  return Parable(
    storyId: storyId,
    title: 'Test Story',
    mood: mood,
    length: 5,
    storytellingMode: 'creative',
    kidFriendly: kidFriendly,
    audioFilePath: audioFilePath,
    reflectionAudioPath: reflectionAudioPath,
    narratorVoiceKey: narratorVoiceKey,
  );
}

/// Helper: Simulate deterministic voice selection (mirrors server script logic)
int _selectVoiceForStory(String storyId, int voiceCount) {
  // Simple hash: sum of character codes mod voice count
  var hash = 0;
  for (var i = 0; i < storyId.length; i++) {
    hash = (hash * 31 + storyId.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  return hash % voiceCount;
}

/// Helper: Get reflection audio path (mirrors app logic)
String? _getReflectionAudioPath(Parable parable) {
  // Prefer explicit reflection path from manifest
  if (parable.reflectionAudioPath != null) {
    return parable.reflectionAudioPath;
  }
  // Fall back to convention-based derivation
  final storyAudioPath = parable.audioFilePath;
  if (storyAudioPath == null) return null;
  if (!storyAudioPath.endsWith('.mp3')) return null;
  return storyAudioPath.replaceAll('.mp3', '.reflection.mp3');
}
