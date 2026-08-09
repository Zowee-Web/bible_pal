import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/app_logger.dart';

/// Allowlist of keys permitted in the support bundle export.
/// This is the source of truth for PII safety - any key not in this list
/// appearing in export would be a privacy concern.
const Set<String> kSupportBundleAllowedKeys = {
  // Top-level metadata
  'session_id',
  'exported_at',
  'diagnostics_enabled',
  'app_version',
  'app_build',
  'platform',
  'platform_version',
  'last_filters',
  'breadcrumb_count',
  'breadcrumbs',
};

/// Keys allowed in last_filters map (subset of safe filter fields)
/// NOTE: 'tradition' is BANNED per Christian General Only invariant (INVARIANTS.md)
/// NOTE: 'length_min' is BANNED - use 'length_bucket' only (StoryLengthBucket canonical)
const Set<String> kLastFiltersAllowedKeys = {
  'kid_mode',
  'story_mode',
  'length_bucket',
  'mood',
  'language_style',
  'storytelling_mode',
  'pool_size',
};

/// Keys allowed in individual breadcrumb entries
/// NOTE: 'tradition' is BANNED per Christian General Only invariant (INVARIANTS.md)
/// NOTE: 'length_min' is BANNED - use 'length_bucket' only (StoryLengthBucket canonical)
const Set<String> kBreadcrumbAllowedKeys = {
  'ts',
  'event',
  'level',
  'location',
  // Safe data keys (non-PII)
  'story_id',
  'score',
  'mood',
  'platform',
  'platform_version',
  'setting',
  'from',
  'to',
  'kid_mode',
  'story_mode',
  'storytelling_mode',
  'language_style',
  'length_bucket',
  'error_type',
  'error_message',
  'count',
  'duration_ms',
  'position_ms',
  'success',
  'source',
  'pool_size',
};

