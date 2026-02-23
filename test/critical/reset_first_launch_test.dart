// CRITICAL TEST: Reset First Launch functionality
//
// This test verifies that StorageService.resetFirstLaunchDevOnly() works correctly.
// After reset, onboarding must be shown again (firstLaunchRequired == true).
//
// This is a developer tool for testing onboarding flows on macOS and other platforms
// where local storage persists between runs.

@Tags(['critical'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/features/onboarding/first_launch_screen.dart'
    show kFirstLaunchCompleteKey;

void main() {
  group('CRITICAL: Reset First Launch', () {
    late StorageService storageService;
    late SharedPreferences prefs;

    setUp(() async {
      // Initialize with completed onboarding state
      SharedPreferences.setMockInitialValues({
        kFirstLaunchCompleteKey: true,
        'user_preferences': '''
        {
          "userName": "TestUser",
          "bibleTranslation": "WEB",
          "languageStyle": "WEB",
          "storytellingMode": "traditional",
          "contentFilteringEnabled": true,
          "kidFriendlyOnly": false,
          "showEverydayReflections": true,
          "hasCompletedOnboarding": true,
          "storyNarrationEnabled": true,
          "palGreetingsEnabled": true,
          "voiceConsentVersion": 1
        }
        ''',
      });
      prefs = await SharedPreferences.getInstance();
      storageService = StorageService(prefs);
    });

    test('CRITICAL: Before reset - onboarding is complete', () async {
      // Verify initial state: onboarding is complete
      final isFirstLaunch = prefs.getBool(kFirstLaunchCompleteKey) != true;
      expect(isFirstLaunch, false,
          reason: 'Before reset, first launch should be complete');

      final userPrefs = await storageService.getUserPreferences();
      expect(userPrefs.hasCompletedOnboarding, true,
          reason: 'Before reset, hasCompletedOnboarding should be true');
      expect(userPrefs.userName, 'TestUser',
          reason: 'Before reset, userName should be set');
      expect(userPrefs.storyNarrationEnabled, true,
          reason: 'Before reset, voice consent should be set');
    });

    test('CRITICAL: After resetFirstLaunchDevOnly - onboarding is required',
        () async {
      // Call the real method
      await storageService.resetFirstLaunchDevOnly();

      // Verify reset state: onboarding is now required
      final isFirstLaunchAfterReset =
          prefs.getBool(kFirstLaunchCompleteKey) != true;
      expect(isFirstLaunchAfterReset, true,
          reason:
              '🚨 CRITICAL: After reset, first launch check should return true (onboarding required)');

      final resetUserPrefs = await storageService.getUserPreferences();
      expect(resetUserPrefs.hasCompletedOnboarding, false,
          reason:
              '🚨 CRITICAL: After reset, hasCompletedOnboarding must be false');
      expect(resetUserPrefs.userName, '',
          reason: '🚨 CRITICAL: After reset, userName must be cleared');
      // Voice features default to ON even after reset (fromJson defaults null → true)
      expect(resetUserPrefs.storyNarrationEnabled, true,
          reason:
              '🚨 CRITICAL: After reset, voice features default to ON (true)');
      expect(resetUserPrefs.palGreetingsEnabled, true,
          reason:
              '🚨 CRITICAL: After reset, PAL greetings default to ON (true)');
      expect(resetUserPrefs.voiceConsentVersion, null,
          reason:
              '🚨 CRITICAL: After reset, voice consent version must be null');
    });

    test('CRITICAL: resetFirstLaunchDevOnly preserves non-onboarding preferences',
        () async {
      // Get current prefs before reset
      final beforePrefs = await storageService.getUserPreferences();

      // Call the real method
      await storageService.resetFirstLaunchDevOnly();

      // Verify preserved fields
      final afterPrefs = await storageService.getUserPreferences();
      expect(afterPrefs.bibleTranslation, beforePrefs.bibleTranslation,
          reason: 'bibleTranslation should be preserved after reset');
      expect(afterPrefs.languageStyle, beforePrefs.languageStyle,
          reason: 'languageStyle should be preserved after reset');
      expect(afterPrefs.storytellingMode, beforePrefs.storytellingMode,
          reason: 'storytellingMode should be preserved after reset');
      expect(afterPrefs.kidFriendlyOnly, beforePrefs.kidFriendlyOnly,
          reason: 'kidFriendlyOnly should be preserved after reset');
      expect(
          afterPrefs.showEverydayReflections, beforePrefs.showEverydayReflections,
          reason: 'showEverydayReflections should be preserved after reset');
      expect(afterPrefs.contentFilteringEnabled,
          beforePrefs.contentFilteringEnabled,
          reason: 'contentFilteringEnabled should be preserved after reset');
    });

    test('CRITICAL: resetFirstLaunchDevOnly does NOT delete favorites or history',
        () async {
      // Add some favorites and history with complete schema
      await prefs.setString('favorites',
          '[{"storyId":"test_story","title":"Test","mood":"joyful","length":5,"scriptureSources":[],"dateSaved":"2024-01-01T00:00:00.000Z"}]');
      await prefs.setString('history',
          '[{"storyId":"test_story","title":"Test","mood":"joyful","length":5,"scriptureSources":[],"timestamp":"2024-01-01T00:00:00.000Z"}]');

      // Call the real method
      await storageService.resetFirstLaunchDevOnly();

      // Verify favorites and history are preserved
      final favorites = await storageService.getFavorites();
      final history = await storageService.getHistory();

      expect(favorites.length, 1,
          reason: '🚨 CRITICAL: Favorites must NOT be deleted by reset');
      expect(history.length, 1,
          reason: '🚨 CRITICAL: History must NOT be deleted by reset');
    });

    test('isOnboardingComplete returns false after resetFirstLaunchDevOnly',
        () async {
      // Call the real method
      await storageService.resetFirstLaunchDevOnly();

      // Check the derived property
      final afterPrefs = await storageService.getUserPreferences();
      expect(afterPrefs.isOnboardingComplete, false,
          reason: 'isOnboardingComplete should return false after reset');
    });
  });
}
