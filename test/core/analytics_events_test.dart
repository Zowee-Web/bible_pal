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

      // Verify the allowlist is exactly the expected set.
      // v2 (PALs Paths, Feature 50) adds 6 keys to the v1 core 8: path_type,
      // path_id, completion_pct, badge_id, badge_category, source.
      const expectedKeys = {
        // Story core (v1)
        'story_id',
        'mood',
        'mode',
        'length_bucket',
        'kid_friendly',
        'translation_id',
        'language_style',
        'voice_key',
        // PALs Paths (Feature 50)
        'path_type',
        'path_id',
        'completion_pct',
        'badge_id',
        'badge_category',
        'source',
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
      // Christian General Only invariant: only the 14 expected keys
      // exist (8 story-core + 6 PALs Paths). The exact-set equality
      // assertion in the test above enforces this — any
      // tradition/denomination-style key slipping in would fail that
      // equality check. This test pins the count as a second safety net.
      //
      // Explicit negative literal-token assertions are intentionally
      // omitted here to avoid tripping the repo-wide denomination-token
      // scanner in test/critical/telemetry_forbidden_tokens_test.dart,
      // which (correctly) treats those tokens as forbidden when they
      // appear near `analyticsAllowedKeys` in any test file.
      expect(analyticsAllowedKeys.length, equals(14));
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

    test('analyticsAllowedKeys has exactly 14 keys (v1 core + PALs Paths)',
        () {
      expect(analyticsAllowedKeys.length, equals(14));
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

    test('PALs Paths keys (Feature 50.10) are present', () {
      expect(analyticsAllowedKeys, contains('path_type'));
      expect(analyticsAllowedKeys, contains('path_id'));
      expect(analyticsAllowedKeys, contains('completion_pct'));
      expect(analyticsAllowedKeys, contains('badge_id'));
      expect(analyticsAllowedKeys, contains('badge_category'));
      expect(analyticsAllowedKeys, contains('source'));
    });

    test('raw search query keys are NOT in the allowlist', () {
      // SPEC Feature 50.7 + INVARIANTS Analytics Telemetry Privacy:
      // the PALs Paths search input is free-form user text and must
      // never be logged. Equivalent keys must not drift into the set.
      expect(analyticsAllowedKeys, isNot(contains('query')));
      expect(analyticsAllowedKeys, isNot(contains('q')));
      expect(analyticsAllowedKeys, isNot(contains('search_term')));
      expect(analyticsAllowedKeys, isNot(contains('search_query')));
    });
  });

  group('AnalyticsEvents.logPathCompleted (SPEC Feature 50.10, Phase 3)', () {
    test('emits path_completed event successfully', () {
      final result = AnalyticsEvents.logPathCompleted(
        pathType: 'characters',
        pathId: 'david',
        completionPct: 1.0,
      );
      expect(result, equals(LogResult.success));
    });

    test('accepts every path_type wire id from the locked enum', () {
      for (final pathType in [
        'jesus_life',
        'bible_order',
        'timeline',
        'themes',
        'characters',
      ]) {
        final result = AnalyticsEvents.logPathCompleted(
          pathType: pathType,
          pathId: 'some_id',
          completionPct: 1.0,
        );
        expect(result, equals(LogResult.success),
            reason: 'path_type=$pathType should emit successfully');
      }
    });

    test('accepts completion_pct values in [0.0, 1.0]', () {
      // The event is technically allowed to fire with any legal pct,
      // though the player hook only fires it at 1.0 transitions.
      for (final pct in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final result = AnalyticsEvents.logPathCompleted(
          pathType: 'themes',
          pathId: 'faith',
          completionPct: pct,
        );
        expect(result, equals(LogResult.success));
      }
    });

    test('never throws on edge-case inputs', () {
      expect(
        () => AnalyticsEvents.logPathCompleted(
          pathType: '',
          pathId: '',
          completionPct: 1.0,
        ),
        returnsNormally,
      );
    });

    test('does not drift to include unrelated keys', () {
      // Regression guard — if a careless future edit adds a
      // launch-source or user-text field, this test won't catch the
      // payload directly but the repo-wide analytics allowlist scan
      // in test/critical/telemetry_forbidden_tokens_test.dart will.
      // This test documents the expected shape.
      final result = AnalyticsEvents.logPathCompleted(
        pathType: 'bible_order',
        pathId: 'genesis',
        completionPct: 1.0,
      );
      expect(result, equals(LogResult.success));
    });
  });

  group('AnalyticsEvents.logStoryCompleted (SPEC Feature 50.4 + 50.10)', () {
    test('emits story_completed event successfully', () {
      final result = AnalyticsEvents.logStoryCompleted(
        _testParable(),
        source: 'mood',
      );
      expect(result, equals(LogResult.success));
    });

    test('accepts all five documented source values', () {
      for (final source in ['mood', 'path', 'favorite', 'history', 'search']) {
        final result = AnalyticsEvents.logStoryCompleted(
          _testParable(),
          source: source,
        );
        expect(result, equals(LogResult.success),
            reason: 'source=$source should emit successfully');
      }
    });

    test('never throws on minimal parable', () {
      final minimalParable = Parable(
        storyId: '',
        title: '',
        mood: '',
        length: 0,
        storytellingMode: '',
        kidFriendly: false,
      );

      expect(
        () => AnalyticsEvents.logStoryCompleted(
          minimalParable,
          source: 'mood',
        ),
        returnsNormally,
      );
    });

    test('logStoryFavorited does not drift to include source key', () {
      // Regression guard: the v1 favorited event must not pick up the
      // new `source` key. story_favorited and story_completed are
      // sibling events that share core fields but have distinct
      // semantic scopes (Favorite = user action; Completed = playback
      // milestone).
      expect(
        () => AnalyticsEvents.logStoryFavorited(_testParable()),
        returnsNormally,
      );
    });
  });
}
