@Tags(['requires_diagnostics_define'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/crash_log_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Use system temp directory for tests (avoids platform channel issues)
    CrashLogStore.instance.testDirectory = Directory.systemTemp;
  });

  tearDown(() async {
    // Cleanup test crash logs
    await clearAllCrashLogs();
    CrashLogStore.instance.reset();
  });

  group('CrashLogStore Basic Operations', () {
    test('writes crash log to disk', () async {
      final error = StateError('Test error');
      final stackTrace = StackTrace.current;

      final success = await writeCrashLog(
        error: error,
        stackTrace: stackTrace,
        breadcrumbs: [
          {'event': 'test_event', 'level': 'info'},
        ],
        appVersion: '1.0.0',
        appBuild: '1',
      );

      expect(success, isTrue);

      final logs = await loadCrashLogs();
      expect(logs, hasLength(1));
      expect(logs.first.errorType, contains('StateError'));
    });

    test('keeps max 10 crash logs', () async {
      // Write 15 crash logs
      for (var i = 0; i < 15; i++) {
        await writeCrashLog(
          error: Exception('Test $i'),
          stackTrace: StackTrace.current,
        );
        // Small delay to ensure different timestamps
        await Future.delayed(const Duration(milliseconds: 10));
      }

      final logs = await loadCrashLogs();
      expect(logs.length, lessThanOrEqualTo(kMaxCrashLogs));
    });

    test('sorts logs newest first', () async {
      await writeCrashLog(
        error: Exception('First'),
        stackTrace: StackTrace.current,
      );
      await Future.delayed(const Duration(milliseconds: 50));

      await writeCrashLog(
        error: Exception('Second'),
        stackTrace: StackTrace.current,
      );
      await Future.delayed(const Duration(milliseconds: 50));

      await writeCrashLog(
        error: Exception('Third'),
        stackTrace: StackTrace.current,
      );

      final logs = await loadCrashLogs();
      expect(logs.length, 3);
      expect(logs.first.errorMessage, contains('Third'));
      expect(logs.last.errorMessage, contains('First'));
    });

    test('includes app version in crash log', () async {
      await writeCrashLog(
        error: Exception('Test'),
        stackTrace: StackTrace.current,
        appVersion: '1.2.3',
        appBuild: '42',
      );

      final logs = await loadCrashLogs();
      expect(logs.first.appVersion, equals('1.2.3'));
      expect(logs.first.appBuild, equals('42'));
    });

    test('clears all crash logs', () async {
      // Write some logs with small delays to ensure unique timestamps
      for (var i = 0; i < 5; i++) {
        await writeCrashLog(
          error: Exception('Test $i'),
          stackTrace: StackTrace.current,
        );
        await Future.delayed(const Duration(milliseconds: 2));
      }

      expect(await loadCrashLogs(), hasLength(5));

      await clearAllCrashLogs();

      expect(await loadCrashLogs(), isEmpty);
    });

    test('handles corrupted log files gracefully', () async {
      // Write a good log
      await writeCrashLog(
        error: Exception('Good'),
        stackTrace: StackTrace.current,
      );

      // Get crash log directory and write corrupted file
      final appDir = Directory.systemTemp;
      final crashDir = Directory('${appDir.path}/crash_logs');
      await crashDir.create(recursive: true);
      final corruptedFile = File('${crashDir.path}/crash_corrupted.json');
      await corruptedFile.writeAsString('invalid json {[}');

      // Should load only the valid log
      final logs = await loadCrashLogs();
      expect(logs, hasLength(1));
    });

    test('safe-fail: never throws on write errors', () async {
      // This should not throw even with unusual data
      expect(
        () async => await writeCrashLog(
          error: Object(),
          stackTrace: StackTrace.current,
        ),
        returnsNormally,
      );
    });

    test('getCrashLogCount returns correct count', () async {
      expect(await getCrashLogCount(), 0);

      await writeCrashLog(
        error: Exception('Test 1'),
        stackTrace: StackTrace.current,
      );
      await Future.delayed(const Duration(milliseconds: 2));
      await writeCrashLog(
        error: Exception('Test 2'),
        stackTrace: StackTrace.current,
      );

      expect(await getCrashLogCount(), 2);
    });
  });

  group('Privacy Firewall: Breadcrumb Sanitization', () {
    test('CRITICAL: only whitelisted keys are persisted', () async {
      final breadcrumbs = [
        {
          // Allowed keys
          'event': 'story_load_success',
          'story_id': 'parable_123',
          'length_bucket': 'short',
          'kid_friendly': true,
          'duration_ms': 1234,

          // Disallowed keys (should be dropped)
          'user_text': 'I am feeling anxious',
          'verse_content': 'For God so loved the world',
          'email': 'user@example.com',
          'arbitrary_key': 'should be dropped',
        },
      ];

      await writeCrashLog(
        error: Exception('Test'),
        stackTrace: StackTrace.current,
        breadcrumbs: breadcrumbs,
      );

      final logs = await loadCrashLogs();
      final crumb = logs.first.breadcrumbs.first;

      // Should have allowed fields
      expect(crumb['event'], equals('story_load_success'));
      expect(crumb['story_id'], equals('parable_123'));
      expect(crumb['kid_friendly'], isTrue);

      // Should NOT have disallowed fields
      expect(crumb.keys, isNot(contains('user_text')));
      expect(crumb.keys, isNot(contains('verse_content')));
      expect(crumb.keys, isNot(contains('email')));
      expect(crumb.keys, isNot(contains('arbitrary_key')));
    });

    test('CRITICAL: caps string values in breadcrumbs', () async {
      final longString = 'A' * 200; // 200 chars

      final breadcrumbs = [
        {
          'event': longString,
        },
      ];

      await writeCrashLog(
        error: Exception('Test'),
        stackTrace: StackTrace.current,
        breadcrumbs: breadcrumbs,
      );

      final logs = await loadCrashLogs();
      final crumb = logs.first.breadcrumbs.first;

      // Should be capped at 100 chars + '...'
      expect(crumb['event'].toString().length, lessThanOrEqualTo(103));
      expect(crumb['event'].toString(), endsWith('...'));
    });

    test('CRITICAL: drops complex types in breadcrumbs', () async {
      final breadcrumbs = [
        {
          'event': 'test',
          'nested_map': {'foo': 'bar'}, // Should be dropped
          'nested_list': [1, 2, 3], // Should be dropped
          'duration_ms': 123, // Should be kept (number)
          'enabled': true, // Should be kept (boolean)
        },
      ];

      await writeCrashLog(
        error: Exception('Test'),
        stackTrace: StackTrace.current,
        breadcrumbs: breadcrumbs,
      );

      final logs = await loadCrashLogs();
      final crumb = logs.first.breadcrumbs.first;

      // Primitives should be kept
      expect(crumb['event'], equals('test'));
      expect(crumb['duration_ms'], equals(123));
      expect(crumb['enabled'], isTrue);

      // Complex types should be dropped
      expect(crumb.keys, isNot(contains('nested_map')));
      expect(crumb.keys, isNot(contains('nested_list')));
    });

    test('allows null values in breadcrumbs', () async {
      final breadcrumbs = [
        {
          'event': 'test',
          'story_id': null,
        },
      ];

      await writeCrashLog(
        error: Exception('Test'),
        stackTrace: StackTrace.current,
        breadcrumbs: breadcrumbs,
      );

      final logs = await loadCrashLogs();
      final crumb = logs.first.breadcrumbs.first;

      expect(crumb['event'], equals('test'));
      expect(crumb['story_id'], isNull);
    });
  });

  group('Privacy: Error Message Sanitization', () {
    test('CRITICAL: sanitizes file:/// paths', () async {
      final error = Exception('Error loading file:///Users/john/Documents/bible_pal/file.txt');

      await writeCrashLog(
        error: error,
        stackTrace: StackTrace.current,
      );

      final logs = await loadCrashLogs();
      expect(logs.first.errorMessage, contains('[PATH]'));
      expect(logs.first.errorMessage, isNot(contains('file:///Users/john')));
    });

    test('CRITICAL: sanitizes /Users/ paths', () async {
      final error = Exception('Failed at /Users/john/secret/data.txt');

      await writeCrashLog(
        error: error,
        stackTrace: StackTrace.current,
      );

      final logs = await loadCrashLogs();
      expect(logs.first.errorMessage, contains('[PATH]'));
      expect(logs.first.errorMessage, isNot(contains('/Users/john')));
    });

    test('CRITICAL: sanitizes /Volumes/ paths', () async {
      final error = Exception('Error reading /Volumes/T9-AI/bible_pal/file.txt');

      await writeCrashLog(
        error: error,
        stackTrace: StackTrace.current,
      );

      final logs = await loadCrashLogs();
      expect(logs.first.errorMessage, contains('[PATH]'));
      expect(logs.first.errorMessage, isNot(contains('/Volumes/T9-AI')));
    });

    test('CRITICAL: sanitizes Windows paths', () async {
      final error = Exception('Failed at C:\\Users\\John\\Documents\\file.txt');

      await writeCrashLog(
        error: error,
        stackTrace: StackTrace.current,
      );

      final logs = await loadCrashLogs();
      expect(logs.first.errorMessage, contains('[PATH]'));
      expect(logs.first.errorMessage, isNot(contains('C:\\Users')));
    });

    test('CRITICAL: does NOT redact simple paths like "/foo"', () async {
      final error = Exception('Error code /404 not found');

      await writeCrashLog(
        error: error,
        stackTrace: StackTrace.current,
      );

      final logs = await loadCrashLogs();
      // Should keep the error code intact
      expect(logs.first.errorMessage, contains('/404'));
    });

    test('removes email addresses', () async {
      final error = Exception('Error for user@example.com');

      await writeCrashLog(
        error: error,
        stackTrace: StackTrace.current,
      );

      final logs = await loadCrashLogs();
      expect(logs.first.errorMessage, contains('[EMAIL]'));
      expect(logs.first.errorMessage, isNot(contains('user@example.com')));
    });

    test('removes phone numbers', () async {
      final error = Exception('Contact 555-123-4567 for help');

      await writeCrashLog(
        error: error,
        stackTrace: StackTrace.current,
      );

      final logs = await loadCrashLogs();
      expect(logs.first.errorMessage, contains('[PHONE]'));
      expect(logs.first.errorMessage, isNot(contains('555-123-4567')));
    });

    test('truncates long error messages', () async {
      final error = Exception('A' * 1000);

      await writeCrashLog(
        error: error,
        stackTrace: StackTrace.current,
      );

      final logs = await loadCrashLogs();
      expect(logs.first.errorMessage!.length, lessThanOrEqualTo(515)); // 500 + "... [truncated]"
    });
  });

  group('Privacy: Stack Trace Sanitization', () {
    test('CRITICAL: preserves package: URIs', () async {
      const stackString = '''
#0      main (package:bible_pal/main.dart:42:5)
#1      _startIsolate (dart:isolate-patch/isolate_patch.dart:301:32)
''';

      await writeCrashLog(
        error: Exception('Test'),
        stackTrace: StackTrace.fromString(stackString),
      );

      final logs = await loadCrashLogs();
      expect(logs.first.stackTrace, contains('package:bible_pal/main.dart'));
    });

    test('CRITICAL: preserves dart: URIs', () async {
      const stackString = '''
#0      List.map (dart:core-patch/growable_array.dart:177:28)
#1      main (package:bible_pal/main.dart:42:5)
''';

      await writeCrashLog(
        error: Exception('Test'),
        stackTrace: StackTrace.fromString(stackString),
      );

      final logs = await loadCrashLogs();
      expect(logs.first.stackTrace, contains('dart:core-patch'));
    });

    test('CRITICAL: redacts file:/// absolute paths', () async {
      const stackString = '''
#0      main (file:///Users/john/flutter/bible_pal/lib/main.dart:42:5)
''';

      await writeCrashLog(
        error: Exception('Test'),
        stackTrace: StackTrace.fromString(stackString),
      );

      final logs = await loadCrashLogs();
      expect(logs.first.stackTrace, contains('file://[PATH]'));
      expect(logs.first.stackTrace, isNot(contains('/Users/john')));
    });

    test('CRITICAL: redacts Unix absolute paths', () async {
      const stackString = '''
#0      main (/Users/john/Documents/project/lib/main.dart:42:5)
#1      helper (/Volumes/T9-AI/bible_pal/lib/helper.dart:10:3)
''';

      await writeCrashLog(
        error: Exception('Test'),
        stackTrace: StackTrace.fromString(stackString),
      );

      final logs = await loadCrashLogs();
      expect(logs.first.stackTrace, contains('[PATH]'));
      expect(logs.first.stackTrace, isNot(contains('/Users/john')));
      expect(logs.first.stackTrace, isNot(contains('/Volumes/T9-AI')));
    });

    test('truncates long stack traces', () async {
      final longStack = List.generate(
        200,
        (i) => '#$i      main (package:bible_pal/main.dart:$i:5)',
      ).join('\n');

      await writeCrashLog(
        error: Exception('Test'),
        stackTrace: StackTrace.fromString(longStack),
      );

      final logs = await loadCrashLogs();
      final stackLines = logs.first.stackTrace!.split('\n');
      expect(stackLines.length, lessThanOrEqualTo(101)); // 100 lines + truncation message
      expect(logs.first.stackTrace, contains('more lines'));
    });
  });

  group('Edge Cases', () {
    test('handles empty breadcrumbs', () async {
      await writeCrashLog(
        error: Exception('Test'),
        stackTrace: StackTrace.current,
        breadcrumbs: [],
      );

      final logs = await loadCrashLogs();
      expect(logs.first.breadcrumbs, isEmpty);
    });

    test('handles null breadcrumbs', () async {
      await writeCrashLog(
        error: Exception('Test'),
        stackTrace: StackTrace.current,
        breadcrumbs: null,
      );

      final logs = await loadCrashLogs();
      expect(logs.first.breadcrumbs, isEmpty);
    });

    test('handles error with no message', () async {
      await writeCrashLog(
        error: Exception(),
        stackTrace: StackTrace.current,
      );

      final logs = await loadCrashLogs();
      expect(logs.first.errorMessage, isNotNull);
    });
  });
}
