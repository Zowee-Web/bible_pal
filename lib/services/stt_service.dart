import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:bible_pal/core/app_logger.dart';

/// Result of a speech recognition callback.
class SttResult {
  final String text;
  final bool isFinal;

  const SttResult({required this.text, required this.isFinal});
}

/// Permission check result for microphone + speech recognition.
enum SttPermissionResult {
  granted,
  denied,
  permanentlyDenied,
}

/// Thin wrapper around [SpeechToText] for voice mood input.
///
/// Design constraints (Invariant 17):
/// - No transcript data may be logged, stored, or transmitted.
/// - This service only surfaces transcripts via the [onResult] callback.
/// - Supports dependency injection: pass a custom [SpeechToText] instance
///   for testing (avoids real microphone access in unit/widget tests).
class SttService {
  final SpeechToText _speech;
  bool _initialized = false;
  bool _available = false;

  /// Default listen duration (seconds).
  static const int defaultListenSeconds = 10;

  /// Default pause-for-silence duration (seconds).
  static const int defaultPauseSeconds = 3;

  /// Create with an optional [SpeechToText] instance for DI/testing.
  SttService({SpeechToText? speech}) : _speech = speech ?? SpeechToText();

  /// Whether the speech engine is available on this platform.
  bool get isAvailable => _available;

  /// Whether the service has been initialized.
  bool get isInitialized => _initialized;

  /// Timeout for microphone permission request (prevents indefinite spinner).
  static const Duration _permissionTimeout = Duration(seconds: 8);

  /// Check and request microphone permission, then initialize speech engine.
  ///
  /// Speech recognition authorization is handled internally by
  /// [SpeechToText.initialize] — we do NOT call [Permission.speech.request]
  /// separately, as that can hang indefinitely on macOS.
  Future<SttPermissionResult> checkPermissions() async {
    try {
      final mic = await Permission.microphone
          .request()
          .timeout(_permissionTimeout, onTimeout: () => PermissionStatus.denied);

      if (mic.isPermanentlyDenied) {
        logEvent('voice_permission_result', {
          'granted': false,
          'permanently_denied': true,
        });
        return SttPermissionResult.permanentlyDenied;
      }

      if (!mic.isGranted) {
        logEvent('voice_permission_result', {
          'granted': false,
          'permanently_denied': false,
        });
        return SttPermissionResult.denied;
      }

      // Mic granted — initialize speech engine (handles speech auth internally)
      final available = await initialize();
      if (!available) {
        logEvent('voice_permission_result', {
          'granted': false,
          'permanently_denied': false,
        });
        return SttPermissionResult.denied;
      }

      logEvent('voice_permission_result', {
        'granted': true,
        'permanently_denied': false,
      });
      return SttPermissionResult.granted;
    } catch (e) {
      logEvent('voice_permission_result', {
        'granted': false,
        'permanently_denied': false,
      });
      return SttPermissionResult.denied;
    }
  }

  /// Initialize the speech recognition engine.
  /// Returns `true` if the engine is available, `false` otherwise.
  Future<bool> initialize() async {
    if (_initialized && _available) return true;

    try {
      _available = await _speech.initialize(
        debugLogging: false,
      );
      _initialized = true;
    } catch (e) {
      _available = false;
      _initialized = true;
      // Log that STT is unavailable (no user data in this event)
      logEvent('voice_input_cancelled', {
        'reason': 'stt_unavailable',
      });
    }

    return _available;
  }

  /// Start listening for speech input.
  ///
  /// [onResult] is called with partial and final results.
  /// [onError] is called if the speech engine encounters an error.
  ///
  /// No transcript data is logged by this method (Invariant 17).
  Future<void> startListening({
    required void Function(SttResult result) onResult,
    void Function(String error)? onError,
    int listenSeconds = defaultListenSeconds,
    int pauseSeconds = defaultPauseSeconds,
  }) async {
    if (!_available) {
      onError?.call('Speech recognition not available');
      return;
    }

    logEvent('voice_input_started', {
      'source': 'mic_tap',
    });

    try {
      await _speech.listen(
        listenFor: Duration(seconds: listenSeconds),
        pauseFor: Duration(seconds: pauseSeconds),
        listenOptions: SpeechListenOptions(partialResults: true),
        onResult: (SpeechRecognitionResult result) {
          // Transcript is passed ONLY via callback — never logged.
          onResult(SttResult(
            text: result.recognizedWords.trim(),
            isFinal: result.finalResult,
          ));
        },
      );
    } catch (e) {
      onError?.call(e.toString());
    }
  }

  /// Stop active listening.
  Future<void> stopListening() async {
    try {
      await _speech.stop();
    } catch (_) {
      // Safe-fail: stopping should never throw to caller.
    }
  }

  /// Cancel active listening (discards partial results).
  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } catch (_) {
      // Safe-fail.
    }
  }

  /// Release resources. Call when the widget is disposed.
  Future<void> dispose() async {
    await cancel();
    _initialized = false;
    _available = false;
  }
}
