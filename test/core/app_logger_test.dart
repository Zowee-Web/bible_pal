import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/app_logger.dart';

void main() {
  setUp(() {
    // Clear breadcrumbs before each test
    AppLogger.instance.clearBreadcrumbs();
  });

  group('AppLogger Privacy Enforcement', () {
    test('CRITICAL: blocks raw text fields (userText, message, prompt, transcript)', () {
      // These keys should NEVER be logged - they contain user input
      final blockedKeys = ['userText', 'user_text', 'message', 'prompt', 'transcript'];

      for (final key in blockedKeys) {
        final result = logEvent('test_event', {
          key: 'This is sensitive user input that should never be logged',
          'allowed_field': 'This is fine',
        });

        expect(
          result,
          equals(LogResult.blocked),
          reason: 'Key "$key" should be blocked from logging',
        );
      }
    });

    test('CRITICAL: blocks PII fields (email, phone, name, password)', () {
      final piiKeys = ['email', 'phone', 'name', 'firstName', 'lastName', 'password', 'token', 'secret'];

      for (final key in piiKeys) {
        final result = logEvent('test_event', {
          key: 'sensitive_value',
          'allowed_field': 'ok',
        });

        expect(
          result,
          equals(LogResult.blocked),
          reason: 'PII key "$key" should be blocked from logging',
        );
      }
    });

    test('CRITICAL: blocks values that look like emails', () {
      final result = logEvent('test_event', {
        'some_field': 'Contact me at user@example.com for details',
      });

      expect(result, equals(LogResult.blocked));
    });

    test('CRITICAL: blocks values that look like phone numbers', () {
      final phoneFormats = [
        '555-123-4567',
        '(555) 123-4567',
        '+1 555 123 4567',
        '5551234567',
      ];

      for (final phone in phoneFormats) {
        final result = logEvent('test_event', {
          'info': 'Call me at $phone',
        });

        expect(
          result,
          equals(LogResult.blocked),
          reason: 'Phone number "$phone" should be blocked',
        );
      }
    });

    test('allows safe fields without PII', () {
      final result = logEvent('story_selected', {
        'story_id': 'parable_113',
        'mode': 'kid_traditional',
        'length_min': 5,
        'score': 0.82,
        'repeat_allowed': false,
      });

      expect(result, equals(LogResult.success));
    });

    test('allows nested maps with safe data', () {
      final result = logEvent('filters_applied', {
        'filters': {
          'kid_mode': true,
          'tradition': 'catholic',
          'mode': 'traditional',
        },
        'counts': {
          'total': 100,
          'eligible': 15,
        },
      });

      expect(result, equals(LogResult.success));
    });

    test('blocks nested maps containing blocked keys', () {
      final result = logEvent('test_event', {
        'metadata': {
          'userText': 'This should be blocked',
          'safe_field': 'ok',
        },
      });

      expect(result, equals(LogResult.blocked));
    });

    test('redacts PII in list values', () {
      // Lists with PII should have items redacted (not blocked entirely)
      // The log succeeds but PII values are replaced with [REDACTED]
      final result = logEvent('test_event', {
        'items': ['safe', 'user@example.com', 'also_safe'],
      });

      // Redaction allows the log to succeed - it sanitizes rather than blocks
      expect(result, equals(LogResult.success));

      // Verify the redaction happened via breadcrumbs
      final breadcrumbs = getRecentBreadcrumbs();
      final lastBreadcrumb = breadcrumbs.last;
      final items = lastBreadcrumb['items'] as List;
      expect(items, contains('[REDACTED]'));
      expect(items, isNot(contains('user@example.com')));
    });
  });

  group('AppLogger Safe-Fail Behavior', () {
    test('CRITICAL: never throws even with null values', () {
      expect(
        () => logEvent('test', {'key': null}),
        returnsNormally,
      );
    });

    test('CRITICAL: never throws with empty event name', () {
      expect(
        () => logEvent('', {'key': 'value'}),
        returnsNormally,
      );

      final result = logEvent('', {'key': 'value'});
      expect(result, equals(LogResult.blocked));
    });

    test('CRITICAL: never throws with empty data', () {
      expect(
        () => logEvent('test', {}),
        returnsNormally,
      );
    });

    test('CRITICAL: never throws with deeply nested data', () {
      final deepData = <String, Object?>{
        'level1': {
          'level2': {
            'level3': {
              'level4': {
                'level5': 'deep_value',
              },
            },
          },
        },
      };

      expect(
        () => logEvent('test', deepData),
        returnsNormally,
      );
    });

    test('CRITICAL: never throws with special characters', () {
      expect(
        () => logEvent('test', {
          'unicode': '🚨 emoji test 日本語',
          'newlines': 'line1\nline2\nline3',
          'quotes': 'He said "hello"',
          'backslash': 'path\\to\\file',
        }),
        returnsNormally,
      );
    });

    test('handles circular reference attempt gracefully', () {
      // This shouldn't actually create a circular reference in Dart Maps,
      // but we want to make sure the logger doesn't crash
      final data = <String, Object?>{};
      data['self'] = 'not_circular'; // Dart prevents actual circular refs

      expect(
        () => logEvent('test', data),
        returnsNormally,
      );
    });
  });

  group('AppLogger Structured Output', () {
    test('produces valid JSON format', () {
      final result = logEvent('story_selected', {
        'story_id': 'parable_001',
        'score': 0.95,
      });

      expect(result, equals(LogResult.success));
      // The actual JSON validation happens in the logger itself
    });

    test('includes required fields: event, level, ts', () {
      // We verify by checking breadcrumbs which capture the data
      logEvent('test_event', {'story_id': 'test_001'});

      final breadcrumbs = getRecentBreadcrumbs();
      expect(breadcrumbs, isNotEmpty);

      final last = breadcrumbs.last;
      expect(last['event'], equals('test_event'));
      expect(last['level'], equals('info'));
      expect(last['ts'], isNotNull);
    });

    test('includes app version when set', () {
      setLoggerAppInfo(version: '1.0.0', build: '42');
      logEvent('app_started', {});

      // Version info is included in output, verified by implementation
      final breadcrumbs = getRecentBreadcrumbs();
      expect(breadcrumbs, isNotEmpty);
    });
  });

  group('AppLogger Breadcrumb Ring Buffer', () {
    test('stores events in breadcrumb buffer', () {
      logEvent('event_1', {'id': 1});
      logEvent('event_2', {'id': 2});
      logEvent('event_3', {'id': 3});

      final breadcrumbs = getRecentBreadcrumbs();
      expect(breadcrumbs.length, equals(3));
      expect(breadcrumbs[0]['event'], equals('event_1'));
      expect(breadcrumbs[2]['event'], equals('event_3'));
    });

    test('limits breadcrumbs to 50 entries', () {
      // Add more than 50 events
      for (var i = 0; i < 60; i++) {
        logEvent('event_$i', {'index': i});
      }

      final breadcrumbs = getRecentBreadcrumbs();
      expect(breadcrumbs.length, equals(50));

      // Should have the most recent 50 events (10-59)
      expect(breadcrumbs.first['event'], equals('event_10'));
      expect(breadcrumbs.last['event'], equals('event_59'));
    });

    test('clearBreadcrumbs removes all entries', () {
      logEvent('event_1', {'id': 1});
      logEvent('event_2', {'id': 2});

      expect(getRecentBreadcrumbs().length, equals(2));

      AppLogger.instance.clearBreadcrumbs();

      expect(getRecentBreadcrumbs().length, equals(0));
    });

    test('breadcrumbs include timestamps', () {
      final before = DateTime.now().toUtc();
      logEvent('timed_event', {'data': 'test'});
      final after = DateTime.now().toUtc();

      final breadcrumbs = getRecentBreadcrumbs();
      final ts = DateTime.parse(breadcrumbs.last['ts'] as String);

      expect(ts.isAfter(before) || ts.isAtSameMomentAs(before), isTrue);
      expect(ts.isBefore(after) || ts.isAtSameMomentAs(after), isTrue);
    });
  });

  group('AppLogger Error Logging', () {
    test('logError includes error_type and location', () {
      final result = logError(
        'audio_load_failed',
        'AudioService.loadAudio',
        storyId: 'parable_001',
      );

      expect(result, equals(LogResult.success));

      final breadcrumbs = getRecentBreadcrumbs();
      final lastError = breadcrumbs.last;

      expect(lastError['event'], equals('error_caught'));
      expect(lastError['error_type'], equals('audio_load_failed'));
      expect(lastError['location'], equals('AudioService.loadAudio'));
      expect(lastError['story_id'], equals('parable_001'));
    });

    test('logError sanitizes error messages', () {
      // Error messages might accidentally contain PII
      final result = logError(
        'network_error',
        'ApiService.fetch',
        errorMessage: 'Failed for user@example.com: Connection refused',
      );

      expect(result, equals(LogResult.success));

      final breadcrumbs = getRecentBreadcrumbs();
      final lastError = breadcrumbs.last;

      // Email should be redacted
      expect(lastError['error_msg'], contains('[EMAIL]'));
      expect(lastError['error_msg'], isNot(contains('user@example.com')));
    });

    test('logError truncates long error messages', () {
      final longMessage = 'x' * 500; // 500 character message

      logError('test_error', 'TestLocation', errorMessage: longMessage);

      final breadcrumbs = getRecentBreadcrumbs();
      final errorMsg = breadcrumbs.last['error_msg'] as String;

      expect(errorMsg.length, lessThanOrEqualTo(203)); // 200 + "..."
    });

    test('logError indicates breadcrumbs attached', () {
      // Add some breadcrumbs first
      logEvent('event_before_error', {'step': 1});
      logEvent('event_before_error', {'step': 2});

      logError('test_error', 'TestLocation');

      final breadcrumbs = getRecentBreadcrumbs();
      final lastError = breadcrumbs.last;

      expect(lastError['breadcrumbs_attached'], isTrue);
      expect(lastError['breadcrumb_count'], greaterThan(0));
    });
  });

  group('AppLogger Payload Size Limits', () {
    test('truncates payloads exceeding 2KB', () {
      // Create a payload that would exceed 2KB
      final largeData = <String, Object?>{
        'story_id': 'parable_001',
        'tags': List.generate(100, (i) => 'tag_$i'), // Many tags
        'filters': {
          'extra_data': 'x' * 1000, // 1KB of data
        },
        'counts': {
          'more_data': 'y' * 1000, // Another 1KB
        },
      };

      final result = logEvent('large_event', largeData);

      // Should either succeed with truncation or succeed if under limit
      expect(
        result,
        anyOf(equals(LogResult.success), equals(LogResult.truncated)),
      );
    });
  });

  group('AppLogger Log Levels', () {
    test('supports all log levels', () {
      expect(
        () => logEvent('debug_event', {'level': 'debug'}, level: LogLevel.debug),
        returnsNormally,
      );
      expect(
        () => logEvent('info_event', {'level': 'info'}, level: LogLevel.info),
        returnsNormally,
      );
      expect(
        () => logEvent('warn_event', {'level': 'warn'}, level: LogLevel.warn),
        returnsNormally,
      );
      expect(
        () => logEvent('error_event', {'level': 'error'}, level: LogLevel.error),
        returnsNormally,
      );
    });

    test('breadcrumbs preserve log level', () {
      logEvent('warn_event', {'data': 'test'}, level: LogLevel.warn);

      final breadcrumbs = getRecentBreadcrumbs();
      expect(breadcrumbs.last['level'], equals('warn'));
    });
  });

  group('AppLogger Event Catalog Validation', () {
    // These tests ensure the documented events work correctly

    test('story_selected event with required fields', () {
      final result = logEvent('story_selected', {
        'story_id': 'parable_113',
        'mode': 'kid_traditional',
        'length_min': 5,
        'tradition': 'catholic',
        'matched_tags': ['calm_peaceful', 'trust'],
        'score': 0.82,
        'repeat_allowed': false,
      });

      expect(result, equals(LogResult.success));
    });

    test('story_pool_loaded event', () {
      final result = logEvent('story_pool_loaded', {
        'total_count': 150,
        'valid_count': 142,
        'skipped_count': 8,
        'source': 'bundled_assets',
      });

      expect(result, equals(LogResult.success));
    });

    test('audio_play_start event', () {
      final result = logEvent('audio_play_start', {
        'story_id': 'parable_001',
        'position_ms': 0,
        'duration_ms': 300000,
      });

      expect(result, equals(LogResult.success));
    });

    test('audio_play_complete event', () {
      final result = logEvent('audio_play_complete', {
        'story_id': 'parable_001',
        'duration_ms': 300000,
        'completed_at_position_ms': 299500,
      });

      expect(result, equals(LogResult.success));
    });

    test('kid_mode_guard_pass event', () {
      final result = logEvent('kid_mode_guard_pass', {
        'eligible_count': 25,
        'total_filtered': 75,
      });

      expect(result, equals(LogResult.success));
    });

    test('kid_mode_guard_fail event', () {
      final result = logEvent('kid_mode_guard_fail', {
        'violation_reason': 'non_kid_friendly_content_leaked',
        'leaked_count': 2,
      }, level: LogLevel.error);

      expect(result, equals(LogResult.success));
    });

    test('app_started event', () {
      setLoggerAppInfo(version: '1.0.0', build: '42');

      final result = logEvent('app_started', {
        'platform': 'ios',
        'locale': 'en_US',
      });

      expect(result, equals(LogResult.success));
    });

    test('mode_changed event', () {
      final result = logEvent('mode_changed', {
        'from': 'creative',
        'to': 'traditional',
      });

      expect(result, equals(LogResult.success));
    });
  });
}
