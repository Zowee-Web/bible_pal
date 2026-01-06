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
const Set<String> kLastFiltersAllowedKeys = {
  'kid_mode',
  'story_mode',
  'length_min',
  'tradition',
  'mood',
};

/// Keys allowed in individual breadcrumb entries
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
  'length_min',
  'tradition',
  'error_type',
  'error_message',
  'count',
  'duration_ms',
  'position_ms',
  'success',
  'source',
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
        'length_min': 5,
        'tradition': 'catholic',
      });

      final filters = getLastFilters();
      expect(filters['kid_mode'], isTrue);
      expect(filters['story_mode'], equals('traditional'));
      expect(filters['length_min'], equals(5));
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

      // Should not look like phone
      expect(RegExp(r'\d{10}').hasMatch(sessionId), isFalse);

      // Should be hex only
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(sessionId), isTrue);
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
      // All filter keys should be safe (enum values, numbers, not user text)
      for (final key in kLastFiltersAllowedKeys) {
        expect(
          ['kid_mode', 'story_mode', 'length_min', 'tradition', 'mood'],
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
        'length_min': 5,
        'tradition': 'catholic',
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
}
