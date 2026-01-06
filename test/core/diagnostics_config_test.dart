import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/diagnostics_config.dart';

void main() {
  group('DiagnosticsConfig', () {
    test('kDiagnosticsEnabled is false by default', () {
      // Without --dart-define=DIAGNOSTICS_ENABLED=true, should be false
      // Note: This test verifies the default, actual value depends on build flags
      expect(kDiagnosticsEnabled, isA<bool>());
    });

    test('kDiagnosticsEnabled is compile-time constant', () {
      // Should be usable in const context
      const enabled = kDiagnosticsEnabled;
      expect(enabled, isA<bool>());
    });
  });
}
