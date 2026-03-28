import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/core/story_length_bucket.dart';

/// Migration tests for v3 features.
/// Validates that existing users upgrading from v2 don't hit issues.
void main() {
  group('v3 Migration: mood system', () {
    test('old "neutral" mood in lastDetectedMood is accepted by fromJson', () {
      // Existing user has neutral saved — should load without crash
      final json = {
        'userName': 'Test',
        'bibleTranslation': 'WEB',
        'lastDetectedMood': 'neutral',
      };
      final prefs = UserPreferences.fromJson(json);
      // neutral is no longer in allowedMoodIds, so _validateMood returns null
      expect(prefs.lastDetectedMood, isNull);
    });

    test('new mood "grateful" loads correctly from JSON', () {
      final json = {
        'userName': 'Test',
        'bibleTranslation': 'WEB',
        'lastDetectedMood': 'grateful',
      };
      final prefs = UserPreferences.fromJson(json);
      expect(prefs.lastDetectedMood, 'grateful');
    });

    test('all 8 new moods are in allowedMoodIds', () {
      const expected = {
        'joyful', 'grateful', 'weary', 'anxious',
        'hurting', 'brave_courage', 'calm_peaceful', 'encouraging',
      };
      expect(allowedMoodIds, expected);
    });

    test('neutral is NOT in allowedMoodIds', () {
      expect(allowedMoodIds.contains('neutral'), false);
    });
  });

  group('v3 Migration: preferredLengthBucket', () {
    test('missing preferredLengthBucket defaults to null', () {
      final json = {
        'userName': 'Test',
        'bibleTranslation': 'WEB',
      };
      final prefs = UserPreferences.fromJson(json);
      expect(prefs.preferredLengthBucket, isNull);
    });

    test('saved preferredLengthBucket loads correctly', () {
      final json = {
        'userName': 'Test',
        'bibleTranslation': 'WEB',
        'preferredLengthBucket': 'full',
      };
      final prefs = UserPreferences.fromJson(json);
      expect(prefs.preferredLengthBucket, 'full');
      expect(StoryLengthBucket.fromJson(prefs.preferredLengthBucket!), StoryLengthBucket.full);
    });
  });

  group('v3 Migration: streak fields', () {
    test('missing streak fields default correctly', () {
      final json = {
        'userName': 'Test',
        'bibleTranslation': 'WEB',
      };
      final prefs = UserPreferences.fromJson(json);
      expect(prefs.currentStreak, 0);
      expect(prefs.lastListenDate, isNull);
    });

    test('saved streak fields load correctly', () {
      final json = {
        'userName': 'Test',
        'bibleTranslation': 'WEB',
        'currentStreak': 7,
        'lastListenDate': '2026-03-27',
      };
      final prefs = UserPreferences.fromJson(json);
      expect(prefs.currentStreak, 7);
      expect(prefs.lastListenDate, '2026-03-27');
    });
  });

  group('v3 Migration: bedtime mode fields', () {
    test('missing bedtime fields default correctly', () {
      final json = {
        'userName': 'Test',
        'bibleTranslation': 'WEB',
      };
      final prefs = UserPreferences.fromJson(json);
      expect(prefs.bedtimeModeEnabled, false);
      expect(prefs.sleepTimerMinutes, 5);
    });
  });

  group('v3 Migration: display labels', () {
    test('length labels are the new warm labels', () {
      expect(StoryLengthBucket.short.displayLabel, 'A Quick Moment');
      expect(StoryLengthBucket.full.displayLabel, 'A Quiet Story');
      expect(StoryLengthBucket.long.displayLabel, 'A Longer Listen');
    });

    test('duration labels exist', () {
      expect(StoryLengthBucket.short.durationLabel, '~2 min');
      expect(StoryLengthBucket.full.durationLabel, '~5 min');
      expect(StoryLengthBucket.long.durationLabel, '~10 min');
    });

    test('subtitles exist', () {
      expect(StoryLengthBucket.short.subtitle, isNotEmpty);
      expect(StoryLengthBucket.full.subtitle, isNotEmpty);
      expect(StoryLengthBucket.long.subtitle, isNotEmpty);
    });
  });

  group('v3 Migration: full round-trip', () {
    test('new fields survive toJson/fromJson round-trip', () {
      final original = UserPreferences(
        bibleTranslation: 'WEB',
        preferredLengthBucket: 'full',
        bedtimeModeEnabled: true,
        sleepTimerMinutes: 10,
        currentStreak: 5,
        lastListenDate: '2026-03-27',
        lastDetectedMood: 'grateful',
      );

      final json = original.toJson();
      final restored = UserPreferences.fromJson(json);

      expect(restored.preferredLengthBucket, 'full');
      expect(restored.bedtimeModeEnabled, true);
      expect(restored.sleepTimerMinutes, 10);
      expect(restored.currentStreak, 5);
      expect(restored.lastListenDate, '2026-03-27');
      expect(restored.lastDetectedMood, 'grateful');
    });

    test('copyWith preserves new fields', () {
      final original = UserPreferences(
        bibleTranslation: 'WEB',
        preferredLengthBucket: 'short',
        currentStreak: 3,
        lastListenDate: '2026-03-26',
      );

      final updated = original.copyWith(currentStreak: 4, lastListenDate: '2026-03-27');
      expect(updated.preferredLengthBucket, 'short'); // preserved
      expect(updated.currentStreak, 4); // updated
      expect(updated.lastListenDate, '2026-03-27'); // updated
    });
  });
}
