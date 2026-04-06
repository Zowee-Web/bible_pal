import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../core/app_logger.dart';

/// Audio Service - handles playback of parable audio files
/// Based on SPEC.md Feature #16: ElevenLabs v3 Multi-Voice Playback
class AudioService {
  final AudioPlayer _player;
  String? _currentStoryId;

  AudioService() : _player = AudioPlayer() {
    _initAudioSession();
  }

  /// Configure audio session for background playback with mixing support.
  /// mixWithOthers allows ambient audio to play alongside narration.
  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
      ));
    } catch (e) {
      debugPrint('Audio session init failed: $e');
    }
  }

  /// Get the audio player instance
  AudioPlayer get player => _player;

  /// Load and prepare audio file for playback
  Future<void> loadAudio(File audioFile, {String? storyId}) async {
    try {
      _currentStoryId = storyId;
      await _player.setFilePath(audioFile.path);
      debugPrint('Audio loaded: ${audioFile.path}');
    } catch (e) {
      debugPrint('Error loading audio: $e');

      logEvent(
          'audio_error',
          {
            'story_id': storyId,
            'error_type': 'load_failed',
          },
          level: LogLevel.error);

      rethrow;
    }
  }

  /// Load and play audio from asset bundle (dev/test use)
  Future<void> playAsset(String assetPath) async {
    try {
      // Stop any existing playback first
      if (isPlaying) {
        debugPrint('Stopping current audio to play new asset');
        await stop();
      }

      await _player.setAsset(assetPath);
      await _player.play();
      debugPrint('Playing asset: $assetPath');
    } catch (e) {
      debugPrint('Error playing asset: $e');
    }
  }

  /// Play the loaded audio
  Future<void> play() async {
    try {
      // Log play start
      logEvent('audio_play_start', {
        'story_id': _currentStoryId,
        'position_ms': _player.position.inMilliseconds,
      });

      await _player.play();
    } catch (e) {
      debugPrint('Error playing audio: $e');

      logEvent(
          'audio_error',
          {
            'story_id': _currentStoryId,
            'error_type': 'play_failed',
          },
          level: LogLevel.error);

      rethrow;
    }
  }

  /// Pause playback
  Future<void> pause() async {
    // Log pause event
    logEvent('audio_play_pause', {
      'story_id': _currentStoryId,
      'position_ms': _player.position.inMilliseconds,
    });

    await _player.pause();
  }

  /// Stop playback and reset position
  Future<void> stop() async {
    await _player.stop();
    await _player.seek(Duration.zero);
  }

  /// Seek to a specific position
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Set playback speed (0.5 to 2.0)
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed.clamp(0.5, 2.0));
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  /// Gradually fade volume to 0 over [duration], then stop playback.
  Future<void> fadeOutAndStop({Duration duration = const Duration(seconds: 5)}) async {
    const steps = 20;
    final currentVolume = _player.volume;
    final stepDuration = Duration(milliseconds: duration.inMilliseconds ~/ steps);
    for (var i = 1; i <= steps; i++) {
      final vol = currentVolume * (1.0 - (i / steps));
      await _player.setVolume(vol.clamp(0.0, 1.0));
      await Future.delayed(stepDuration);
    }
    await stop();
    await _player.setVolume(1.0); // Reset volume for next playback
  }

  /// Get current playback position
  Duration get position => _player.position;

  /// Get total duration
  Duration? get duration => _player.duration;

  /// Get current playback state
  PlayerState get playerState => _player.playerState;

  /// Stream of position updates
  Stream<Duration> get positionStream => _player.positionStream;

  /// Stream of duration updates
  Stream<Duration?> get durationStream => _player.durationStream;

  /// Stream of player state updates
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// Stream of playback completed events
  Stream<void> get playbackCompletedStream => _player.playerStateStream
      .where((state) => state.processingState == ProcessingState.completed)
      .map((_) {});

  /// Check if audio is currently playing
  bool get isPlaying => _player.playing;

  /// Check if audio is paused
  bool get isPaused => !_player.playing && _player.position > Duration.zero;

  /// Dispose the audio player
  Future<void> dispose() async {
    await _player.dispose();
  }
}
