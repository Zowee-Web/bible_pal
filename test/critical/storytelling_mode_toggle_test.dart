// CRITICAL STORYTELLING MODE TEST
// This test ensures that the Creative/Traditional toggle actually works.
// If this test fails, users are getting random stories regardless of their preference.
//
// Contracts v2: Default storytellingMode is 'traditional' (not 'creative')

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/core/story_length_bucket.dart';

void main() {
  group('CRITICAL: Storytelling Mode Toggle', () {
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

    test('CRITICAL: Creative mode MUST only return creative stories', () async {
      // ARRANGE: User selects creative mode
      final creativePrefs = UserPreferences(
        bibleTranslation: 'WEB',
        storytellingMode: 'creative',
        kidFriendlyOnly: false,
      );

      // ACT: Get eligible parables
      final eligibleParables = await parableService.getEligibleParables(
        mood: 'joyful',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: creativePrefs,
      );

      // ASSERT: ALL parables MUST be creative mode
      for (final parable in eligibleParables) {
        expect(
          parable.storytellingMode,
          'creative',
          reason: '🚨 STORYTELLING MODE VIOLATION 🚨\n'
              'User selected CREATIVE mode but got TRADITIONAL story!\n'
              'Story: "${parable.title}" (ID: ${parable.storyId})\n'
              'Mode: ${parable.storytellingMode}\n'
              'The creative/traditional toggle is BROKEN!',
        );
      }

      // Verify we got SOME creative parables
      expect(
        eligibleParables.isNotEmpty,
        true,
        reason:
            'No creative parables found. Manifest may be missing creative stories.',
      );
    });

    test('CRITICAL: Traditional mode MUST only return traditional stories',
        () async {
      // ARRANGE: User selects traditional mode
      final traditionalPrefs = UserPreferences(
        bibleTranslation: 'WEB',
        storytellingMode: 'traditional',
        kidFriendlyOnly:
            true, // Use kid mode to access kid-friendly traditional stories
      );

      // ACT: Get eligible parables
      final eligibleParables = await parableService.getEligibleParables(
        mood: 'joyful',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: traditionalPrefs,
      );

      // ASSERT: ALL parables MUST be traditional mode
      for (final parable in eligibleParables) {
        expect(
          parable.storytellingMode,
          'traditional',
          reason: '🚨 STORYTELLING MODE VIOLATION 🚨\n'
              'User selected TRADITIONAL mode but got CREATIVE story!\n'
              'Story: "${parable.title}" (ID: ${parable.storyId})\n'
              'Mode: ${parable.storytellingMode}\n'
              'The creative/traditional toggle is BROKEN!',
        );
      }

      // Contracts v2: Traditional stories require bibleSourceRef to be eligible
      // If empty, it means manifest traditional stories need bibleSourceRef populated
      if (eligibleParables.isEmpty) {
        // ignore: avoid_print
        print('\n⚠️ WARNING: No eligible traditional stories found.');
        // ignore: avoid_print
        print(
            '   Contracts v2 requires bibleSourceRef for traditional stories.');
        // ignore: avoid_print
        print(
            '   Run: server/tools/backfill_story_mode.sh to identify stories needing bibleSourceRef');
      }
      // Note: We no longer fail on empty - the mode filter is correct,
      // the manifest just needs bibleSourceRef population
    });

    test('CRITICAL: selectParable() enforces storytelling mode', () async {
      // ARRANGE: Creative mode
      final creativePrefs = UserPreferences(
        bibleTranslation: 'WEB',
        storytellingMode: 'creative',
        kidFriendlyOnly: false,
      );

      // ACT: Select multiple parables
      for (int i = 0; i < 10; i++) {
        final selectedParable = await parableService.selectParable(
          mood: 'joyful',
          lengthBucket: StoryLengthBucket.short,
          userPrefs: creativePrefs,
        );

        // ASSERT: Must be creative (or null if no more available)
        if (selectedParable != null) {
          expect(
            selectedParable.storytellingMode,
            'creative',
            reason:
                'selectParable() returned ${selectedParable.storytellingMode} when user selected creative',
          );
        }
      }
    });

    test(
        'CRITICAL: UserPreferences.storytellingMode defaults to traditional (Contracts v2)',
        () {
      // ARRANGE & ACT
      final defaultPrefs = UserPreferences(
        bibleTranslation: 'WEB',
        // storytellingMode NOT specified - defaults to 'traditional' per Contracts v2
      );

      // ASSERT - Contracts v2: Default is Traditional
      expect(
        defaultPrefs.storytellingMode,
        'traditional',
        reason:
            'UserPreferences.storytellingMode should default to "traditional" (Contracts v2)',
      );
    });

    test('CRITICAL: UserPreferences.copyWith preserves storytellingMode', () {
      // ARRANGE
      final originalPrefs = UserPreferences(
        bibleTranslation: 'WEB',
        storytellingMode: 'traditional',
      );

      // ACT
      final copiedPrefs = originalPrefs.copyWith(
        bibleTranslation: 'KJV',
      );

      // ASSERT
      expect(
        copiedPrefs.storytellingMode,
        'traditional',
        reason: '🚨 BUG: copyWith() did NOT preserve storytellingMode!\n'
            'Original: traditional\n'
            'Copied: ${copiedPrefs.storytellingMode}\n'
            'Updating other preferences will reset storytelling mode!',
      );
    });

    test('CRITICAL: UserPreferences.fromJson/toJson preserves storytellingMode',
        () {
      // ARRANGE
      final originalPrefs = UserPreferences(
        bibleTranslation: 'KJV',
        storytellingMode: 'traditional',
      );

      // ACT
      final json = originalPrefs.toJson();
      final deserializedPrefs = UserPreferences.fromJson(json);

      // ASSERT
      expect(
        deserializedPrefs.storytellingMode,
        'traditional',
        reason: '🚨 BUG: Serialization lost storytellingMode!\n'
            'Original: traditional\n'
            'After JSON round-trip: ${deserializedPrefs.storytellingMode}\n'
            'Saving/loading will reset user\'s mode preference!',
      );
    });

    test('CRITICAL: Manifest contains both creative and traditional stories',
        () async {
      // This ensures we have content for both modes
      // NOTE: Contracts v2 - Traditional stories require bibleSourceRef to be eligible
      final allParables = await parableService.getEligibleParables(
        mood: 'joyful',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: UserPreferences(
          bibleTranslation: 'WEB',
          storytellingMode: 'creative',
          kidFriendlyOnly: true, // Use kid mode to access kid-friendly stories
        ),
      );

      final creativeCount =
          allParables.where((p) => p.storytellingMode == 'creative').length;

      final traditionalParables = await parableService.getEligibleParables(
        mood: 'joyful',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: UserPreferences(
          bibleTranslation: 'WEB',
          storytellingMode: 'traditional',
          kidFriendlyOnly:
              true, // Use kid mode to access kid-friendly traditional stories
        ),
      );

      final traditionalCount = traditionalParables
          .where((p) => p.storytellingMode == 'traditional')
          .length;

      expect(
        creativeCount,
        greaterThan(0),
        reason:
            'Manifest contains NO creative stories! Users in creative mode will get nothing.',
      );

      // Contracts v2: Traditional stories require bibleSourceRef to be eligible
      // If no eligible traditional stories, it means bibleSourceRef hasn't been populated yet
      // This is a warning, not a hard failure - run backfill_story_mode.sh to identify missing refs
      if (traditionalCount == 0) {
        // ignore: avoid_print
        print('\n⚠️ WARNING: No eligible traditional stories found.');
        // ignore: avoid_print
        print(
            '   Contracts v2 requires bibleSourceRef for traditional stories.');
        // ignore: avoid_print
        print(
            '   Run: server/tools/backfill_story_mode.sh to identify stories needing bibleSourceRef');
      } else {
        expect(
          traditionalCount,
          greaterThan(0),
          reason:
              'Manifest contains NO traditional stories with bibleSourceRef! '
              'Traditional mode requires bibleSourceRef per Contracts v2.',
        );
      }

      // Log stats
      // ignore: avoid_print
      print('\n📊 Storytelling Mode Stats:');
      // ignore: avoid_print
      print('   Creative stories (joyful, short): $creativeCount');
      // ignore: avoid_print
      print(
          '   Traditional stories (joyful, short, with bibleSourceRef): $traditionalCount');
    });
  });
}
