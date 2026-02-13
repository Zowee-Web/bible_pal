import 'dart:math' show Random;
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart'
    show HapticFeedback, SystemSound, SystemSoundType;
import 'package:flutter_soloud/flutter_soloud.dart' as soloud;

// Conditional import: use just_audio fallback only on non-web platforms
import 'typewriter_click_fallback_stub.dart'
    if (dart.library.io) 'typewriter_click_fallback_just_audio.dart'
    as tw_fallback;

import 'typewriter_click_fallback.dart';

/// Dev-only toggle for SoLoud vs just_audio fallback on desktop.
/// Set to false to revert to just_audio pool if SoLoud causes issues.
/// Can be disabled via: --dart-define=DISABLE_SOLOUD_AUDIO=true
const bool kUseSoloudTypewriter = !bool.fromEnvironment('DISABLE_SOLOUD_AUDIO');

/// Minimum click interval (ms) - at 70ms typing speed, this allows every click
const int kMinClickIntervalMs = 50;

/// Typewriter click sound service for PAL intro typing animations.
///
/// Platform behavior:
/// - iOS/Android: Uses SystemSound.click + haptic feedback (native, low-latency)
/// - macOS/Desktop: Uses SoLoud for low-latency rapid-fire clicks (or just_audio fallback)
/// - Web: No typewriter clicks (stub fallback)
///
/// This service is intentionally NOT user-configurable.
/// Typewriter clicks are reserved exclusively for PAL intro moments.
class TypewriterClickService {
  static TypewriterClickService? _instance;

  // SoLoud engine and loaded sounds (desktop with kUseSoloudTypewriter)
  soloud.SoLoud? _soloud;
  final List<soloud.AudioSource> _soloudSources = [];
  int _soloudIndex = 0;
  final _random = Random();

  // Fallback pool (conditionally imported: just_audio on desktop, no-op on web)
  TypewriterFallbackPool? _fallbackPool;

  /// WAV asset paths for mechanical click variation
  static const List<String> _wavAssets = [
    'assets/audio/typewriter_click_a.wav',
    'assets/audio/typewriter_click_b.wav',
    'assets/audio/typewriter_click_c.wav',
  ];

  bool _initialized = false;
  bool _isDesktop = false;
  bool _isMobile = false;
  bool _usingSoloud = false;

  TypewriterClickService._();

  /// Singleton instance
  static TypewriterClickService get instance {
    _instance ??= TypewriterClickService._();
    return _instance!;
  }

  /// Whether the service is running on desktop (for cadence clamping).
  bool get isDesktop => _isDesktop;

  /// Initialize the service (call once at app startup or before use)
  Future<void> initialize() async {
    if (_initialized) return;

    // Detect platform types (web-safe)
    _isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);

