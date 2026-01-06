import 'package:flutter_test/flutter_test.dart';

/// Known error type categories from ERROR_TAXONOMY.md
const Set<String> kValidErrorCategories = {
  'audio',
  'network',
  'storage',
  'story',
  'verse',
  'tts',
  'eligibility',
  'permission',
  'state',
  'validation',
  // Escape hatch for genuinely new categories (must be documented)
  'custom',
};

/// Result of error type validation
enum ErrorTypeValidation {
  valid,
  invalidFormat,
  unknownCategory,
}

/// Validates that an error type follows the taxonomy convention.
/// Returns validation result for stricter enforcement.
ErrorTypeValidation validateErrorType(String errorType) {
  // Must be snake_case
  if (!RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$').hasMatch(errorType)) {
    return ErrorTypeValidation.invalidFormat;
  }

  // Must have at least category_specific format
  if (!errorType.contains('_')) {
    return ErrorTypeValidation.invalidFormat;
  }

  // Category must be known (strict enforcement)
  final category = errorType.split('_').first;
  if (!kValidErrorCategories.contains(category)) {
    return ErrorTypeValidation.unknownCategory;
  }

  return ErrorTypeValidation.valid;
}

/// Legacy helper for simple boolean check
bool isValidErrorType(String errorType) {
  return validateErrorType(errorType) == ErrorTypeValidation.valid;
}

void main() {
  group('Error Taxonomy Naming Convention', () {
    test('valid error types pass validation', () {
      final validTypes = [
        'audio_load_failed',
        'audio_play_failed',
        'network_timeout',
        'network_connection_failed',
        'storage_read_failed',
        'story_load_failed',
        'verse_lookup_failed',
        'tts_generation_failed',
        'eligibility_no_stories',
        'permission_microphone_denied',
        'state_invalid_transition',
        'validation_kid_safe_failed',
      ];

      for (final errorType in validTypes) {
        expect(
          isValidErrorType(errorType),
          isTrue,
          reason: '$errorType should be valid',
        );
      }
    });

    test('invalid error types fail validation', () {
      final invalidTypes = [
        'AudioLoadFailed', // camelCase
        'AUDIO_LOAD_FAILED', // UPPERCASE
        'audio-load-failed', // kebab-case
        'audiofailed', // no underscore
        '123_error', // starts with number
        'audio_', // trailing underscore
        '_audio_error', // leading underscore
      ];

      for (final errorType in invalidTypes) {
        expect(
          isValidErrorType(errorType),
          isFalse,
          reason: '$errorType should be invalid',
        );
      }
    });

    test('unknown categories are flagged', () {
      // These follow snake_case but have unknown categories
      final unknownCategoryTypes = [
        'unknown_error',
        'foo_bar_baz',
        // Note: 'custom_thing_failed' is now valid (custom_ is escape hatch)
      ];

      for (final errorType in unknownCategoryTypes) {
        expect(
          isValidErrorType(errorType),
          isFalse,
          reason: '$errorType has unknown category',
        );
      }
    });
  });

  group('Error Taxonomy Categories', () {
    test('all documented categories are in valid set', () {
      // Categories from ERROR_TAXONOMY.md
      final documentedCategories = [
        'audio',
        'network',
        'storage',
        'story',
        'verse',
        'tts',
        'eligibility',
        'permission',
        'state',
        'validation',
      ];

      for (final category in documentedCategories) {
        expect(
          kValidErrorCategories.contains(category),
          isTrue,
          reason: '$category should be in valid categories',
        );
      }
    });
  });

  group('Error Type Examples from Codebase', () {
    // These are error types actually used in the codebase
    // This test ensures they follow the taxonomy
    test('codebase error types follow taxonomy', () {
      final codebaseErrorTypes = [
        'audio_load_failed',
        'audio_play_failed',
        'network_error', // Note: might want network_request_failed
      ];

      for (final errorType in codebaseErrorTypes) {
        // At minimum, should be snake_case with underscore
        expect(
          RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)+$').hasMatch(errorType),
          isTrue,
          reason: '$errorType should follow snake_case convention',
        );
      }
    });
  });

  group('Strict Error Taxonomy Enforcement', () {
    test('validateErrorType returns specific failure reasons', () {
      // Invalid format cases
      expect(
        validateErrorType('AudioLoadFailed'),
        equals(ErrorTypeValidation.invalidFormat),
        reason: 'camelCase should fail with invalidFormat',
      );

      expect(
        validateErrorType('audio-load-failed'),
        equals(ErrorTypeValidation.invalidFormat),
        reason: 'kebab-case should fail with invalidFormat',
      );

      expect(
        validateErrorType('audiofailed'),
        equals(ErrorTypeValidation.invalidFormat),
        reason: 'missing underscore should fail with invalidFormat',
      );

      // Unknown category cases
      expect(
        validateErrorType('unknown_error'),
        equals(ErrorTypeValidation.unknownCategory),
        reason: 'unknown category should fail with unknownCategory',
      );

      expect(
        validateErrorType('foo_bar_baz'),
        equals(ErrorTypeValidation.unknownCategory),
        reason: 'arbitrary category should fail with unknownCategory',
      );

      // Valid cases
      expect(
        validateErrorType('audio_load_failed'),
        equals(ErrorTypeValidation.valid),
        reason: 'standard error type should be valid',
      );

      expect(
        validateErrorType('custom_new_error'),
        equals(ErrorTypeValidation.valid),
        reason: 'custom_ prefix is allowed escape hatch',
      );
    });

    test('custom_ prefix is escape hatch for new categories', () {
      // custom_ prefix allows genuinely new error types without
      // updating the taxonomy first (but should be documented later)
      expect(isValidErrorType('custom_experiment_failed'), isTrue);
      expect(isValidErrorType('custom_feature_x_error'), isTrue);
    });

    test('all documented categories are testable', () {
      // Every category in ERROR_TAXONOMY.md should produce valid errors
      final categories = [
        'audio',
        'network',
        'storage',
        'story',
        'verse',
        'tts',
        'eligibility',
        'permission',
        'state',
        'validation',
      ];

      for (final category in categories) {
        final testError = '${category}_test_error';
        expect(
          isValidErrorType(testError),
          isTrue,
          reason: '$category category should produce valid error types',
        );
      }
    });

    test('error types from logError calls should be validated', () {
      // This test demonstrates how error types should be validated
      // at the call site (not enforced here, but documented)

      // GOOD: Using validated error types
      const goodErrorTypes = [
        'audio_load_failed',
        'network_timeout',
        'storage_read_failed',
        'story_not_found',
        'validation_kid_safe_failed',
      ];

      for (final errorType in goodErrorTypes) {
        final result = validateErrorType(errorType);
        expect(
          result,
          equals(ErrorTypeValidation.valid),
          reason: '$errorType should be valid for logError',
        );
      }
    });
  });
}
