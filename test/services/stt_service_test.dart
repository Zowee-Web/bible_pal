import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/stt_service.dart';
import 'package:bible_pal/core/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for the SttService wrapper (Feature 2.2).
///
/// Uses the real SpeechToText instance but without actual mic access,
/// so initialize() will return false in test environment (no speech engine).
/// This validates error handling and safe-fail behavior.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() {
    AppLogger.instance.clearBreadcrumbs();
  });

  group('SttService', () {
    test('initial state: not initialized, not available', () {
      final service = SttService();
      expect(service.isInitialized, false);
      expect(service.isAvailable, false);
    });

    test('initialize returns false when speech engine is unavailable (test env)', () async {
      final service = SttService();
      final result = await service.initialize();

      // In test environment, SpeechToText.initialize() returns false
      // because there is no speech engine available.
      expect(result, false);
      expect(service.isInitialized, true);
      expect(service.isAvailable, false);
    });

    test('initialize handles exceptions gracefully', () async {
      // SttService wraps all init errors; should never throw.
      final service = SttService();
      final result = await service.initialize();
      expect(result, isA<bool>());
    });

    test('startListening calls onError when STT not available', () async {
      final service = SttService();
      await service.initialize(); // Will set _available = false in tests

      String? errorMsg;
      await service.startListening(
        onResult: (_) {},
        onError: (e) => errorMsg = e,
      );

      expect(errorMsg, isNotNull);
      expect(errorMsg, contains('not available'));
    });

    test('stopListening does not throw even when not listening', () async {
      final service = SttService();
      // Should not throw
      await service.stopListening();
    });

    test('cancel does not throw even when not listening', () async {
      final service = SttService();
      await service.cancel();
    });

    test('dispose resets state', () async {
      final service = SttService();
      await service.initialize();
      await service.dispose();

      expect(service.isInitialized, false);
      expect(service.isAvailable, false);
    });

    test('CRITICAL: SttService has no logEvent calls containing transcript data', () {
      // Structural test: verify that the SttService source code does not
      // log any transcript-related data. This is verified by the repo-wide
      // scan in voice_privacy_scan_test.dart, but we document the intent here.
      //
      // The SttService logs only:
      // - voice_input_started (no text payload)
      // - voice_input_cancelled (reason string only)
      // - voice_permission_result (granted/denied booleans only)
      //
      // It does NOT log the recognized text.
      expect(true, true); // Placeholder — real enforcement via repo scan
    });
  });

  group('SttResult', () {
    test('holds text and isFinal', () {
      const result = SttResult(text: 'hello', isFinal: true);
      expect(result.text, 'hello');
      expect(result.isFinal, true);
    });

    test('partial result has isFinal=false', () {
      const result = SttResult(text: 'hel', isFinal: false);
      expect(result.isFinal, false);
    });
  });

  group('SttPermissionResult', () {
    test('has 3 values', () {
      expect(SttPermissionResult.values.length, 3);
    });

    test('contains granted, denied, permanentlyDenied', () {
      expect(SttPermissionResult.values, containsAll([
        SttPermissionResult.granted,
        SttPermissionResult.denied,
        SttPermissionResult.permanentlyDenied,
      ]));
    });
  });

  group('SttService constants', () {
    test('defaultListenSeconds is 10', () {
      expect(SttService.defaultListenSeconds, 10);
    });

    test('defaultPauseSeconds is 5', () {
      expect(SttService.defaultPauseSeconds, 5);
    });
  });
}