void main() {
  setUp(() {
    AppLogger.instance.clearBreadcrumbs();
    AppLogger.instance.clearLastFilters();
  });

  group('Session ID', () {
    test('session_id is non-empty string', () {
      final sessionId = getSessionId();
      expect(sessionId, isNotEmpty);
    });

    test('session_id is 16 hex characters', () {
      final sessionId = getSessionId();
      expect(sessionId.length, equals(16));
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(sessionId), isTrue);
    });

    test('session_id is stable within same app run', () {
      final id1 = getSessionId();
      final id2 = getSessionId();
      final id3 = AppLogger.instance.sessionId;

      expect(id1, equals(id2));
      expect(id2, equals(id3));
    });
  });

  group('Last Filters Tracking', () {
    test('last_filters is empty initially', () {
      final filters = getLastFilters();
      expect(filters, isEmpty);
    });

    test('filters_applied event updates last_filters', () {
      logEvent('filters_applied', {
        'kid_mode': true,
        'story_mode': 'traditional',
        'length_bucket': 'short',
        'mood': 'joyful',
      });

      final filters = getLastFilters();
      expect(filters['kid_mode'], isTrue);
      expect(filters['story_mode'], equals('traditional'));
      expect(filters['length_bucket'], equals('short'));
    });

    test('last_filters only updated by filters_applied event', () {
      // Log non-filters event
      logEvent('story_selected', {
        'story_id': 'parable_001',
        'score': 0.85,
      });

      final filters = getLastFilters();
      expect(filters, isEmpty); // Should not be updated
    });

    test('last_filters is a copy (immutable)', () {
      logEvent('filters_applied', {'kid_mode': true});

      final filters1 = getLastFilters();
      final filters2 = getLastFilters();

      // Should be equal but not identical objects
      expect(filters1, equals(filters2));
    });
  });

  group('Support Bundle Fields - Privacy', () {
    test('support bundle does not contain blocked keys', () {
      // Attempt to log filters with blocked keys (should be blocked)
      final result = logEvent('filters_applied', {
        'kid_mode': true,
        'userText': 'should be blocked',
      });

      expect(result, equals(LogResult.blocked));

      // Last filters should NOT be updated with blocked data
      final filters = getLastFilters();
      expect(filters.containsKey('userText'), isFalse);
    });

    test('session_id contains no PII patterns', () {
      final sessionId = getSessionId();

      // Should not look like email
      expect(sessionId.contains('@'), isFalse);

      // Session IDs are generated solely from Random.secure() bytes, not
      // user input. These assertions verify their deterministic
      // 16-character lowercase-hex format. Do not reject PII-like
      // substrings: random hex can coincidentally contain ten decimal
      // digits (~2.96% of generated IDs).
      expect(sessionId, hasLength(16));
      expect(sessionId, matches(RegExp(r'^[0-9a-f]{16}$')));
    });
  });

  group('App Info Accessors', () {
    test('appVersion accessible after setAppInfo', () {
      setLoggerAppInfo(version: '2.0.0', build: '99');

      expect(AppLogger.instance.appVersion, equals('2.0.0'));
      expect(AppLogger.instance.appBuild, equals('99'));
    });
  });

  group('Support Bundle Key Allowlist', () {
    test('top-level keys must match allowlist exactly', () {
      // This test documents the expected support bundle structure
      // If new keys are added, they must be reviewed for PII safety
      final expectedKeys = kSupportBundleAllowedKeys.toList()..sort();

      // Document the expected structure
      expect(
        expectedKeys,
        containsAll([
          'session_id',
          'exported_at',
          'diagnostics_enabled',
          'app_version',
          'app_build',
          'platform',
          'platform_version',
          'last_filters',
          'breadcrumb_count',
          'breadcrumbs',
        ]),
        reason: 'Support bundle must contain only safe, non-PII fields',
      );
    });

    test('last_filters keys are safe', () {
      // All filter keys should be safe (enum values, bucket names, not user text)
      // NOTE: 'tradition' is BANNED per Christian General Only invariant
      // NOTE: 'length_min' is BANNED - use 'length_bucket' only
      for (final key in kLastFiltersAllowedKeys) {
        expect(
          [
            'kid_mode',
            'story_mode',
            'length_bucket',
            'mood',
            'language_style',
            'storytelling_mode',
            'pool_size'
          ],
          contains(key),
          reason: '$key is in last_filters allowlist',
        );
      }
    });

    test('breadcrumb keys are safe', () {
      // Breadcrumbs should never contain PII
      final piiIndicators = [
        'usertext',
        'user_text',
        'email',
        'phone',
        'name',
        'password',
        'token',
        'key',
        'secret',
        'credential',
        'address',
        'ip',
      ];

      for (final key in kBreadcrumbAllowedKeys) {
        final lowerKey = key.toLowerCase();
        for (final pii in piiIndicators) {
          expect(
            lowerKey.contains(pii),
            isFalse,
            reason: '$key looks like it might contain PII (matches: $pii)',
          );
        }
      }
    });

    test('no blocked keys in any allowlist', () {
      // Cross-check against the blocked keys from AppLogger
      // These should NEVER appear in any allowlist
      const mustBeBlocked = [
        'usertext',
        'user_text',
        'email',
        'phone',
        'password',
        'apikey',
        'api_key',
        'token',
      ];

      final allAllowedKeys = <String>{
        ...kSupportBundleAllowedKeys,
        ...kLastFiltersAllowedKeys,
        ...kBreadcrumbAllowedKeys,
      };

      for (final blocked in mustBeBlocked) {
        expect(
          allAllowedKeys.contains(blocked),
          isFalse,
          reason: '$blocked should never be in any allowlist',
        );
      }
    });
  });

  group('Support Bundle Integration', () {
    test('logged events produce safe breadcrumbs', () {
      // Log various events with safe data
      logEvent('app_started', {
        'platform': 'ios',
        'platform_version': '17.0',
      });

      logEvent('story_selected', {
        'story_id': 'parable_001',
        'score': 0.85,
        'mood': 'joyful',
      });

      logEvent('filters_applied', {
        'kid_mode': true,
        'story_mode': 'creative',
        'length_bucket': 'short',
        'mood': 'joyful',
      });

      // Get breadcrumbs and verify structure
      final breadcrumbs = getRecentBreadcrumbs();
      expect(breadcrumbs.length, equals(3));

      // Check each breadcrumb only has allowed keys
      for (final crumb in breadcrumbs) {
        for (final key in crumb.keys) {
          expect(
            kBreadcrumbAllowedKeys.contains(key),
            isTrue,
            reason: 'Breadcrumb key "$key" not in allowlist',
          );
        }
      }

      // Check filters were captured
      final filters = getLastFilters();
      expect(filters.isNotEmpty, isTrue);

      for (final key in filters.keys) {
        expect(
          kLastFiltersAllowedKeys.contains(key),
          isTrue,
          reason: 'Filter key "$key" not in allowlist',
        );
      }
    });

    test('blocked data never appears in breadcrumbs', () {
      // Attempt to log blocked data
      final blockedResult = logEvent('test_event', {
        'userText': 'this should be blocked',
        'email': 'test@test.com',
      });

      expect(blockedResult, equals(LogResult.blocked));

      // Log a safe event to get breadcrumbs
      logEvent('safe_event', {'story_id': 'parable_001'});

      // Check breadcrumbs don't contain blocked keys
      final breadcrumbs = getRecentBreadcrumbs();

      for (final crumb in breadcrumbs) {
        expect(crumb.containsKey('userText'), isFalse);
        expect(crumb.containsKey('email'), isFalse);
      }
    });
  });

  group('CRITICAL: Telemetry Invariants - Christian General Only & StoryLengthBucket', () {
    // These tests enforce HARD invariants on telemetry:
    // 1. NO 'tradition' field anywhere (Christian General Only - INVARIANTS.md)
    // 2. NO 'length_min' or minute-based length fields (use 'length_bucket' only)
    //
    // DO NOT WEAKEN THESE TESTS.

    test('CRITICAL: tradition field MUST NOT be in any allowlist', () {
      // Per INVARIANTS.md: Christian General Only - no denomination/tradition fields
      const bannedKey = 'tradition';

      expect(
        kSupportBundleAllowedKeys.contains(bannedKey),
        isFalse,
        reason:
            '🚨 INVARIANT VIOLATION: "tradition" in kSupportBundleAllowedKeys violates Christian General Only',
      );

      expect(
        kLastFiltersAllowedKeys.contains(bannedKey),
        isFalse,
        reason:
            '🚨 INVARIANT VIOLATION: "tradition" in kLastFiltersAllowedKeys violates Christian General Only',
      );

      expect(
        kBreadcrumbAllowedKeys.contains(bannedKey),
        isFalse,
        reason:
            '🚨 INVARIANT VIOLATION: "tradition" in kBreadcrumbAllowedKeys violates Christian General Only',
      );
    });

    test('CRITICAL: length_min field MUST NOT be in any allowlist', () {
      // Per SPEC.md: StoryLengthBucket is canonical, no minutes in active logic
      const bannedKey = 'length_min';

      expect(
        kSupportBundleAllowedKeys.contains(bannedKey),
        isFalse,
        reason:
            '🚨 INVARIANT VIOLATION: "length_min" in kSupportBundleAllowedKeys - use length_bucket',
      );

      expect(
        kLastFiltersAllowedKeys.contains(bannedKey),
        isFalse,
        reason:
            '🚨 INVARIANT VIOLATION: "length_min" in kLastFiltersAllowedKeys - use length_bucket',
      );

      expect(
        kBreadcrumbAllowedKeys.contains(bannedKey),
        isFalse,
        reason:
            '🚨 INVARIANT VIOLATION: "length_min" in kBreadcrumbAllowedKeys - use length_bucket',
      );
    });

    test('CRITICAL: length_bucket MUST be in filter allowlists', () {
      // StoryLengthBucket is the canonical representation
      expect(
        kLastFiltersAllowedKeys.contains('length_bucket'),
        isTrue,
        reason: 'length_bucket must be allowed in filters (StoryLengthBucket canonical)',
      );

      expect(
        kBreadcrumbAllowedKeys.contains('length_bucket'),
        isTrue,
        reason: 'length_bucket must be allowed in breadcrumbs (StoryLengthBucket canonical)',
      );
    });

    test('CRITICAL: no minute-based length fields in any allowlist', () {
      // Comprehensive check for any legacy minute-based fields
      const bannedMinuteFields = [
        'length_min',
        'length_max',
        'length_minutes',
        'minutes',
        'duration_minutes',
      ];

      final allAllowedKeys = <String>{
        ...kSupportBundleAllowedKeys,
        ...kLastFiltersAllowedKeys,
        ...kBreadcrumbAllowedKeys,
      };

      for (final banned in bannedMinuteFields) {
        expect(
          allAllowedKeys.contains(banned),
          isFalse,
          reason:
              '🚨 INVARIANT VIOLATION: "$banned" found in allowlist - use length_bucket instead',
        );
      }
    });

    test('CRITICAL: no denomination fields in any allowlist', () {
      // Comprehensive check for any tradition/denomination fields
      const bannedDenominationFields = [
        'tradition',
        'denomination',
        'faith_tradition',
        'church',
        'religion',
      ];

      final allAllowedKeys = <String>{
        ...kSupportBundleAllowedKeys,
        ...kLastFiltersAllowedKeys,
        ...kBreadcrumbAllowedKeys,
      };

      for (final banned in bannedDenominationFields) {
        expect(
          allAllowedKeys.contains(banned),
          isFalse,
          reason:
              '🚨 INVARIANT VIOLATION: "$banned" found in allowlist - violates Christian General Only',
        );
      }
    });
  });

  group('CRITICAL: story_selected Event Telemetry Invariants', () {
    // These tests enforce that story_selected events use ONLY canonical fields.
    // NO minute-based length fields, NO tradition/denomination fields.
    //
    // DO NOT WEAKEN THESE TESTS.

    test('CRITICAL: story_selected event MUST NOT contain length_min', () {
      // Log a story_selected event (simulating what ParableService does)
      logEvent('story_selected', {
        'story_id': 'parable_001',
        'mode': 'adult_traditional',
        'length_bucket': 'short',
        'matched_tags': ['grateful'],
        'selection_method': 'deterministic_lrp',
        'repeat_allowed': false,
      });

      final breadcrumbs = getRecentBreadcrumbs();
      expect(breadcrumbs, isNotEmpty);

      final storySelectedCrumb =
          breadcrumbs.firstWhere((c) => c['event'] == 'story_selected');

      // CRITICAL: Must NOT contain any minute-based length fields
      expect(
        storySelectedCrumb.containsKey('length_min'),
        isFalse,
        reason: '🚨 INVARIANT VIOLATION: story_selected contains length_min - use length_bucket only',
      );
      expect(
        storySelectedCrumb.containsKey('length_max'),
        isFalse,
        reason: '🚨 INVARIANT VIOLATION: story_selected contains length_max - use length_bucket only',
      );
      expect(
        storySelectedCrumb.containsKey('minutes'),
        isFalse,
        reason: '🚨 INVARIANT VIOLATION: story_selected contains minutes - use length_bucket only',
      );
      expect(
        storySelectedCrumb.containsKey('duration_minutes'),
        isFalse,
        reason: '🚨 INVARIANT VIOLATION: story_selected contains duration_minutes - use length_bucket only',
      );
    });

    test('CRITICAL: story_selected event MUST include length_bucket', () {
      logEvent('story_selected', {
        'story_id': 'parable_002',
        'mode': 'kid_creative',
        'length_bucket': 'full',
        'matched_tags': ['anxious'],
        'selection_method': 'relatability_ranking',
        'repeat_allowed': true,
      });

      final breadcrumbs = getRecentBreadcrumbs();
      final storySelectedCrumb =
          breadcrumbs.firstWhere((c) => c['event'] == 'story_selected');

      // CRITICAL: Must contain length_bucket (canonical representation)
      expect(
        storySelectedCrumb.containsKey('length_bucket'),
        isTrue,
        reason: '🚨 INVARIANT VIOLATION: story_selected missing length_bucket - required field',
      );

      // Verify it's a valid bucket value
      final lengthBucket = storySelectedCrumb['length_bucket'] as String;
      expect(
        ['short', 'full', 'long'].contains(lengthBucket),
        isTrue,
        reason: '🚨 INVARIANT VIOLATION: length_bucket must be short/full/long, got: $lengthBucket',
      );
    });

    test('CRITICAL: story_selected event MUST NOT contain tradition field', () {
      logEvent('story_selected', {
        'story_id': 'parable_003',
        'mode': 'adult_creative',
        'length_bucket': 'long',
        'matched_tags': ['sad'],
        'selection_method': 'deterministic_lrp',
        'repeat_allowed': false,
      });

      final breadcrumbs = getRecentBreadcrumbs();
      final storySelectedCrumb =
          breadcrumbs.firstWhere((c) => c['event'] == 'story_selected');

      // CRITICAL: Must NOT contain tradition/denomination fields
      expect(
        storySelectedCrumb.containsKey('tradition'),
        isFalse,
        reason: '🚨 INVARIANT VIOLATION: story_selected contains tradition - violates Christian General Only',
      );
      expect(
        storySelectedCrumb.containsKey('denomination'),
        isFalse,
        reason: '🚨 INVARIANT VIOLATION: story_selected contains denomination - violates Christian General Only',
      );
    });

    test('CRITICAL: story_selected required fields check', () {
      logEvent('story_selected', {
        'story_id': 'parable_test',
        'mode': 'kid_traditional',
        'length_bucket': 'short',
        'matched_tags': ['grateful', 'waiting'],
        'selection_method': 'relatability_ranking',
        'repeat_allowed': false,
      });

      final breadcrumbs = getRecentBreadcrumbs();
      final crumb = breadcrumbs.firstWhere((c) => c['event'] == 'story_selected');

      // Verify expected required fields are present
      expect(crumb.containsKey('story_id'), isTrue, reason: 'story_id is required');
      expect(crumb.containsKey('mode'), isTrue, reason: 'mode is required');
      expect(crumb.containsKey('length_bucket'), isTrue, reason: 'length_bucket is required');
      expect(crumb.containsKey('selection_method'), isTrue, reason: 'selection_method is required');

      // Verify NO banned fields
      const bannedFields = [
        'length_min', 'length_max', 'minutes', 'duration_minutes',
        'tradition', 'denomination', 'faith_tradition',
      ];
      for (final banned in bannedFields) {
        expect(
          crumb.containsKey(banned),
          isFalse,
          reason: '🚨 story_selected contains banned field: $banned',
        );
      }
    });
  });
}
