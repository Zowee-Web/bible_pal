// CRITICAL VOICE CONSENT GATE BEHAVIOR TEST
// This test verifies the consent gate BLOCKS audio when consent is null or false.
// Tests run at the preferences/provider level to ensure the gate logic is enforced.
//
// DO NOT DISABLE OR WEAKEN THIS TEST.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/providers/app_state_notifier.dart';
import 'package:bible_pal/providers/service_providers.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/models/user_preferences.dart';

void main() {
  group('CRITICAL: Voice Consent Gate Behavior', () {
    late ProviderContainer container;
    late StorageService storageService;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() async {
      // Initialize with clean preferences
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storageService = StorageService(prefs);

      // Create container with storage override only
      // We don't need audio for consent gate testing
      container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWith((ref) async => storageService),
        ],
      );

      // Wait for app state to initialize
      await container.read(appStateProvider.future);
    });

    tearDown(() {
      container.dispose();
    });

    test(
        'CRITICAL: play() would return needsConsent when storyNarrationEnabled is null',
        () async {
      // ARRANGE: Default state (consent is null)
      final appState = await container.read(appStateProvider.future);

      // ASSERT: Verify consent is null (default state)
      expect(
        appState.userPreferences.storyNarrationEnabled,
        isNull,
        reason:
            '🚨 CONSENT GATE: storyNarrationEnabled should be null by default',
      );

      // ASSERT: isStoryNarrationEnabled returns false for null
      // This is what ParablePlayerNotifier.play() checks
      expect(
        appState.userPreferences.isStoryNarrationEnabled,
        false,
        reason:
            '🚨 CONSENT GATE: isStoryNarrationEnabled must return false when null',
      );

      // ASSERT: hasAsked returns false (needs dialog)
      expect(
        appState.userPreferences.hasAskedStoryNarrationConsent,
        false,
        reason:
            '🚨 CONSENT GATE: hasAskedStoryNarrationConsent must return false when null',
      );
    });

    test('CRITICAL: consent gate allows play after enabling', () async {
      // ARRANGE: Enable story narration consent
      final appNotifier = container.read(appStateProvider.notifier);
      await appNotifier.updateStoryNarrationConsent(true);

      // ACT: Read updated state
      final appState = await container.read(appStateProvider.future);

      // ASSERT: Consent is now true
      expect(
        appState.userPreferences.storyNarrationEnabled,
        true,
        reason: 'storyNarrationEnabled should be true after enabling',
      );

      expect(
        appState.userPreferences.isStoryNarrationEnabled,
        true,
        reason: 'isStoryNarrationEnabled should return true when enabled',
      );

      expect(
        appState.userPreferences.hasAskedStoryNarrationConsent,
        true,
        reason: 'hasAskedStoryNarrationConsent should be true after enabling',
      );

      // ASSERT: Version is set
      expect(
        appState.userPreferences.voiceConsentVersion,
        currentVoiceConsentVersion,
        reason: 'voiceConsentVersion should be set when consent is granted',
      );
    });

    test('CRITICAL: consent gate blocks after disabling', () async {
      // ARRANGE: First enable, then disable
      final appNotifier = container.read(appStateProvider.notifier);
      await appNotifier.updateStoryNarrationConsent(true);
      await appNotifier.updateStoryNarrationConsent(false);

      // ACT: Read updated state
      final appState = await container.read(appStateProvider.future);

      // ASSERT: Consent is false (blocked)
      expect(
        appState.userPreferences.storyNarrationEnabled,
        false,
        reason:
            '🚨 CONSENT GATE: storyNarrationEnabled should be false after disabling',
      );

      expect(
        appState.userPreferences.isStoryNarrationEnabled,
        false,
        reason:
            '🚨 CONSENT GATE: isStoryNarrationEnabled must return false when disabled',
      );

      // But hasAsked should still be true (user was asked)
      expect(
        appState.userPreferences.hasAskedStoryNarrationConsent,
        true,
        reason: 'hasAskedStoryNarrationConsent should be true (user was asked)',
      );
    });

    test('CRITICAL: consent persists across provider recreation', () async {
      // ARRANGE: Enable consent
      final appNotifier = container.read(appStateProvider.notifier);
      await appNotifier.updateStoryNarrationConsent(true);

      // ACT: Dispose and recreate container (simulates app restart)
      container.dispose();

      // Recreate with same preferences (SharedPreferences persists in test)
      final prefs = await SharedPreferences.getInstance();
      storageService = StorageService(prefs);

      container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWith((ref) async => storageService),
        ],
      );

      // Wait for initialization
      final appState = await container.read(appStateProvider.future);

      // ASSERT: Consent should persist
      expect(
        appState.userPreferences.storyNarrationEnabled,
        true,
        reason: '🚨 CONSENT GATE: Consent must persist across app restarts',
      );

      expect(
        appState.userPreferences.voiceConsentVersion,
        currentVoiceConsentVersion,
        reason: 'voiceConsentVersion must persist across app restarts',
      );
    });

    test('PAL greetings consent is independent from story narration', () async {
      // ARRANGE: Enable story narration but NOT PAL greetings
      final appNotifier = container.read(appStateProvider.notifier);
      await appNotifier.updateStoryNarrationConsent(true);

      // ACT: Read state
      final appState = await container.read(appStateProvider.future);

      // ASSERT: Story narration enabled, PAL greetings still null
      expect(appState.userPreferences.isStoryNarrationEnabled, true);
      expect(
        appState.userPreferences.palGreetingsEnabled,
        isNull,
        reason:
            'PAL greetings should remain null when only story narration is updated',
      );
      expect(appState.userPreferences.isPalGreetingsEnabled, false);
    });

    test('Both consent types can be set independently', () async {
      // ARRANGE: Enable story narration, disable PAL greetings
      final appNotifier = container.read(appStateProvider.notifier);
      await appNotifier.updateStoryNarrationConsent(true);
      await appNotifier.updatePalGreetingsConsent(false);

      // ACT: Read state
      final appState = await container.read(appStateProvider.future);

      // ASSERT: Independent states
      expect(appState.userPreferences.storyNarrationEnabled, true);
      expect(appState.userPreferences.palGreetingsEnabled, false);
      expect(appState.userPreferences.isStoryNarrationEnabled, true);
      expect(appState.userPreferences.isPalGreetingsEnabled, false);
    });

    test('updateVoiceConsent sets both at once', () async {
      // ARRANGE: Set both via updateVoiceConsent
      final appNotifier = container.read(appStateProvider.notifier);
      await appNotifier.updateVoiceConsent(
        storyNarrationEnabled: true,
        palGreetingsEnabled: false,
      );

      // ACT: Read state
      final appState = await container.read(appStateProvider.future);

      // ASSERT: Both set correctly
      expect(appState.userPreferences.storyNarrationEnabled, true);
      expect(appState.userPreferences.palGreetingsEnabled, false);
      expect(appState.userPreferences.voiceConsentVersion,
          currentVoiceConsentVersion);
    });
  });
}
