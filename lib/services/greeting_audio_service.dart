import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart' as soloud;

/// Greeting audio service using SoLoud for reliable macOS playback.
///
/// Uses SoLoud (same as typewriter clicks) to avoid just_audio's macOS
/// audio routing issues.
///
/// Can be disabled via: --dart-define=DISABLE_SOLOUD_AUDIO=true
class GreetingAudioService {
  /// Flag to disable SoLoud for diagnostic purposes
  static const bool _useSoloud = !bool.fromEnvironment('DISABLE_SOLOUD_AUDIO');
  static GreetingAudioService? _instance;

  soloud.SoLoud? _soloud;
  soloud.AudioSource? _greetingSource;
  soloud.SoundHandle? _currentHandle;
  bool _initialized = false;

  /// WAV asset path for PAL greeting
  static const String _greetingAsset = 'assets/audio/pal_test_greeting.wav';

  GreetingAudioService._();

  /// Singleton instance
  static GreetingAudioService get instance {
    _instance ??= GreetingAudioService._();
    return _instance!;
  }

  /// Initialize the service (call once before use)
  Future<void> initialize() async {
    if (_initialized) return;

    // Skip SoLoud initialization if disabled via dart-define
    if (!_useSoloud) {
      if (kDebugMode) {
        debugPrint('GreetingAudioService: SoLoud disabled via DISABLE_SOLOUD_AUDIO');
      }
      _initialized = true;
      return;
    }

    try {
      _soloud = soloud.SoLoud.instance;
      await _soloud!.init();

      // Load greeting WAV into memory for instant playback
      _greetingSource = await _soloud!.loadAsset(_greetingAsset);

      _initialized = true;
      if (kDebugMode) {
        debugPrint('GreetingAudioService: SoLoud initialized');
      }
    } catch (e) {
      debugPrint('GreetingAudioService: SoLoud init failed: $e');
      _greetingSource = null;
      try {
        _soloud?.deinit();
      } catch (_) {}
      _soloud = null;
      _initialized = false;
    }
  }

  /// Play the greeting audio
  /// Always reloads the audio source to prevent hash not found errors
  Future<void> playGreeting() async {
    if (!_useSoloud) {
      if (kDebugMode) {
        debugPrint('GreetingAudioService: SoLoud disabled, skipping greeting');
      }
      return;
    }

    try {
      // Always reinitialize to ensure fresh audio source
      // This prevents "hash not found" errors from stale C++ references
      if (_greetingSource != null) {
        try {
          _soloud?.disposeSource(_greetingSource!);
        } catch (e) {
          debugPrint('GreetingAudioService: Error disposing old source: $e');
        }
        _greetingSource = null;
      }

      _initialized = false;

      if (kDebugMode) {
        debugPrint('GreetingAudioService: Reloading audio source...');
      }

      await initialize();

      if (!_initialized || _soloud == null || _greetingSource == null) {
        debugPrint('GreetingAudioService: Failed to initialize, cannot play');
        return;
      }

      // Play with full volume
      _currentHandle = await _soloud!.play(_greetingSource!, volume: 1.0);

      if (kDebugMode) {
        debugPrint('GreetingAudioService: Playing greeting');
      }
    } catch (e, stackTrace) {
      debugPrint('GreetingAudioService: Play failed: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// Stop any currently playing greeting audio without deiniting SoLoud.
  /// Safe to call even if nothing is playing.
  void stopPlayback() {
    if (_currentHandle != null && _soloud != null) {
      try {
        _soloud!.stop(_currentHandle!);
      } catch (_) {
        // Safe-fail: stopping should never throw to caller.
      }
      _currentHandle = null;
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    if (_greetingSource != null) {
      _soloud?.disposeSource(_greetingSource!);
      _greetingSource = null;
    }

    try {
      _soloud?.deinit();
    } catch (_) {}
    _soloud = null;
    _initialized = false;
  }
}
