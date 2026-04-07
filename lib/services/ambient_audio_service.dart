import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ambient_sound_type.dart';
import '../core/app_logger.dart';

const _pkBackgroundSound = 'settings.backgroundSoundOn';
const _pkAmbientSoundType = 'settings.ambientSoundType';
const _pkAmbientVolume = 'settings.ambientVolume';

/// Ambient background audio service for story playback (Feature 49).
///
/// Plays looping ambient sounds during story narration.
/// Controlled from player screen; settings persist in SharedPreferences.
class AmbientAudioService {
  final AudioPlayer _player;

  static const double defaultVolume = 0.10;

  AmbientSoundType? _activeType;
  bool _isStarting = false;

  AmbientAudioService({AudioPlayer? player})
      : _player = player ?? AudioPlayer(
          handleAudioSessionActivation: false,
        );

  bool get isPlaying => _activeType != null;
  AmbientSoundType? get activeType => _activeType;

  /// Start ambient audio if background sound is enabled in settings.
  /// Called by ParablePlayerNotifier.play() when narration starts.
  Future<void> startIfEnabled() async {
    if (_isStarting) return;

    final sp = await SharedPreferences.getInstance();
    final enabled = sp.getBool(_pkBackgroundSound) ?? false;
    if (!enabled) return;

    await _startPlayback(sp);
  }

  /// Force-start ambient audio regardless of the toggle setting.
  /// Used by the player screen preview toggle.
  Future<void> forceStart() async {
    if (_isStarting) return;
    final sp = await SharedPreferences.getInstance();
    await _startPlayback(sp);
  }

  Future<void> _startPlayback(SharedPreferences sp) async {
    final typeStr = sp.getString(_pkAmbientSoundType);
    final requestedType = AmbientSoundType.fromString(typeStr);
    final volume = sp.getDouble(_pkAmbientVolume) ?? defaultVolume;

    // Already playing the same sound — no-op
    if (_activeType == requestedType) return;

    // Playing a different sound — stop first
    if (_activeType != null) {
      await forceStop();
    }

    _isStarting = true;
    try {
      await _player.setAsset(requestedType.assetPath);
      await _player.setLoopMode(LoopMode.one);
      await _player.setVolume(volume);
      await _player.play();
      _activeType = requestedType;

      logEvent('ambient_started', {'sound_type': requestedType.assetName});
    } catch (e) {
      debugPrint('AmbientAudioService: Failed to start: $e');
      logEvent('audio_error', {
        'source': 'ambient',
        'error_type': e.runtimeType.toString(),
      }, level: LogLevel.error);
      _activeType = null;
    } finally {
      _isStarting = false;
    }
  }

  /// Update volume on the live player.
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  /// Stop ambient audio. Always stops regardless of state.
  Future<void> forceStop() async {
    final stoppedType = _activeType;
    _activeType = null;
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('AmbientAudioService: Failed to stop: $e');
    }
    if (stoppedType != null) {
      logEvent('ambient_stopped', {'sound_type': stoppedType.assetName});
    }
  }

  /// Stop ambient audio (only if playing).
  Future<void> stop() async {
    if (_activeType == null) return;
    await forceStop();
  }

  Future<void> dispose() async {
    _activeType = null;
    await _player.dispose();
  }
}
