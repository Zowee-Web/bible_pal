import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/services/audio_service.dart';
import 'package:bible_pal/core/app_logger.dart';
import 'service_providers.dart';

/// Parable Player State
class ParablePlayerState {
  final Parable? currentParable;
  final String? parableText;
  final bool isLoading;
  final String? errorMessage;

  const ParablePlayerState({
    this.currentParable,
    this.parableText,
    this.isLoading = false,
    this.errorMessage,
  });

  ParablePlayerState copyWith({
    Parable? currentParable,
    String? parableText,
    bool? isLoading,
    String? errorMessage,
  }) {
    return ParablePlayerState(
      currentParable: currentParable ?? this.currentParable,
      parableText: parableText ?? this.parableText,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  ParablePlayerState clearParable() {
    return const ParablePlayerState();
  }
}

/// Parable Player Notifier - manages parable playback state
class ParablePlayerNotifier extends Notifier<ParablePlayerState> {
  late AudioService _audioService;

  @override
  ParablePlayerState build() {
    // Get services
    _audioService = ref.watch(audioServiceProvider);
    // ParableService is FutureProvider - we'll await it when needed in async methods

    // Listen to audio state changes
    _listenToAudioState();

    return const ParablePlayerState();
  }

  // Getters for audio state
  AudioService get audioService => _audioService;
  bool get isPlaying => _audioService.isPlaying;
  bool get isPaused => _audioService.isPaused;
  Duration get position => _audioService.position;
  Duration? get duration => _audioService.duration;

  // Streams
  Stream<Duration> get positionStream => _audioService.positionStream;
  Stream<Duration?> get durationStream => _audioService.durationStream;

  /// Listen to audio state changes
  void _listenToAudioState() {
    _audioService.playerStateStream.listen((_) {
      // Notify listeners when audio state changes
      // This triggers rebuilds for widgets watching playback state
      ref.notifyListeners();
    });

    _audioService.playbackCompletedStream.listen((_) {
      _onPlaybackCompleted();
    });
  }

  /// Load and prepare a parable for playback
  Future<void> loadParable(Parable parable) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      // Get ParableService
      final parableService = await ref.read(parableServiceProvider.future);

      // Load audio file
      final audioFile = await parableService.getAudioFile(parable);
      if (audioFile == null) {
        logEvent('audio_asset_missing', {
          'story_id': parable.storyId,
          'expected_path': parable.audioFilePath,
        }, level: LogLevel.error);

        throw Exception('Audio file not found for parable: ${parable.storyId}');
      }

      await _audioService.loadAudio(audioFile, storyId: parable.storyId);

      // Load text (optional, for scripture panel)
      final parableText = await parableService.getParableText(parable);

      state = ParablePlayerState(
        currentParable: parable,
        parableText: parableText,
        isLoading: false,
      );
    } catch (e) {
      logError('parable_load_failed', 'ParablePlayerNotifier.loadParable',
          storyId: parable.storyId, errorMessage: e.toString());

      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error loading parable: $e',
      );
      rethrow;
    }
  }

  /// Play the current parable
  Future<void> play() async {
    if (state.currentParable == null) return;

    try {
      await _audioService.play();
      ref.notifyListeners();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Error playing audio: $e');
    }
  }

  /// Pause playback
  Future<void> pause() async {
    await _audioService.pause();
    ref.notifyListeners();
  }

  /// Stop playback
  Future<void> stop() async {
    await _audioService.stop();
    ref.notifyListeners();
  }

  /// Seek to a specific position
  Future<void> seek(Duration position) async {
    await _audioService.seek(position);
    ref.notifyListeners();
  }

  /// Set playback speed
  Future<void> setSpeed(double speed) async {
    await _audioService.setSpeed(speed);
    ref.notifyListeners();
  }

  /// Set volume
  Future<void> setVolume(double volume) async {
    await _audioService.setVolume(volume);
    ref.notifyListeners();
  }

  /// Handle playback completion
  void _onPlaybackCompleted() {
    // Log playback complete
    final storyId = state.currentParable?.storyId;
    final durationMs = _audioService.duration?.inMilliseconds;

    logEvent('audio_play_complete', {
      'story_id': storyId,
      'duration_ms': durationMs,
    });

    // Playback completed, app can show sharing options or return to menu
    ref.notifyListeners();
  }

  /// Clear current parable and reset player
  Future<void> clear() async {
    await _audioService.stop();
    state = state.clearParable();
  }
}

/// Parable Player Provider
final parablePlayerProvider =
    NotifierProvider<ParablePlayerNotifier, ParablePlayerState>(
  ParablePlayerNotifier.new,
);
