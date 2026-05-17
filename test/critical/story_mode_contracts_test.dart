// CRITICAL STORY MODE CONTRACTS TEST
// Per docs/INVARIANTS.md and docs/archive/CREATIVE_RETIREMENT_2026_05_13.md.
//
// Post-Creative-retirement (2026-05-13) these tests enforce:
// - Traditional stories MUST have bibleSourceRef
// - Default storytellingMode is 'traditional'
// - Legacy 'creative' values in SharedPreferences coerce to 'traditional' on load
// - languageStyle is presentation-only (doesn't affect mode rules)
// - Mode filtering returns only traditional stories
//
// Coerce-on-load and registry-side guarantees that no Creative entries exist
// in active manifests are covered by creative_retirement_test.dart.

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
  group('CRITICAL: Story Mode Contracts (Traditional-only)', () {
    group('Default storytellingMode', () {
      test('CRITICAL: UserPreferences defaults to traditional mode', () {
        final prefs = UserPreferences(bibleTranslation: 'WEB');

        expect(
          prefs.storytellingMode,
          'traditional',
          reason: 'UserPreferences.storytellingMode must default to "traditional".\n'
              'Actual default: ${prefs.storytellingMode}',
        );
      });

      test('CRITICAL: UserPreferences.defaults() returns traditional mode', () {
        final prefs = UserPreferences.defaults();

        expect(prefs.storytellingMode, 'traditional');
      });

      test(
          'CRITICAL: UserPreferences.fromJson defaults missing mode to traditional',
          () {
        final json = {'bibleTranslation': 'WEB'};
        final prefs = UserPreferences.fromJson(json);

        expect(prefs.storytellingMode, 'traditional');
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

        // Traditional story WITHOUT bibleSourceRef - invalid
        final invalidTraditional = Parable(
          storyId: 'trad_002',
          title: 'Some Story',
          mood: 'joyful',
          length: 5,
          storytellingMode: 'traditional',
          kidFriendly: false,
        );

        expect(invalidTraditional.hasBibleSourceRef, false);
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

        expect(result.isValid, false);
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

      test('CRITICAL: validateMetadataOnly rejects non-traditional modes', () {
        // Post-Creative-retirement: only 'traditional' is a valid mode value.
        final result = StoryModeValidator.validateMetadataOnly(
          storytellingMode: 'creative',
          bibleSourceRef: null,
          languageStyle: 'WEB',
        );

        expect(result.isValid, false);
        expect(
          result.violations.any((v) => v.contains('storytellingMode')),
          true,
        );
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
      });

      test('CRITICAL: Traditional+KJV still requires bibleSourceRef', () {
        final result = StoryModeValidator.validateMetadataOnly(
          storytellingMode: 'traditional',
          bibleSourceRef: 'Genesis 1:1',
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
          'storytellingMode': 'traditional',
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
          storytellingMode: 'traditional',
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
          'storytellingMode': 'traditional',
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

        final copied = original.copyWith(bibleTranslation: 'KJV');

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

    test('CRITICAL: getEligibleParables returns only traditional stories',
        () async {
      final prefs = UserPreferences(
        bibleTranslation: 'WEB',
        storytellingMode: 'traditional',
        kidFriendlyOnly: true,
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
          reason: 'Traditional mode request returned non-traditional story.\n'
              'Story: ${p.storyId}',
        );
      }
    });
  });
}
