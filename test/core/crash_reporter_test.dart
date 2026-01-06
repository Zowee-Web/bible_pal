import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/crash_reporter.dart';

void main() {
  setUp(() {
    // Reset to noop reporter before each test
    resetCrashReporter();
  });

  group('CrashReporter Interface', () {
    test('crashReporter returns NoopCrashReporter by default', () {
      expect(crashReporter, isA<NoopCrashReporter>());
    });

    test('setCrashReporter changes active reporter', () {
      final customReporter = _MockCrashReporter();
      setCrashReporter(customReporter);

      expect(crashReporter, equals(customReporter));
    });

    test('resetCrashReporter restores noop reporter', () {
      final customReporter = _MockCrashReporter();
      setCrashReporter(customReporter);

      resetCrashReporter();

      expect(crashReporter, isA<NoopCrashReporter>());
    });
  });

  group('NoopCrashReporter', () {
    test('is singleton', () {
      final reporter1 = NoopCrashReporter.instance;
      final reporter2 = NoopCrashReporter.instance;
      expect(identical(reporter1, reporter2), isTrue);
    });

    test('recordBreadcrumb does not throw', () {
      expect(
        () => NoopCrashReporter.instance.recordBreadcrumb(
          event: 'test_event',
          data: {'key': 'value'},
          level: 'info',
          timestamp: DateTime.now(),
        ),
        returnsNormally,
      );
    });

    test('reportError does not throw', () {
      expect(
        () => NoopCrashReporter.instance.reportError(
          errorType: 'test_error',
          location: 'TestLocation',
          sanitizedMessage: 'Test message',
          additionalData: {'extra': 'data'},
        ),
        returnsNormally,
      );
    });

    test('reportFatalCrash does not throw', () {
      expect(
        () => NoopCrashReporter.instance.reportFatalCrash(
          error: Exception('Test error'),
          stackTrace: StackTrace.current,
          breadcrumbs: [
            {'event': 'test', 'level': 'info'},
          ],
        ),
        returnsNormally,
      );
    });

    test('setUserId does not throw', () {
      expect(
        () => NoopCrashReporter.instance.setUserId('anon_12345'),
        returnsNormally,
      );
    });

    test('setCustomKey does not throw', () {
      expect(
        () => NoopCrashReporter.instance.setCustomKey('app_version', '1.0.0'),
        returnsNormally,
      );
    });
  });

  group('CrashReporter Integration', () {
    test('custom reporter receives breadcrumbs', () {
      final mockReporter = _MockCrashReporter();
      setCrashReporter(mockReporter);

      crashReporter.recordBreadcrumb(
        event: 'test_event',
        data: {'story_id': 'parable_001'},
        level: 'info',
        timestamp: DateTime.now(),
      );

      expect(mockReporter.recordedBreadcrumbs, hasLength(1));
      expect(mockReporter.recordedBreadcrumbs.first['event'], equals('test_event'));
    });

    test('custom reporter receives errors', () {
      final mockReporter = _MockCrashReporter();
      setCrashReporter(mockReporter);

      crashReporter.reportError(
        errorType: 'audio_load_failed',
        location: 'AudioService.load',
        sanitizedMessage: 'File not found',
      );

      expect(mockReporter.reportedErrors, hasLength(1));
      expect(mockReporter.reportedErrors.first['errorType'], equals('audio_load_failed'));
    });

    test('custom reporter receives fatal crashes', () {
      final mockReporter = _MockCrashReporter();
      setCrashReporter(mockReporter);

      crashReporter.reportFatalCrash(
        error: StateError('Fatal state'),
        stackTrace: StackTrace.current,
      );

      expect(mockReporter.fatalCrashes, hasLength(1));
      expect(mockReporter.fatalCrashes.first['error'], isA<StateError>());
    });
  });

  group('CrashReporter Safe-Fail', () {
    test('handles null data in breadcrumb gracefully', () {
      expect(
        () => crashReporter.recordBreadcrumb(
          event: 'test',
          data: {'nullable': null},
          level: 'info',
          timestamp: DateTime.now(),
        ),
        returnsNormally,
      );
    });

    test('handles empty data in reportError gracefully', () {
      expect(
        () => crashReporter.reportError(
          errorType: 'test',
          location: 'Test',
        ),
        returnsNormally,
      );
    });
  });
}

/// Mock crash reporter for testing
class _MockCrashReporter implements CrashReporter {
  final List<Map<String, Object?>> recordedBreadcrumbs = [];
  final List<Map<String, Object?>> reportedErrors = [];
  final List<Map<String, Object?>> fatalCrashes = [];
  String? userId;
  final Map<String, Object> customKeys = {};

  @override
  void recordBreadcrumb({
    required String event,
    required Map<String, Object?> data,
    required String level,
    required DateTime timestamp,
  }) {
    recordedBreadcrumbs.add({
      'event': event,
      'data': data,
      'level': level,
      'timestamp': timestamp,
    });
  }

  @override
  void reportError({
    required String errorType,
    required String location,
    String? sanitizedMessage,
    Map<String, Object?>? additionalData,
  }) {
    reportedErrors.add({
      'errorType': errorType,
      'location': location,
      'message': sanitizedMessage,
      'additionalData': additionalData,
    });
  }

  @override
  void reportFatalCrash({
    required Object error,
    required StackTrace stackTrace,
    List<Map<String, Object?>>? breadcrumbs,
  }) {
    fatalCrashes.add({
      'error': error,
      'stackTrace': stackTrace,
      'breadcrumbs': breadcrumbs,
    });
  }

  @override
  void setUserId(String anonymousId) {
    userId = anonymousId;
  }

  @override
  void setCustomKey(String key, Object value) {
    customKeys[key] = value;
  }
}
