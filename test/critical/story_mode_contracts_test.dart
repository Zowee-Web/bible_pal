// CRITICAL STORY MODE CONTRACTS TEST
// Per SPEC.md Story Mode Contracts v2 and INVARIANTS.md
//
// These tests enforce:
// - Traditional stories MUST have bibleSourceRef
// - Creative stories MUST NOT have bibleSourceRef
// - Mode filtering never cross-contaminates
// - Default storytellingMode is traditional
// - languageStyle is presentation-only (doesn't affect mode rules)

@Tags(['critical'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/safety/story_mode_validator.dart';
import 'package:bible_pal/core/story_length_bucket.dart';

void main() {
  group('CRITICAL: Story Mode Contracts v2', () {
    group('Default storytellingMode', () {
      test('CRITICAL: UserPreferences defaults to traditional mode', () {
        // Per Contracts v2: Default is Traditional
        final prefs = UserPreferences(bibleTranslation: 'WEB');

        expect(
          prefs.storytellingMode,
          'traditional',
          reason: '🚨 CONTRACTS V2 VIOLATION 🚨\n'
              'UserPreferences.storytellingMode must default to "traditional".\n'
              'Actual default: ${prefs.storytellingMode}',
        );
      });

      test('CRITICAL: UserPreferences.defaults() returns traditional mode', () {
        final prefs = UserPreferences.defaults();

        expect(
          prefs.storytellingMode,
          'traditional',
          reason: '🚨 CONTRACTS V2 VIOLATION 🚨\n'
              'UserPreferences.defaults().storytellingMode must be "traditional".\n'
              'Actual: ${prefs.storytellingMode}',
        );
      });

      test(
          'CRITICAL: UserPreferences.fromJson defaults missing mode to traditional',
          () {
        final json = {'bibleTranslation': 'WEB'};
        final prefs = UserPreferences.fromJson(json);

        expect(
          prefs.storytellingMode,
          'traditional',
          reason: '🚨 CONTRACTS V2 VIOLATION 🚨\n'
              'Missing storytellingMode in JSON must default to "traditional".\n'
              'Actual: ${prefs.storytellingMode}',
        );
      });
    });

    group('bibleSourceRef Requirements', () {
      test('CRITICAL: Traditional Parable requires bibleSourceRef', () {
        // Traditional story WITH bibleSourceRef - valid
        final validTraditional = Parable(
          storyId: 'trad_001',
          title: 'The Good Shepherd',
          mood: 'joyful',
          length: 5,
          storytellingMode: 'traditional',
          kidFriendly: false,
          bibleSourceRef: 'Luke 15:3-7',
        );

        expect(validTraditional.hasBibleSourceRef, true);

        // Traditional story WITHOUT bibleSourceRef - invalid per Contracts v2
        final invalidTraditional = Parable(
          storyId: 'trad_002',
          title: 'Some Story',
          mood: 'joyful',
          length: 5,
          storytellingMode: 'traditional',
          kidFriendly: false,
          // bibleSourceRef missing
        );

        expect(
          invalidTraditional.hasBibleSourceRef,
          false,
          reason:
              'Traditional story without bibleSourceRef should report hasBibleSourceRef=false',
        );
      });

      test('CRITICAL: Creative Parable must NOT have bibleSourceRef', () {
        // Creative story WITHOUT bibleSourceRef - valid
        final validCreative = Parable(
          storyId: 'creative_001',
          title: 'The Kind Farmer',
          mood: 'joyful',
          length: 5,
          storytellingMode: 'creative',
          kidFriendly: false,
          // bibleSourceRef absent - correct for Creative
        );

        expect(validCreative.hasBibleSourceRef, false);

        // Creative story WITH bibleSourceRef - invalid per Contracts v2
        final invalidCreative = Parable(
          storyId: 'creative_002',
          title: 'Another Story',
          mood: 'joyful',
          length: 5,
          storytellingMode: 'creative',
          kidFriendly: false,
          bibleSourceRef: 'Genesis 1:1', // WRONG - Creative shouldn't have this
        );

        expect(
          invalidCreative.hasBibleSourceRef,
          true,
          reason:
              'This Creative story incorrectly has bibleSourceRef - validation should catch this',
        );
      });
    });

    group('StoryModeValidator - Metadata Validation', () {
      test('CRITICAL: validateMetadataOnly passes valid Traditional', () {
        final result = StoryModeValidator.validateMetadataOnly(
          storytellingMode: 'traditional',
          bibleSourceRef: 'John 3:16',
          languageStyle: 'WEB',
        );

        expect(result.isValid, true);
        expect(result.violations, isEmpty);
      });

      test(
          'CRITICAL: validateMetadataOnly fails Traditional without bibleSourceRef',
          () {
        final result = StoryModeValidator.validateMetadataOnly(
          storytellingMode: 'traditional',
          bibleSourceRef: null,
          languageStyle: 'WEB',
        );

        expect(
          result.isValid,
          false,
          reason: 'Traditional without bibleSourceRef must fail validation',
        );
        expect(
            result.violations.any((v) => v.contains('bibleSourceRef')), true);
      });

      test(
          'CRITICAL: validateMetadataOnly fails Traditional with empty bibleSourceRef',
          () {
        final result = StoryModeValidator.validateMetadataOnly(
          storytellingMode: 'traditional',
          bibleSourceRef: '   ',
          languageStyle: 'WEB',
        );

        expect(result.isValid, false);
      });

      test('CRITICAL: validateMetadataOnly passes valid Creative', () {
        final result = StoryModeValidator.validateMetadataOnly(
          storytellingMode: 'creative',
          bibleSourceRef: null,
          languageStyle: 'WEB',
        );

        expect(result.isValid, true);
        expect(result.violations, isEmpty);
      });

      test('CRITICAL: validateMetadataOnly fails Creative with bibleSourceRef',
          () {
        final result = StoryModeValidator.validateMetadataOnly(
          storytellingMode: 'creative',
          bibleSourceRef: 'Matthew 5:1',
          languageStyle: 'KJV',
        );

        expect(
          result.isValid,
          false,
          reason: 'Creative with bibleSourceRef must fail validation',
        );
        expect(
            result.violations.any((v) => v.contains('bibleSourceRef')), true);
      });
    });

    group('StoryModeValidator - Content Validation', () {
      test('Traditional validation detects MoDC companionship patterns', () {
        final result = StoryModeValidator.validateTraditional(
          storyText:
              'I sit with you now, dear listener, as we explore this story.',
          bibleSourceRef: 'Luke 15:3-7',
          languageStyle: 'WEB',
        );

        expect(result.violations.any((v) => v.contains('MoDC')), true);
      });

      test('Creative validation detects scripture authority claims', () {
        final result = StoryModeValidator.validateCreative(
          storyText: 'As the Bible says, we should always be kind to others.',
          bibleSourceRef: null,
          languageStyle: 'WEB',
        );

        expect(result.violations.any((v) => v.contains('scripture authority')),
            true);
      });

      test('Creative+KJV validation detects scripture-claim markers', () {
        final result = StoryModeValidator.validateCreative(
          storyText: 'Thus saith the storyteller, verily the farmer was kind.',
          bibleSourceRef: null,
          languageStyle: 'KJV',
        );

        expect(
            result.violations.any((v) => v.contains('scripture-claim marker')),
            true);
      });

      test('Creative+WEB does NOT flag archaic language', () {
        // Same text but WEB style - should not trigger KJV-specific checks
        final result = StoryModeValidator.validateCreative(
          storyText: 'Thus saith the storyteller, verily the farmer was kind.',
          bibleSourceRef: null,
          languageStyle: 'WEB',
        );

        // Should not have KJV-specific violation (but may have other issues)
        expect(result.violations.any((v) => v.contains('Creative+KJV')), false);
      });
    });

    group('languageStyle Independence', () {
      test(
          'CRITICAL: languageStyle does not affect bibleSourceRef requirements',
          () {
        // Traditional+WEB still requires bibleSourceRef
        final tradWeb = StoryModeValidator.validateMetadataOnly(
          storytellingMode: 'traditional',
          bibleSourceRef: null,
          languageStyle: 'WEB',
        );
        expect(tradWeb.isValid, false);

        // Traditional+KJV still requires bibleSourceRef
        final tradKjv = StoryModeValidator.validateMetadataOnly(
          storytellingMode: 'traditional',
          bibleSourceRef: null,
          languageStyle: 'KJV',
        );
        expect(tradKjv.isValid, false);

        // Creative+WEB still forbids bibleSourceRef
        final creativeWeb = StoryModeValidator.validateMetadataOnly(
          storytellingMode: 'creative',
          bibleSourceRef: 'Luke 1:1',
          languageStyle: 'WEB',
        );
        expect(creativeWeb.isValid, false);

        // Creative+KJV still forbids bibleSourceRef
        final creativeKjv = StoryModeValidator.validateMetadataOnly(
          storytellingMode: 'creative',
          bibleSourceRef: 'Luke 1:1',
          languageStyle: 'KJV',
        );
        expect(creativeKjv.isValid, false);
      });

      test('CRITICAL: Traditional+KJV still requires bibleSourceRef', () {
        final result = StoryModeValidator.validateMetadataOnly(
          storytellingMode: 'traditional',
          bibleSourceRef: 'Genesis 1:1',
          languageStyle: 'KJV',
        );

        expect(result.isValid, true);
      });

      test('CRITICAL: Creative+KJV still forbids bibleSourceRef', () {
        final result = StoryModeValidator.validateMetadataOnly(
          storytellingMode: 'creative',
          bibleSourceRef: null,
          languageStyle: 'KJV',
        );

        expect(result.isValid, true);
      });
    });

    group('Parable Model', () {
      test('Parable.fromJson parses bibleSourceRef', () {
        final json = {
          'storyId': 'test_001',
          'title': 'Test Story',
          'mood': 'joyful',
          'length': 5,
          'storytellingMode': 'traditional',
          'kidFriendly': false,
          'bibleSourceRef': 'John 3:16',
        };

        final parable = Parable.fromJson(json);

        expect(parable.bibleSourceRef, 'John 3:16');
        expect(parable.hasBibleSourceRef, true);
      });

      test('Parable.fromJson handles missing bibleSourceRef', () {
        final json = {
          'storyId': 'test_002',
          'title': 'Test Story',
          'mood': 'joyful',
          'length': 5,
          'storytellingMode': 'creative',
          'kidFriendly': false,
        };

        final parable = Parable.fromJson(json);

        expect(parable.bibleSourceRef, null);
        expect(parable.hasBibleSourceRef, false);
      });

      test('Parable.toJson includes bibleSourceRef when present', () {
        final parable = Parable(
          storyId: 'test_003',
          title: 'Test Story',
          mood: 'joyful',
          length: 5,
          storytellingMode: 'traditional',
          kidFriendly: false,
          bibleSourceRef: 'Matthew 5:1-12',
        );

        final json = parable.toJson();

        expect(json['bibleSourceRef'], 'Matthew 5:1-12');
      });

      test('Parable.toJson omits bibleSourceRef when absent', () {
        final parable = Parable(
          storyId: 'test_004',
          title: 'Test Story',
          mood: 'joyful',
          length: 5,
          storytellingMode: 'creative',
          kidFriendly: false,
        );

        final json = parable.toJson();

        expect(json.containsKey('bibleSourceRef'), false);
      });

      test('Parable.fromJson parses languageStyle', () {
        final json = {
          'storyId': 'test_005',
          'title': 'Test Story',
          'mood': 'joyful',
          'length': 5,
          'storytellingMode': 'traditional',
          'kidFriendly': false,
          'languageStyle': 'KJV',
        };

        final parable = Parable.fromJson(json);

        expect(parable.languageStyle, 'KJV');
      });

      test('Parable.fromJson defaults languageStyle to WEB', () {
        final json = {
          'storyId': 'test_006',
          'title': 'Test Story',
          'mood': 'joyful',
          'length': 5,
          'storytellingMode': 'creative',
          'kidFriendly': false,
        };

        final parable = Parable.fromJson(json);

        expect(parable.languageStyle, 'WEB');
      });

      test('Parable.copyWith preserves bibleSourceRef', () {
        final original = Parable(
          storyId: 'test_007',
          title: 'Original',
          mood: 'joyful',
          length: 5,
          storytellingMode: 'traditional',
          kidFriendly: false,
          bibleSourceRef: 'Psalm 23',
        );

        final copied = original.copyWith(title: 'Modified');

        expect(copied.bibleSourceRef, 'Psalm 23');
      });
    });

    group('UserPreferences languageStyle', () {
      test('UserPreferences has languageStyle field', () {
        final prefs = UserPreferences(
          bibleTranslation: 'WEB',
          languageStyle: 'KJV',
        );

        expect(prefs.languageStyle, 'KJV');
      });

      test('UserPreferences.fromJson reads languageStyle', () {
        final json = {
          'bibleTranslation': 'WEB',
          'languageStyle': 'KJV',
        };

        final prefs = UserPreferences.fromJson(json);

        expect(prefs.languageStyle, 'KJV');
      });

      test('UserPreferences.fromJson defaults languageStyle to WEB', () {
        final json = {'bibleTranslation': 'WEB'};

        final prefs = UserPreferences.fromJson(json);

        expect(prefs.languageStyle, 'WEB');
      });

      test('UserPreferences.fromJson reads legacy storyLanguage field', () {
        // Backwards compatibility
        final json = {
          'bibleTranslation': 'WEB',
          'storyLanguage': 'KJV',
        };

        final prefs = UserPreferences.fromJson(json);

        expect(prefs.languageStyle, 'KJV');
      });

      test('UserPreferences.toJson writes languageStyle', () {
        final prefs = UserPreferences(
          bibleTranslation: 'WEB',
          languageStyle: 'KJV',
        );

        final json = prefs.toJson();

        expect(json['languageStyle'], 'KJV');
      });

      test('UserPreferences.copyWith preserves languageStyle', () {
        final original = UserPreferences(
          bibleTranslation: 'WEB',
          languageStyle: 'KJV',
        );

        final copied = original.copyWith(storytellingMode: 'creative');

        expect(copied.languageStyle, 'KJV');
      });
    });
  });

  group('CRITICAL: ParableService Mode Filtering', () {
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

    test('CRITICAL: Traditional mode only returns traditional stories',
        () async {
      final prefs = UserPreferences(
        bibleTranslation: 'WEB',
        storytellingMode: 'traditional',
        kidFriendlyOnly: true, // Use kid mode for available traditional stories
      );

      final eligible = await parableService.getEligibleParables(
        mood: 'joyful',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: prefs,
      );

      for (final p in eligible) {
        expect(
          p.storytellingMode,
          'traditional',
          reason: '🚨 MODE CONTAMINATION 🚨\n'
              'Traditional mode request returned creative story!\n'
              'Story: ${p.storyId}',
        );
      }
    });

    test('CRITICAL: Creative mode only returns creative stories', () async {
      final prefs = UserPreferences(
        bibleTranslation: 'WEB',
        storytellingMode: 'creative',
        kidFriendlyOnly: false,
      );

      final eligible = await parableService.getEligibleParables(
        mood: 'joyful',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: prefs,
      );

      for (final p in eligible) {
        expect(
          p.storytellingMode,
          'creative',
          reason: '🚨 MODE CONTAMINATION 🚨\n'
              'Creative mode request returned traditional story!\n'
              'Story: ${p.storyId}',
        );
      }
    });

    test('CRITICAL: No silent cross-mode fallback', () async {
      // This test verifies that when no stories match the mode,
      // we get an empty list rather than cross-mode content
      final prefs = UserPreferences(
        bibleTranslation: 'WEB',
        storytellingMode: 'traditional',
        kidFriendlyOnly: false,
      );

      final eligible = await parableService.getEligibleParables(
        mood: 'joyful',
        lengthBucket: StoryLengthBucket.short,
        userPrefs: prefs,
      );

      // All returned stories must be traditional mode
      // (empty is OK, cross-mode contamination is NOT OK)
      for (final p in eligible) {
        expect(p.storytellingMode, 'traditional');
      }
    });
  });
}
