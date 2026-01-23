// CRITICAL STORY TRANSLATION FILTER TEST
// This test ensures that stories are correctly filtered by languageStyle (Contracts v2).
// languageStyle (WEB/KJV) must match story's translationId for proper content segregation.
//
// DO NOT DISABLE OR WEAKEN THIS TEST.

library;

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/core/story_length_bucket.dart';

void main() {
  group('CRITICAL: Story Translation Filtering', () {
    late ParableService parableService;
    late StorageService storageService;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storageService = StorageService(prefs);
      parableService = ParableService(storageService, null, true);
    });

    test('CRITICAL: All parables in manifest MUST have translationId field',
        () async {
      // ARRANGE: Load manifest.json directly to check ALL entries
      final jsonContent =
          await rootBundle.loadString('assets/stories/manifest.json');
      final manifestData = jsonDecode(jsonContent) as Map<String, dynamic>;
      final parablesList = manifestData['parables'] as List<dynamic>;

      // ASSERT: Every entry in manifest must have translationId
      for (final json in parablesList) {
        final entry = json as Map<String, dynamic>;
        final storyId = entry['storyId'] as String;
        final title = entry['title'] as String;

        // Check translationId exists
        expect(
          entry.containsKey('translationId'),
          true,
          reason: '🚨 CRITICAL: Parable "$title" (ID: $storyId) '
              'is missing translationId field in manifest.json!\n'
              'All parables MUST have translationId to support Story Language filtering.',
        );

        // Check translationId is valid
        final translationId = entry['translationId'] as String?;
        expect(
          translationId != null && ['WEB', 'KJV'].contains(translationId),
          true,
          reason: '🚨 CRITICAL: Parable "$title" (ID: $storyId) '
              'has invalid translationId: "$translationId".\n'
              'Only WEB or KJV are allowed for storyLanguage filtering.',
        );
      }

      // Verify we checked a reasonable number of entries
      expect(
        parablesList.length,
        greaterThan(10),
        reason:
            'Manifest should have more than 10 parables. Found: ${parablesList.length}',
      );
    });

    test('CRITICAL: WEB stories MUST be returned when storyLanguage is WEB',
        () async {
      // ARRANGE: User with WEB preference (default)
      // Note: storyLanguage will be added in Phase 2, currently defaults to WEB in ParableService
      final webPrefs = UserPreferences(
        bibleTranslation: 'WEB',
        storytellingMode: 'creative',
        kidFriendlyOnly: false,
      );

      // ACT: Get eligible parables
      final eligibleParables = await parableService.getEligibleParables(
        mood: 'joyful',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: webPrefs,
      );

      // ASSERT: All returned parables must have translationId = 'WEB'
      for (final parable in eligibleParables) {
        expect(
          parable.translationId,
          'WEB',
          reason: '🚨 STORY LANGUAGE VIOLATION 🚨\n'
              'Parable "${parable.title}" (ID: ${parable.storyId}) has translationId="${parable.translationId}"\n'
              'but was returned when storyLanguage=WEB.\n'
              'Stories must be filtered by translationId to match user\'s Story Language preference.',
        );
      }
    });

    test('CRITICAL: Parable model correctly serializes translationId', () {
      // ARRANGE: Create a parable with WEB translation
      final webParable = Parable(
        storyId: 'test_web_001',
        title: 'Test WEB Story',
        mood: 'joyful',
        length: 5,
        storytellingMode: 'creative',
        translationId: 'WEB',
        kidFriendly: false,
      );

      // ACT: Serialize and deserialize
      final json = webParable.toJson();
      final deserializedParable = Parable.fromJson(json);

      // ASSERT: translationId survives round-trip
      expect(json['translationId'], 'WEB');
      expect(deserializedParable.translationId, 'WEB');

      // Test KJV as well
      final kjvParable = Parable(
        storyId: 'test_kjv_001',
        title: 'Test KJV Story',
        mood: 'weary',
        length: 10,
        storytellingMode: 'traditional',
        translationId: 'KJV',
        kidFriendly: true,
      );

      final kjvJson = kjvParable.toJson();
      final deserializedKjv = Parable.fromJson(kjvJson);

      expect(kjvJson['translationId'], 'KJV');
      expect(deserializedKjv.translationId, 'KJV');
    });

    test('CRITICAL: Parable.fromJson defaults to WEB if translationId missing',
        () {
      // ARRANGE: JSON without translationId (legacy data)
      final legacyJson = {
        'storyId': 'legacy_001',
        'title': 'Legacy Story',
        'mood': 'joyful',
        'emotionalTags': <String>[],
        'length': 5,
        'storytellingMode': 'creative',
        'kidFriendly': false,
        // Note: no translationId field
      };

      // ACT: Parse legacy JSON
      final parable = Parable.fromJson(legacyJson);

      // ASSERT: Should default to WEB for backwards compatibility
      expect(
        parable.translationId,
        'WEB',
        reason: 'Legacy parables without translationId should default to WEB '
            'for backwards compatibility.',
      );
    });

    test('CRITICAL: Parable.copyWith preserves translationId', () {
      // ARRANGE: Create a KJV parable
      final originalParable = Parable(
        storyId: 'test_kjv_002',
        title: 'Original Title',
        mood: 'weary',
        length: 10,
        storytellingMode: 'traditional',
        translationId: 'KJV',
        kidFriendly: false,
      );

      // ACT: Copy with different title
      final copiedParable = originalParable.copyWith(
        title: 'New Title',
      );

      // ASSERT: translationId must be preserved
      expect(
        copiedParable.translationId,
        'KJV',
        reason: '🚨 CRITICAL BUG 🚨\n'
            'Parable.copyWith() did NOT preserve translationId!\n'
            'Original: translationId=KJV\n'
            'Copied: translationId=${copiedParable.translationId}\n'
            'This could cause stories to be served with wrong translation.',
      );
    });

    test('CRITICAL: Parable.copyWith can change translationId', () {
      // ARRANGE: Create a WEB parable
      final originalParable = Parable(
        storyId: 'test_web_002',
        title: 'Test Story',
        mood: 'joyful',
        length: 5,
        storytellingMode: 'creative',
        translationId: 'WEB',
        kidFriendly: false,
      );

      // ACT: Copy with different translationId
      final copiedParable = originalParable.copyWith(
        translationId: 'KJV',
      );

      // ASSERT: translationId should be changed
      expect(copiedParable.translationId, 'KJV');
      expect(originalParable.translationId, 'WEB'); // Original unchanged
    });

    test('CRITICAL: KJV stories MUST be returned when languageStyle is KJV',
        () async {
      // ARRANGE: User with KJV language style preference (Contracts v2)
      final kjvPrefs = UserPreferences(
        bibleTranslation: 'KJV',
        languageStyle:
            'KJV', // Explicitly set KJV language style (Contracts v2)
        storytellingMode: 'creative',
        kidFriendlyOnly: false,
      );

      // ACT: Get eligible parables
      final eligibleParables = await parableService.getEligibleParables(
        mood: 'joyful',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: kjvPrefs,
      );

      // ASSERT: All returned parables must have translationId = 'KJV'
      // Note: If no KJV stories exist yet, this test passes with empty results
      for (final parable in eligibleParables) {
        expect(
          parable.translationId,
          'KJV',
          reason: '🚨 LANGUAGE STYLE VIOLATION 🚨\n'
              'Parable "${parable.title}" (ID: ${parable.storyId}) has translationId="${parable.translationId}"\n'
              'but was returned when languageStyle=KJV.\n'
              'Stories must be filtered by translationId to match user\'s languageStyle preference.',
        );
      }
    });

    test('CRITICAL: UserPreferences.languageStyle defaults to WEB', () {
      // ARRANGE & ACT: Create UserPreferences with defaults
      final defaultPrefs = UserPreferences.defaults();

      // ASSERT: languageStyle should default to WEB (Contracts v2)
      expect(
        defaultPrefs.languageStyle,
        'WEB',
        reason: 'UserPreferences.languageStyle should default to WEB (Modern).',
      );
    });

    test('CRITICAL: UserPreferences.languageStyle validates to WEB or KJV only',
        () {
      // ARRANGE: JSON with invalid languageStyle (use constructed invalid value
      // to avoid literal banned translation tokens in test code)
      const invalidValue = 'INVALID_TRANSLATION'; // Any non-WEB/KJV value
      final invalidJson = {
        'bibleTranslation': 'WEB',
        'languageStyle': invalidValue,
        'storytellingMode': 'creative',
        'kidFriendlyOnly': false,
      };

      // ACT: Parse JSON with invalid languageStyle
      final prefs = UserPreferences.fromJson(invalidJson);

      // ASSERT: Invalid languageStyle should be sanitized to WEB
      expect(
        prefs.languageStyle,
        'WEB',
        reason:
            '🚨 CRITICAL: Invalid languageStyle "$invalidValue" was NOT sanitized!\n'
            'Only WEB or KJV are allowed for languageStyle.\n'
            'Invalid values must be reset to WEB.',
      );
    });

    test('CRITICAL: UserPreferences.copyWith preserves languageStyle', () {
      // ARRANGE: Create preferences with KJV language style
      final originalPrefs = UserPreferences(
        bibleTranslation: 'KJV',
        languageStyle: 'KJV',
        storytellingMode: 'creative',
        kidFriendlyOnly: false,
      );

      // ACT: Copy with a different field changed
      final copiedPrefs = originalPrefs.copyWith(
        storytellingMode: 'traditional',
      );

      // ASSERT: languageStyle MUST be preserved
      expect(
        copiedPrefs.languageStyle,
        'KJV',
        reason: '🚨 CRITICAL BUG 🚨\n'
            'UserPreferences.copyWith() did NOT preserve languageStyle!\n'
            'Original: languageStyle=KJV\n'
            'Copied: languageStyle=${copiedPrefs.languageStyle}\n'
            'This means updating other preferences will accidentally change language style!',
      );
    });

    test('CRITICAL: UserPreferences.fromJson/toJson preserves languageStyle',
        () {
      // ARRANGE: Create preferences with KJV language style
      final originalPrefs = UserPreferences(
        bibleTranslation: 'KJV',
        languageStyle: 'KJV',
        storytellingMode: 'traditional',
        kidFriendlyOnly: true,
      );

      // ACT: Serialize to JSON and deserialize
      final json = originalPrefs.toJson();
      final deserializedPrefs = UserPreferences.fromJson(json);

      // ASSERT: languageStyle MUST survive serialization
      expect(
        deserializedPrefs.languageStyle,
        'KJV',
        reason: '🚨 CRITICAL BUG 🚨\n'
            'UserPreferences serialization lost languageStyle!\n'
            'Original: languageStyle=KJV\n'
            'After JSON round-trip: languageStyle=${deserializedPrefs.languageStyle}\n'
            'This means saving/loading preferences will lose language style setting!',
      );

      // Test WEB case too
      final webPrefs = UserPreferences(
        bibleTranslation: 'WEB',
        languageStyle: 'WEB',
        storytellingMode: 'creative',
        kidFriendlyOnly: false,
      );

      final webJson = webPrefs.toJson();
      final deserializedWeb = UserPreferences.fromJson(webJson);

      expect(
        deserializedWeb.languageStyle,
        'WEB',
        reason: 'UserPreferences serialization failed for languageStyle=WEB',
      );
    });
  });
}
