import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/diagnostics_lifecycle_observer.dart';
import 'package:bible_pal/core/diagnostics_config.dart';

void main() {
  setUp(() {
    // Ensure clean state
    DiagnosticsLifecycleObserver.dispose();
  });

  tearDown(() {
    DiagnosticsLifecycleObserver.dispose();
  });

  group('DiagnosticsLifecycleObserver', () {
    test('initialize registers observer only when diagnostics enabled', () {
      // Initialize
      initializeDiagnosticsLifecycle();

      if (kDiagnosticsEnabled) {
        expect(DiagnosticsLifecycleObserver.isRegistered, isTrue);
      } else {
        expect(DiagnosticsLifecycleObserver.isRegistered, isFalse);
      }
    });

    test('initialize is idempotent - multiple calls safe', () {
      initializeDiagnosticsLifecycle();
      initializeDiagnosticsLifecycle();
      initializeDiagnosticsLifecycle();

      // Should not throw, and state should be consistent
      if (kDiagnosticsEnabled) {
        expect(DiagnosticsLifecycleObserver.isRegistered, isTrue);
      } else {
        expect(DiagnosticsLifecycleObserver.isRegistered, isFalse);
      }
    });

    test('dispose unregisters observer', () {
      initializeDiagnosticsLifecycle();
      DiagnosticsLifecycleObserver.dispose();

      expect(DiagnosticsLifecycleObserver.isRegistered, isFalse);
    });

    test('dispose is safe to call when not registered', () {
      // Should not throw
      expect(
        () => DiagnosticsLifecycleObserver.dispose(),
        returnsNormally,
      );
    });

    test('dispose is safe to call multiple times', () {
      initializeDiagnosticsLifecycle();
      DiagnosticsLifecycleObserver.dispose();
      DiagnosticsLifecycleObserver.dispose();
      DiagnosticsLifecycleObserver.dispose();

      expect(DiagnosticsLifecycleObserver.isRegistered, isFalse);
    });
  });

  group('DiagnosticsLifecycleObserver Safe-Fail', () {
    test('initialize never throws', () {
      expect(
        () => initializeDiagnosticsLifecycle(),
        returnsNormally,
      );
    });

    test('dispose never throws', () {
      expect(
        () => DiagnosticsLifecycleObserver.dispose(),
        returnsNormally,
      );
    });
  });
}
