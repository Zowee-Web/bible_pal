import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:just_audio/just_audio.dart';
import 'typewriter_click_fallback.dart';

/// just_audio-based fallback pool for desktop builds.
/// Used when SoLoud is disabled or fails to initialize.
class TypewriterFallbackPoolImpl implements TypewriterFallbackPool {
  final List<AudioPlayer> _pool = [];
  int _poolIndex = 0;
  static const int _poolSize = 6;

  @override
  Future<void> init(List<String> assetPaths) async {
    try {
      // Create pool of audio players for rapid-fire clicks
      // 3 WAV variants × 2 players each = 6 total for overlapping playback
      for (int i = 0; i < _poolSize; i++) {
        final player = AudioPlayer();
        // Round-robin through WAV variants (A, B, C, A, B, C)
        final assetPath = assetPaths[i % assetPaths.length];
        await player.setAsset(assetPath);
        // Subtle volume variation: 0.68, 0.70, 0.72 (mechanical realism)
        final volume = 0.68 + (i % 3) * 0.02;
        await player.setVolume(volume);
        _pool.add(player);
      }
      if (kDebugMode) {
        debugPrint(
            'TypewriterFallbackPool: just_audio initialized ($_poolSize players)');
      }
    } catch (e) {
      debugPrint('TypewriterFallbackPool: Failed to initialize: $e');
      // Clean up any partially created players
      for (final p in _pool) {
        await p.dispose();
      }
      _pool.clear();
    }
  }

  @override
  void playClick() {
    if (_pool.isEmpty) return;

    final playedIndex = _poolIndex;
    final player = _pool[playedIndex];
    _poolIndex = (_poolIndex + 1) % _pool.length;

    // Fire-and-forget: seek and play without awaiting
    unawaited(player.seek(Duration.zero).then((_) => player.play()));

    if (kDebugMode) {
      debugPrint('typewriter_sfx_play: just_audio_pool[$playedIndex]');
    }
  }

  @override
  Future<void> dispose() async {
    for (final player in _pool) {
      await player.dispose();
    }
    _pool.clear();
    _poolIndex = 0;
  }

  @override
  bool get isReady => _pool.isNotEmpty;
}

/// Factory function for conditional import.
TypewriterFallbackPool createFallbackPool() => TypewriterFallbackPoolImpl();
