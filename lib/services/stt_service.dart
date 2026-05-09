import 'dart:async';

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

  /// Default listen duration (seconds). Long enough for the user to
  /// share how their day is going without being cut off mid-sentence.
  static const int defaultListenSeconds = 90;

  /// Hard ceiling on silence before the engine finalizes on its own.
  /// Acts as a safety net — the early-endpoint timer below normally
  /// finalizes much sooner.
  static const Duration defaultPauseDuration =
      Duration(milliseconds: 6500);

  /// Early-endpoint detection: if no new partial result arrives within
  /// this window after the user stops speaking, force the engine to
  /// finalize. Partial results stream every ~200ms while talking, so
  /// "no partials for N ms" is a reliable end-of-utterance signal —
  /// far snappier than waiting for [defaultPauseDuration] of silence.
  ///
  /// LOCKED at 3500ms. Calibrated to Adam's natural speaking cadence
  /// on 2026-04-27 (shorter values cut him off mid-sentence; longer
  /// felt laggy). Do not change without explicit user request.
  static const Duration defaultEndpointDelay =
      Duration(milliseconds: 3500);

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
    Duration pauseDuration = defaultPauseDuration,
    Duration endpointDelay = defaultEndpointDelay,
  }) async {
    if (!_available) {
      onError?.call('Speech recognition not available');
      return;
    }

    logEvent('voice_input_started', {
      'source': 'mic_tap',
    });

    Timer? endpointTimer;

    try {
      await _speech.listen(
        listenFor: Duration(seconds: listenSeconds),
        pauseFor: pauseDuration,
        localeId: 'en_US',
        listenOptions: SpeechListenOptions(partialResults: true),
        onResult: (SpeechRecognitionResult result) {
          final text = result.recognizedWords.trim();
          // Transcript is passed ONLY via callback — never logged.
          onResult(SttResult(
            text: text,
            isFinal: result.finalResult,
          ));
          if (result.finalResult) {
            endpointTimer?.cancel();
            endpointTimer = null;
          } else if (text.isNotEmpty) {
            // Reset the endpoint timer on every partial — only fires
            // once the partial stream goes quiet, which is the fastest
            // reliable end-of-utterance signal we get from the engine.
            endpointTimer?.cancel();
            endpointTimer = Timer(endpointDelay, () {
              _speech.stop();
            });
          }
        },
      );
    } catch (e) {
      endpointTimer?.cancel();
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
