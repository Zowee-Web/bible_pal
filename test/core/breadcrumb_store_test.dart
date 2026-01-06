import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/core/breadcrumb_store.dart';
import 'package:bible_pal/core/diagnostics_config.dart';

void main() {
  setUp(() {
    // Reset store state before each test
    BreadcrumbStore.instance.reset();
    // Set up mock SharedPreferences
    SharedPreferences.setMockInitialValues({});
  });

  group('BreadcrumbStore', () {
    test('is singleton', () {
      final store1 = BreadcrumbStore.instance;
      final store2 = BreadcrumbStore.instance;
      expect(identical(store1, store2), isTrue);
    });

    test('queueBreadcrumb adds to pending queue', () {
      // Note: This test behavior depends on kDiagnosticsEnabled
      BreadcrumbStore.instance.queueBreadcrumb({
        'event': 'test_event',
        'level': 'info',
        'ts': DateTime.now().toIso8601String(),
      });

      if (kDiagnosticsEnabled) {
        expect(BreadcrumbStore.instance.pendingWriteCount, equals(1));
      } else {
        // When disabled, queue is not used
        expect(BreadcrumbStore.instance.pendingWriteCount, equals(0));
      }
    });

    test('reset clears pending writes', () {
      // Queue some breadcrumbs (only works if diagnostics enabled)
      BreadcrumbStore.instance.queueBreadcrumb({'event': 'test1'});
      BreadcrumbStore.instance.queueBreadcrumb({'event': 'test2'});

      BreadcrumbStore.instance.reset();

      expect(BreadcrumbStore.instance.pendingWriteCount, equals(0));
    });

    test('loadPersistedBreadcrumbs returns empty list when disabled', () async {
      final result = await BreadcrumbStore.instance.loadPersistedBreadcrumbs();

      if (kDiagnosticsEnabled) {
        // With no data, should return empty
        expect(result, isEmpty);
      } else {
        // When disabled, always returns empty
        expect(result, isEmpty);
      }
    });

    test('loadPersistedBreadcrumbs handles invalid JSON gracefully', () async {
      SharedPreferences.setMockInitialValues({
        'diagnostics.breadcrumbs': 'not valid json',
      });

      // Should not throw, returns empty list
      final result = await loadPersistedBreadcrumbs();
      expect(result, isEmpty);
    });

    test('loadPersistedBreadcrumbs handles non-list JSON gracefully', () async {
      SharedPreferences.setMockInitialValues({
        'diagnostics.breadcrumbs': '{"not": "a list"}',
      });

      final result = await loadPersistedBreadcrumbs();
      expect(result, isEmpty);
    });

    test('clear removes persisted data', () async {
      SharedPreferences.setMockInitialValues({
        'diagnostics.breadcrumbs': '[{"event": "old_event"}]',
      });

      await BreadcrumbStore.instance.clear();

      final result = await loadPersistedBreadcrumbs();
      expect(result, isEmpty);
    });

    test('convenience functions work', () async {
      // queueBreadcrumbForPersistence
      queueBreadcrumbForPersistence({'event': 'test'});

      // flushBreadcrumbsNow
      await flushBreadcrumbsNow();

      // loadPersistedBreadcrumbs
      final result = await loadPersistedBreadcrumbs();
      expect(result, isA<List<Map<String, Object?>>>());
    });
  });

  group('BreadcrumbStore Safe-Fail', () {
    test('queueBreadcrumb never throws with null values', () {
      expect(
        () => BreadcrumbStore.instance.queueBreadcrumb({'key': null}),
        returnsNormally,
      );
    });

    test('queueBreadcrumb never throws with empty map', () {
      expect(
        () => BreadcrumbStore.instance.queueBreadcrumb({}),
        returnsNormally,
      );
    });

    test('flushNow never throws', () async {
      // Should not throw even with no data
      await expectLater(
        BreadcrumbStore.instance.flushNow(),
        completes,
      );
    });

    test('clear never throws', () async {
      await expectLater(
        BreadcrumbStore.instance.clear(),
        completes,
      );
    });

    test('loadPersistedBreadcrumbs never throws', () async {
      await expectLater(
        loadPersistedBreadcrumbs(),
        completes,
      );
    });
  });

  group('BreadcrumbStore Throttling', () {
    test('multiple queues do not trigger immediate writes', () {
      // Queue multiple breadcrumbs rapidly
      for (var i = 0; i < 10; i++) {
        BreadcrumbStore.instance.queueBreadcrumb({
          'event': 'rapid_event_$i',
          'index': i,
        });
      }

      // If diagnostics enabled, all should be pending (not written yet due to throttle)
      if (kDiagnosticsEnabled) {
        expect(BreadcrumbStore.instance.pendingWriteCount, equals(10));
      }
    });
  });
}