    _isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);

    if (_isDesktop) {
      if (kUseSoloudTypewriter) {
        await _initSoloud();
      }
      // Fallback to just_audio if SoLoud failed or disabled
      if (!_usingSoloud) {
        await _initFallbackPool();
      }
    }

    _initialized = true;
  }

  /// Initialize SoLoud engine and load click sounds
  Future<void> _initSoloud() async {
    try {
      _soloud = soloud.SoLoud.instance;
      await _soloud!.init();

      // Load all 3 WAV variants into memory for instant playback
      for (final assetPath in _wavAssets) {
        final source = await _soloud!.loadAsset(assetPath);
        _soloudSources.add(source);
      }

      _usingSoloud = true;
      if (kDebugMode) {
        debugPrint(
            'TypewriterClickService: SoLoud initialized (${_soloudSources.length} click variants)');
      }
    } catch (e) {
      debugPrint('TypewriterClickService: SoLoud init failed: $e');
      // Clean up on failure
      _soloudSources.clear();
      try {
        _soloud?.deinit();
      } catch (_) {}
      _soloud = null;
      _usingSoloud = false;
    }
  }

  /// Initialize fallback pool (conditionally imported)
  Future<void> _initFallbackPool() async {
    _fallbackPool = tw_fallback.createFallbackPool();
    await _fallbackPool!.init(_wavAssets);
    if (kDebugMode && _fallbackPool!.isReady) {
      debugPrint('TypewriterClickService: Fallback pool initialized');
    }
  }

  /// Play a single click sound with optional haptic feedback.
  ///
  /// On iOS/Android: SystemSound.click + HapticFeedback (mobile only)
  /// On macOS/Desktop: SoLoud instant playback (or just_audio fallback), no haptics
  /// On Web: No-op
  void playClick({bool withHaptic = true}) {
    if (!_initialized) {
      // Should have been pre-initialized, but handle gracefully
      if (kDebugMode) {
        debugPrint('TypewriterClickService: playClick called before init');
      }
      return;
    }

    if (_isDesktop) {
      if (_usingSoloud && _soloud != null && _soloudSources.isNotEmpty) {
        _playSoloudClick();
      } else if (_fallbackPool != null && _fallbackPool!.isReady) {
        _fallbackPool!.playClick();
      }
      // No haptics on desktop
    } else if (_isMobile) {
      // iOS/Android: system sound
      if (kDebugMode) {
        debugPrint('typewriter_sfx_play: system_sound');
      }
      SystemSound.play(SystemSoundType.click);

      // Haptic feedback only on mobile
      if (withHaptic) {
        HapticFeedback.selectionClick();
      }
    }
    // Web: no-op (no sound, no haptics)
  }

  /// Play click via SoLoud (instant, low-latency)
  void _playSoloudClick() {
    final source = _soloudSources[_soloudIndex];
    _soloudIndex = (_soloudIndex + 1) % _soloudSources.length;

    // Small volume variation for mechanical realism: 0.65-0.71
    final volume = 0.65 + _random.nextDouble() * 0.06;

    // Fire-and-forget: SoLoud.play is synchronous and instant
    _soloud!.play(source, volume: volume);

    if (kDebugMode) {
      debugPrint(
          'typewriter_sfx_play: soloud[$_soloudIndex] vol=${volume.toStringAsFixed(2)}');
    }
  }

  /// Dispose resources when no longer needed
  Future<void> dispose() async {
    // Dispose SoLoud
    for (final source in _soloudSources) {
      _soloud?.disposeSource(source);
    }
    _soloudSources.clear();
    try {
      _soloud?.deinit();
    } catch (_) {}
    _soloud = null;
    _usingSoloud = false;

    // Dispose fallback pool
    await _fallbackPool?.dispose();
    _fallbackPool = null;

    _soloudIndex = 0;
    _initialized = false;
  }
}

/// Typewriter click sound helper for typing animations.
///
/// Plays click on EVERY non-whitespace character for authentic typewriter feel.
/// Only active during PAL intro typing — disable explicitly when intro ends.
///
/// IMPORTANT: Call this BEFORE setState() for proper audio-visual sync.
class TypewriterClickHelper {
  final TypewriterClickService _service = TypewriterClickService.instance;
  bool _serviceInitialized = false;
  DateTime _lastClick = DateTime(1970);
  bool enabled = true;

  TypewriterClickHelper();

  /// Pre-initialize the audio service for instant playback on first character.
  /// Call this in initState() before typing animation starts.
  Future<void> preInitialize() async {
    if (!_serviceInitialized) {
      await _service.initialize();
      _serviceInitialized = true;
    }
  }

  /// Call this BEFORE setState() when a character is about to be appended.
  /// Plays click synchronously (fire-and-forget) for proper timing.
  void onCharAppended(String char) {
    // Gate: only play during PAL intro typing
    if (!enabled) return;

    // Skip whitespace and control characters
    if (char.isEmpty ||
        char == ' ' ||
        char == '\n' ||
        char == '\r' ||
        char == '\t') {
      return;
    }

    // Simple rate limit to prevent audio overlap
    final now = DateTime.now();
    if (now.difference(_lastClick).inMilliseconds < kMinClickIntervalMs) {
      return;
    }
    _lastClick = now;

    // Play click on every non-whitespace character
    _service.playClick();
  }

  /// Reset state (useful if restarting animation)
  void reset() {
    _lastClick = DateTime(1970);
  }
}
