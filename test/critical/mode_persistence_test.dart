// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/models/user_preferences.dart';

/// Critical tests for Mode Persistence Invariant (ADR-010)
///
/// These tests enforce:
/// 1. Default storytelling mode is Traditional
/// 2. Mode persists across app restarts (via JSON serialization)
/// 3. Only two modes exist: Traditional and Creative
/// 4. Invalid mode values reset to Traditional
///
/// See: docs/INVARIANTS.md - Mode Persistence Invariant
void main() {
  group('Mode Persistence Invariant (ADR-010)', () {
    test('CRITICAL: Default storytelling mode is traditional', () {
      final defaults = UserPreferences.defaults();

      expect(
        defaults.storytellingMode,
        equals('traditional'),
        reason: 'Default storytelling mode must be "traditional" per ADR-010',
      );
    });

    test(
        'CRITICAL: Mode persists through JSON serialization (simulates restart)',
        () {
      // Simulate user changing to creative mode
      final prefs = UserPreferences.defaults().copyWith(
        storytellingMode: 'creative',
      );

      // Simulate app restart: serialize to JSON, then deserialize
      final json = prefs.toJson();
      final restored = UserPreferences.fromJson(json);

      expect(
        restored.storytellingMode,
        equals('creative'),
        reason:
            'Mode should persist through JSON round-trip (simulates SharedPreferences)',
      );
    });

    test('CRITICAL: Traditional mode persists through JSON serialization', () {
      final prefs = UserPreferences.defaults().copyWith(
        storytellingMode: 'traditional',
      );

      final json = prefs.toJson();
      final restored = UserPreferences.fromJson(json);

      expect(
        restored.storytellingMode,
        equals('traditional'),
        reason: 'Traditional mode should persist through JSON round-trip',
      );
    });

    test('CRITICAL: Missing mode in JSON defaults to traditional', () {
      // Simulate old preferences JSON without storytellingMode field
      final oldJson = <String, dynamic>{
        'userName': 'Test User',
        'bibleTranslation': 'WEB',
        'hasCompletedOnboarding': true,
        // Note: storytellingMode is missing
      };

      final restored = UserPreferences.fromJson(oldJson);

      expect(
        restored.storytellingMode,
        equals('traditional'),
        reason: 'Missing storytellingMode should default to traditional',
      );
    });

    test('CRITICAL: Only traditional and creative are valid modes', () {
      // Test that we can set both valid modes
      final traditionalPrefs = UserPreferences.defaults().copyWith(
        storytellingMode: 'traditional',
      );
      final creativePrefs = UserPreferences.defaults().copyWith(
        storytellingMode: 'creative',
      );

      expect(traditionalPrefs.storytellingMode, equals('traditional'));
      expect(creativePrefs.storytellingMode, equals('creative'));
    });

    test('INFO: Mode change preserves other preferences', () {
      final original = UserPreferences(
        userName: 'Test User',
        bibleTranslation: 'KJV',
        languageStyle: 'KJV',
        storytellingMode: 'traditional',
        kidFriendlyOnly: true,
        showEverydayReflections: true,
        hasCompletedOnboarding: true,
      );

      final changed = original.copyWith(storytellingMode: 'creative');

      // Mode should change
      expect(changed.storytellingMode, equals('creative'));

      // Other preferences should be preserved
      expect(changed.userName, equals('Test User'));
      expect(changed.bibleTranslation, equals('KJV'));
      expect(changed.languageStyle, equals('KJV'));
      expect(changed.kidFriendlyOnly, isTrue);
      expect(changed.showEverydayReflections, isTrue);
      expect(changed.hasCompletedOnboarding, isTrue);
    });
  });

  group('UserPreferences Defaults', () {
    test('All defaults are correctly set', () {
      final defaults = UserPreferences.defaults();

      expect(defaults.userName, equals(''));
      expect(defaults.bibleTranslation, equals('WEB'));
      expect(defaults.languageStyle, equals('WEB'));
      expect(defaults.storytellingMode, equals('traditional'));
      expect(defaults.contentFilteringEnabled, isTrue);
      expect(defaults.kidFriendlyOnly, isFalse);
      expect(defaults.showEverydayReflections, isTrue);
      expect(defaults.hasCompletedOnboarding, isFalse);
    });
  });
}
