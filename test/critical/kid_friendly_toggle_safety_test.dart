// CRITICAL KID SAFETY TEST
// This test MUST pass to protect children from inappropriate content.
// If this test fails, the kid-friendly toggle is broken and children are at risk.
//
// DO NOT DISABLE OR WEAKEN THIS TEST.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/storage_service.dart';

void main() {
  group('CRITICAL: Kid-Friendly Toggle Safety', () {
    late ParableService parableService;
    late StorageService storageService;

    setUpAll(() {
      // Initialize Flutter binding for tests
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storageService = StorageService(prefs);
      // Initialize ParableService in test mode (allows testing without audio files)
      parableService = ParableService(storageService, null, true);
    });

    test('CRITICAL: Kid mode MUST filter out non-kid-friendly parables', () async {
      // ARRANGE: Create user preferences with kid mode ON
      final kidModePrefs = UserPreferences(
        faithTradition: 'Protestant',
        bibleTranslation: 'WEB',
        storytellingMode: 'creative',
        kidFriendlyOnly: true, // KID MODE ENABLED
      );

      // ACT: Get eligible parables for a joyful mood, 5-minute story
      final eligibleParables = await parableService.getEligibleParables(
        mood: 'joyful',
        lengthMinutes: 5,
        userPrefs: kidModePrefs,
      );

      // ASSERT: EVERY parable returned MUST be kid-friendly
      for (final parable in eligibleParables) {
        expect(
          parable.kidFriendly,
          true,
          reason: '🚨 CRITICAL SAFETY VIOLATION 🚨\n'
              'Parable "${parable.title}" (ID: ${parable.storyId}) is NOT kid-friendly\n'
              'but was returned when kidFriendlyOnly=true.\n'
              'This exposes children to inappropriate content!\n'
              'Fix immediately: Check ParableService.getEligibleParables() filtering logic.',
        );
      }

      // Additional check: Verify we got SOME kid-friendly parables
      // (Empty result is suspicious - might indicate broken filtering)
      expect(
        eligibleParables.isNotEmpty,
        true,
        reason: '⚠️  WARNING: No kid-friendly parables found.\n'
            'This might indicate the manifest has no kid-friendly stories,\n'
            'or the filtering logic is broken.\n'
            'Verify: (1) Manifest has kidFriendly=true parables, (2) Filtering works.',
      );
    });

    test('CRITICAL: selectParable() MUST enforce kid-friendly filter', () async {
      // ARRANGE: Kid mode enabled
      final kidModePrefs = UserPreferences(
        faithTradition: 'Protestant',
        bibleTranslation: 'WEB',
        storytellingMode: 'creative',
        kidFriendlyOnly: true,
      );

      // ACT: Select a parable (tries multiple times to ensure consistency)
      for (int i = 0; i < 10; i++) {
        final selectedParable = await parableService.selectParable(
          mood: 'joyful',
          lengthMinutes: 5,
          userPrefs: kidModePrefs,
        );

        // ASSERT: Selected parable MUST be kid-friendly (or null if none available)
        if (selectedParable != null) {
          expect(
            selectedParable.kidFriendly,
            true,
            reason: '🚨 CRITICAL SAFETY VIOLATION 🚨\n'
                'selectParable() returned non-kid-friendly parable:\n'
                'Title: "${selectedParable.title}"\n'
                'ID: ${selectedParable.storyId}\n'
                'Kid-Friendly: ${selectedParable.kidFriendly}\n'
                'User had kidFriendlyOnly=true but got inappropriate content!\n'
                'This is a CRITICAL BUG that endangers children.',
          );
        }
      }
    });

    test('CRITICAL: Adult mode MUST ONLY return non-kid-friendly parables', () async {
      // ARRANGE: Kid mode disabled (adult mode)
      final adultModePrefs = UserPreferences(
        faithTradition: '', // Empty to match test data with "Unspecified"
        bibleTranslation: 'WEB',
        storytellingMode: 'creative',
        kidFriendlyOnly: false, // KID MODE DISABLED (adults want adult content)
      );

      // ACT: Get eligible parables
      final eligibleParables = await parableService.getEligibleParables(
        mood: 'joyful',
        lengthMinutes: 5,
        userPrefs: adultModePrefs,
      );

      // ASSERT: EVERY parable returned MUST be non-kid-friendly (adult content only)
      for (final parable in eligibleParables) {
        expect(
          parable.kidFriendly,
          false,
          reason: '🚨 ADULT MODE VIOLATION 🚨\\n'
              'Parable "${parable.title}" (ID: ${parable.storyId}) is kid-friendly\\n'
              'but was returned when kidFriendlyOnly=false.\\n'
              'Adults should ONLY get adult content!\\n'
              'Fix immediately: Check ParableService.getEligibleParables() filtering logic.',
        );
      }

      // Additional check: Verify we got SOME non-kid-friendly parables
      // (Empty result is suspicious - might indicate broken filtering or no adult content)
      expect(
        eligibleParables.isNotEmpty,
        true,
        reason: '⚠️  WARNING: No non-kid-friendly parables found.\\n'
            'This might indicate the manifest has no adult content,\\n'
            'or the filtering logic is broken.\\n'
            'Verify: (1) Manifest has kidFriendly=false parables, (2) Filtering works.',
      );
    });

    test('CRITICAL: UserPreferences.kidFriendlyOnly defaults to FALSE (safe default)', () {
      // ARRANGE & ACT: Create UserPreferences with no kidFriendlyOnly specified
      final defaultPrefs = UserPreferences(
        faithTradition: 'Protestant',
        bibleTranslation: 'WEB',
        storytellingMode: 'creative',
        // kidFriendlyOnly NOT specified - should default to false
      );

      // ASSERT: Defaults to false (adult mode)
      expect(
        defaultPrefs.kidFriendlyOnly,
        false,
        reason: 'UserPreferences.kidFriendlyOnly should default to false (adult mode).\n'
            'If it defaults to true, adults will be restricted.\n'
            'If it defaults to null, we have undefined behavior.',
      );
    });

    test('CRITICAL: UserPreferences.copyWith preserves kidFriendlyOnly', () {
      // ARRANGE: Create preferences with kid mode ON
      final originalPrefs = UserPreferences(
        faithTradition: 'Protestant',
        bibleTranslation: 'WEB',
        storytellingMode: 'creative',
        kidFriendlyOnly: true,
      );

      // ACT: Copy with a different field changed
      final copiedPrefs = originalPrefs.copyWith(
        storytellingMode: 'traditional',
      );

      // ASSERT: kidFriendlyOnly MUST be preserved
      expect(
        copiedPrefs.kidFriendlyOnly,
        true,
        reason: '🚨 CRITICAL BUG 🚨\n'
            'UserPreferences.copyWith() did NOT preserve kidFriendlyOnly!\n'
            'Original: kidFriendlyOnly=true\n'
            'Copied: kidFriendlyOnly=${copiedPrefs.kidFriendlyOnly}\n'
            'This means updating other preferences will accidentally turn off kid mode!',
      );
    });

    test('CRITICAL: UserPreferences.fromJson/toJson preserves kidFriendlyOnly', () {
      // ARRANGE: Create preferences with kid mode ON
      final originalPrefs = UserPreferences(
        faithTradition: 'Catholic',
        bibleTranslation: 'KJV',
        storytellingMode: 'traditional',
        kidFriendlyOnly: true,
      );

      // ACT: Serialize to JSON and deserialize
      final json = originalPrefs.toJson();
      final deserializedPrefs = UserPreferences.fromJson(json);

      // ASSERT: kidFriendlyOnly MUST survive serialization
      expect(
        deserializedPrefs.kidFriendlyOnly,
        true,
        reason: '🚨 CRITICAL BUG 🚨\n'
            'UserPreferences serialization lost kidFriendlyOnly!\n'
            'Original: kidFriendlyOnly=true\n'
            'After JSON round-trip: kidFriendlyOnly=${deserializedPrefs.kidFriendlyOnly}\n'
            'This means saving/loading preferences will lose kid mode setting!',
      );

      // Test false case too
      final adultPrefs = UserPreferences(
        faithTradition: 'Orthodox',
        bibleTranslation: 'ASV',
        storytellingMode: 'creative',
        kidFriendlyOnly: false,
      );

      final adultJson = adultPrefs.toJson();
      final deserializedAdult = UserPreferences.fromJson(adultJson);

      expect(
        deserializedAdult.kidFriendlyOnly,
        false,
        reason: 'UserPreferences serialization failed for kidFriendlyOnly=false',
      );
    });
  });
}
