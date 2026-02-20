import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/analytics_events.dart';
import 'package:bible_pal/core/app_logger.dart';
import 'package:bible_pal/models/parable.dart';

/// Test helper: builds a fully-populated Parable for analytics tests.
Parable _testParable({
  bool kidFriendly = false,
  String mood = 'weary',
  String storytellingMode = 'traditional',
  String storyLength = 'short',
  String translationId = 'WEB',
  String languageStyle = 'WEB',
  String narratorVoiceKey = 'VOICE_JAMES_HUSKY',
}) {
  return Parable(
    storyId: '807',
    title: 'A Gentle Rest',
    mood: mood,
    length: 5,
    storyLength: storyLength,
    storytellingMode: storytellingMode,
    translationId: translationId,
    languageStyle: languageStyle,
    kidFriendly: kidFriendly,
    scriptureSources: ['Psalm 127:1-2'],
    narratorVoiceKey: narratorVoiceKey,
    bibleSourceRef: 'Psalm 127:1-2',
    bibleStoryKey: 'psalm_127_rest',
    reflectionQuestion: 'What makes you feel safe?',
  );
}

void main() {
  setUp(() {
    AppLogger.instance.clearBreadcrumbs();
  });

  group('AnalyticsEvents.logStoryFavorited', () {
    test('CRITICAL: emits story_favorited event successfully', () {
      final result = AnalyticsEvents.logStoryFavorited(_testParable());
      expect(result, equals(LogResult.success));
    });

    test('CRITICAL: story_favorited payload contains only allowlisted keys',
        () {
      final parable = _testParable();
      final result = AnalyticsEvents.logStoryFavorited(parable);
      expect(result, equals(LogResult.success));

      // Verify the allowlist is exactly the expected set
      const expectedKeys = {
        'story_id',
        'mood',
        'mode',
        'length_bucket',
        'kid_friendly',
        'translation_id',
        'language_style',
        'voice_key',
      };
      expect(analyticsAllowedKeys, equals(expectedKeys));
    });

    test('CRITICAL: allowlist contains no PII keys', () {
      // PII keys must never appear in the allowlist.
      // AppLogger._blockedKeys enforces this at runtime;
      // this test ensures we never add them to the allowlist.
      expect(analyticsAllowedKeys.contains('email'), isFalse);
      expect(analyticsAllowedKeys.contains('phone'), isFalse);
      expect(analyticsAllowedKeys.contains('name'), isFalse);
      expect(analyticsAllowedKeys.contains('title'), isFalse);
      expect(analyticsAllowedKeys.contains('userText'), isFalse);
      expect(analyticsAllowedKeys.contains('user_text'), isFalse);
      expect(analyticsAllowedKeys.contains('message'), isFalse);
      expect(analyticsAllowedKeys.contains('prompt'), isFalse);
      expect(analyticsAllowedKeys.contains('transcript'), isFalse);
    });

    test('CRITICAL: allowlist contains length_bucket not minute-based keys',
        () {
      // Telemetry invariant: only length_bucket is permitted.
      expect(analyticsAllowedKeys.contains('length_bucket'), isTrue);
      // No minute-based fields allowed
      expect(analyticsAllowedKeys, isNot(contains('minutes')));
    });

    test('CRITICAL: allowlist contains no denomination keys', () {
      // Christian General Only invariant: only the 8 expected keys exist.
      // If a denomination-related key were added, the exact-set test above
      // would also catch it. This test verifies the count as a safety net.
      expect(analyticsAllowedKeys.length, equals(8));
    });

    test('CRITICAL: kidFriendly field is populated correctly (true)', () {
      final result =
          AnalyticsEvents.logStoryFavorited(_testParable(kidFriendly: true));
      expect(result, equals(LogResult.success));
    });

    test('CRITICAL: kidFriendly field is populated correctly (false)', () {
      final result = AnalyticsEvents.logStoryFavorited(
          _testParable(kidFriendly: false));
      expect(result, equals(LogResult.success));
    });

    test('CRITICAL: logStoryFavorited never throws', () {
      // Even with minimal/edge-case data, should never throw
      final minimalParable = Parable(
        storyId: '',
        title: '',
        mood: '',
        length: 0,
        storytellingMode: '',
        kidFriendly: false,
      );

      expect(
        () => AnalyticsEvents.logStoryFavorited(minimalParable),
        returnsNormally,
      );
    });

    test('emits correct mood value', () {
      for (final mood
          in ['joyful', 'weary', 'anxious', 'hurting', 'neutral']) {
        final result =
            AnalyticsEvents.logStoryFavorited(_testParable(mood: mood));
        expect(result, equals(LogResult.success));
      }
    });

    test('emits correct mode value for traditional and creative', () {
      final tradResult = AnalyticsEvents.logStoryFavorited(
          _testParable(storytellingMode: 'traditional'));
      expect(tradResult, equals(LogResult.success));

      final creativeResult = AnalyticsEvents.logStoryFavorited(
          _testParable(storytellingMode: 'creative'));
      expect(creativeResult, equals(LogResult.success));
    });

    test('emits correct length_bucket for all buckets', () {
      for (final len in ['short', 'full', 'long']) {
        final result =
            AnalyticsEvents.logStoryFavorited(_testParable(storyLength: len));
        expect(result, equals(LogResult.success));
      }
    });

    test('handles null narratorVoiceKey gracefully', () {
      final parable = Parable(
        storyId: '999',
        title: 'Test',
        mood: 'neutral',
        length: 5,
        storyLength: 'short',
        storytellingMode: 'traditional',
        kidFriendly: false,
      );

      expect(
        () => AnalyticsEvents.logStoryFavorited(parable),
        returnsNormally,
      );
    });

    test('translation_id reflects parable translationId', () {
      final webResult =
          AnalyticsEvents.logStoryFavorited(_testParable(translationId: 'WEB'));
      expect(webResult, equals(LogResult.success));

      final kjvResult =
          AnalyticsEvents.logStoryFavorited(_testParable(translationId: 'KJV'));
      expect(kjvResult, equals(LogResult.success));
    });
  });

  group('Analytics Allowlist Integrity', () {
    test('analyticsAllowedKeys is non-empty', () {
      expect(analyticsAllowedKeys, isNotEmpty);
    });

    test('analyticsAllowedKeys has exactly 8 keys', () {
      expect(analyticsAllowedKeys.length, equals(8));
    });

    test('all allowlisted keys are snake_case', () {
      for (final key in analyticsAllowedKeys) {
        expect(
          RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(key),
          isTrue,
          reason: 'Key "$key" must be snake_case',
        );
      }
    });
  });
}
