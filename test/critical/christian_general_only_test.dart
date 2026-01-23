// ignore_for_file: avoid_print
@Tags(['critical'])
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Christian General Only Invariant Enforcement Tests
///
/// These tests scan the entire codebase to ensure that denomination/tradition
/// concepts have been completely removed. Bible PAL serves all Christians
/// with a unified "Christian General" experience.
///
/// See: docs/INVARIANTS.md - Christian General Only Invariant (NON-NEGOTIABLE)
///
/// BANNED PATTERNS:
/// - faithTradition as a field or parameter
/// - updateFaithTradition() method
/// - tradition_setup_screen (file should not exist)
/// - Filtering by p.faithTradition
/// - Denomination selection UI
///
/// ALLOWED:
/// - References to Biblical traditions (e.g., Jewish traditions in scripture)
/// - This test file itself (exclusion)
/// - INVARIANTS.md and SPEC.md documentation explaining the invariant
/// - Comments explaining why tradition code was removed

void main() {
  group('Christian General Only Invariant', () {
    test('CRITICAL: No faithTradition field in lib/ models', () async {
      final violations = <String>[];
      final libDir = Directory('lib');

      await for (final entity in libDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final content = await entity.readAsString();
          final lines = content.split('\n');

          for (int i = 0; i < lines.length; i++) {
            final line = lines[i];
            // Check for faithTradition field declaration
            if (line.contains('final String faithTradition') ||
                line.contains('String? faithTradition') ||
                line.contains('required this.faithTradition') ||
                line.contains("'faithTradition':") ||
                line.contains('"faithTradition":')) {
              // Allow comments explaining removal
              if (!line.trimLeft().startsWith('//') &&
                  !line.trimLeft().startsWith('*') &&
                  !line.trimLeft().startsWith('///')) {
                violations.add('${entity.path}:${i + 1}: $line');
              }
            }
          }
        }
      }

      if (violations.isNotEmpty) {
        print('🚨 VIOLATION: faithTradition field found in lib/');
        print('The following files contain faithTradition references:');
        for (final v in violations) {
          print('  $v');
        }
        fail(
            'Christian General Only Invariant violated: ${violations.length} occurrences of faithTradition in lib/');
      }
    });

    test('CRITICAL: No tradition filtering in ParableService', () async {
      final parableServiceFile = File('lib/services/parable_service.dart');

      if (!await parableServiceFile.exists()) {
        fail('ParableService file not found');
      }

      final content = await parableServiceFile.readAsString();

      // Check for tradition filtering patterns
      final violations = <String>[];

      if (content.contains('p.faithTradition')) {
        violations.add('Filtering by p.faithTradition');
      }
      if (content.contains('userPrefs.faithTradition')) {
        violations.add('Accessing userPrefs.faithTradition');
      }
      if (content.contains("'tradition':")) {
        violations.add("Logging 'tradition' in analytics");
      }

      if (violations.isNotEmpty) {
        print('🚨 VIOLATION: Tradition filtering found in ParableService');
        for (final v in violations) {
          print('  $v');
        }
        fail(
            'Christian General Only Invariant violated: ParableService contains tradition filtering');
      }
    });

    test('CRITICAL: No tradition selector UI', () async {
      // The tradition_setup_screen.dart file should not exist
      final traditionScreenFile =
          File('lib/features/onboarding/tradition_setup_screen.dart');

      if (await traditionScreenFile.exists()) {
        fail(
            'Christian General Only Invariant violated: tradition_setup_screen.dart still exists');
      }
    });

    test('CRITICAL: No faithTradition in manifest.json', () async {
      final manifestFile = File('assets/stories/manifest.json');

      if (!await manifestFile.exists()) {
        // Manifest might not exist in test environment, skip
        return;
      }

      final content = await manifestFile.readAsString();

      if (content.contains('"faithTradition"')) {
        fail(
            'Christian General Only Invariant violated: manifest.json contains faithTradition field');
      }
    });

    test('CRITICAL: No updateFaithTradition method in providers', () async {
      final appStateFile = File('lib/providers/app_state_notifier.dart');

      if (!await appStateFile.exists()) {
        fail('app_state_notifier.dart not found');
      }

      final content = await appStateFile.readAsString();

      if (content.contains('updateFaithTradition')) {
        fail(
            'Christian General Only Invariant violated: updateFaithTradition method exists');
      }
    });

    test('CRITICAL: No ENABLE_DENOMINATION_SELECTOR flag', () async {
      final featureFlagsFile = File('lib/core/feature_flags.dart');

      if (!await featureFlagsFile.exists()) {
        fail('feature_flags.dart not found');
      }

      final content = await featureFlagsFile.readAsString();

      if (content.contains('kEnableDenominationSelector') ||
          content.contains('ENABLE_DENOMINATION_SELECTOR')) {
        // Allow comments explaining removal
        final lines = content.split('\n');
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          if ((line.contains('kEnableDenominationSelector') ||
                  line.contains('ENABLE_DENOMINATION_SELECTOR')) &&
              !line.trimLeft().startsWith('//') &&
              !line.trimLeft().startsWith('*')) {
            fail(
                'Christian General Only Invariant violated: ENABLE_DENOMINATION_SELECTOR flag exists at line ${i + 1}');
          }
        }
      }
    });

    test('CRITICAL: No kDefaultFaithTradition constant', () async {
      final featureFlagsFile = File('lib/core/feature_flags.dart');

      if (!await featureFlagsFile.exists()) {
        fail('feature_flags.dart not found');
      }

      final content = await featureFlagsFile.readAsString();

      // Check for the constant declaration (not comments)
      final lines = content.split('\n');
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('kDefaultFaithTradition') &&
            !line.trimLeft().startsWith('//') &&
            !line.trimLeft().startsWith('*')) {
          fail(
              'Christian General Only Invariant violated: kDefaultFaithTradition constant exists at line ${i + 1}');
        }
      }
    });

    test('CRITICAL: UserPreferences has no faithTradition field', () async {
      final userPrefsFile = File('lib/models/user_preferences.dart');

      if (!await userPrefsFile.exists()) {
        fail('user_preferences.dart not found');
      }

      final content = await userPrefsFile.readAsString();

      // Check for field declaration
      if (content.contains('final String faithTradition;')) {
        fail(
            'Christian General Only Invariant violated: UserPreferences has faithTradition field');
      }

      // Check for constructor parameter
      if (content.contains('required this.faithTradition')) {
        fail(
            'Christian General Only Invariant violated: UserPreferences requires faithTradition in constructor');
      }
    });

    test('CRITICAL: Parable has no faithTradition field', () async {
      final parableFile = File('lib/models/parable.dart');

      if (!await parableFile.exists()) {
        fail('parable.dart not found');
      }

      final content = await parableFile.readAsString();

      if (content.contains('final String faithTradition;') ||
          content.contains('required this.faithTradition')) {
        fail(
            'Christian General Only Invariant violated: Parable has faithTradition field');
      }
    });

    test('CRITICAL: Favorite has no faithTradition field', () async {
      final favoriteFile = File('lib/models/favorite.dart');

      if (!await favoriteFile.exists()) {
        fail('favorite.dart not found');
      }

      final content = await favoriteFile.readAsString();

      if (content.contains('final String faithTradition;') ||
          content.contains('required this.faithTradition')) {
        fail(
            'Christian General Only Invariant violated: Favorite has faithTradition field');
      }
    });

    test('CRITICAL: HistoryEntry has no faithTradition field', () async {
      final historyFile = File('lib/models/history_entry.dart');

      if (!await historyFile.exists()) {
        fail('history_entry.dart not found');
      }

      final content = await historyFile.readAsString();

      if (content.contains('final String faithTradition;') ||
          content.contains('required this.faithTradition')) {
        fail(
            'Christian General Only Invariant violated: HistoryEntry has faithTradition field');
      }
    });

    test('No denomination selection in Settings', () async {
      final settingsFile = File('lib/features/settings/settings_screen.dart');

      if (!await settingsFile.exists()) {
        // Settings screen might not exist yet
        return;
      }

      final content = await settingsFile.readAsString();

      // Check for tradition/denomination UI
      if (content.contains('TraditionSelector') ||
          content.contains('DenominationSelector') ||
          content.contains('Change Faith Tradition') ||
          content.contains('updateFaithTradition')) {
        fail(
            'Christian General Only Invariant violated: Settings has tradition selection UI');
      }
    });
  });
}
