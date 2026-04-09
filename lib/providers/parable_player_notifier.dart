import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/services/ambient_audio_service.dart';
import 'package:bible_pal/services/audio_service.dart';
import 'package:bible_pal/services/verse_service.dart';
import 'package:bible_pal/services/voice_consent_gate.dart';
import 'package:bible_pal/core/app_logger.dart';
import 'service_providers.dart';
import 'app_state_notifier.dart';

/// Result of attempting to play voice audio (story narration).
/// Callers MUST handle `needsConsent` by showing VoiceConsentDialog.
enum VoicePlayResult {
  /// Audio playback started successfully
  played,

  /// User has not yet been asked for voice consent (storyNarrationEnabled == null).
  /// Caller MUST show VoiceConsentDialog and retry play() after consent is given.
  needsConsent,

  /// User explicitly disabled story narration (storyNarrationEnabled == false).
  /// Audio will not play. Caller may show text-only fallback.
  disabled,

  /// No parable loaded to play
  noParable,

  /// Error occurred during playback
  error,
}

/// Parable Player State
class ParablePlayerState {
  final Parable? currentParable;
  final String? parableText;
  final bool isLoading;
  final String? errorMessage;
  final bool playbackCompleted;
  final String? palResponseText;
  final VerseResponse? verse;

  /// Android-only: progress of an in-flight R2 audio download in [0.0, 1.0].
  /// Null when no download is in progress (cache hit, bundled asset, or iOS).
  final double? downloadProgress;

  const ParablePlayerState({
    this.currentParable,
    this.parableText,
    this.isLoading = false,
    this.errorMessage,
    this.playbackCompleted = false,
    this.palResponseText,
    this.verse,
    this.downloadProgress,
  });

  ParablePlayerState copyWith({
    Parable? currentParable,
    String? parableText,
    bool? isLoading,
    String? errorMessage,
    bool? playbackCompleted,
    String? palResponseText,
    VerseResponse? verse,
    double? downloadProgress,
    bool clearDownloadProgress = false,
  }) {
    return ParablePlayerState(
      currentParable: currentParable ?? this.currentParable,
      parableText: parableText ?? this.parableText,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      playbackCompleted: playbackCompleted ?? this.playbackCompleted,
      palResponseText: palResponseText ?? this.palResponseText,
      verse: verse ?? this.verse,
      downloadProgress: clearDownloadProgress
          ? null
          : (downloadProgress ?? this.downloadProgress),
    );
  }

  ParablePlayerState clearParable() {
    return const ParablePlayerState();
  }
}

/// Parable Player Notifier - manages parable playback state
class ParablePlayerNotifier extends Notifier<ParablePlayerState> {
  late AudioService _audioService;
  late AmbientAudioService _ambientService;

  @override
  ParablePlayerState build() {
    // Get services
    _audioService = ref.watch(audioServiceProvider);
    _ambientService = ref.watch(ambientAudioServiceProvider);
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

    logEvent('story_load_start', {
      'story_id': parable.storyId,
      'length_bucket': parable.lengthBucket.name,
    });

    try {
      // Get ParableService
      final parableService = await ref.read(parableServiceProvider.future);

      // Load audio file. On Android, R2 downloads report progress to update
      // a download indicator in the UI. iOS uses bundled assets only and
      // never receives a progress callback (SPEC Feature 27).
      final audioFile = await parableService.getAudioFile(
        parable,
        onProgress: Platform.isAndroid
            ? (progress) {
                state = state.copyWith(downloadProgress: progress);
              }
            : null,
      );
      // Clear download progress regardless of how the audio was resolved.
      if (state.downloadProgress != null) {
        state = state.copyWith(clearDownloadProgress: true);
      }
      if (audioFile == null) {
        logEvent(
            'audio_asset_missing',
            {
              'story_id': parable.storyId,
              'expected_path': parable.audioFilePath,
            },
            level: LogLevel.error);

        throw Exception('Audio file not found for parable: ${parable.storyId}');
      }

      await _audioService.loadAudio(audioFile, storyId: parable.storyId);

      // Load text (optional, for scripture panel)
      final parableText = await parableService.getParableText(parable);

      // Content filtering check (SPEC Feature #24)
      if (parableText != null) {
        final appState = ref.read(appStateProvider).valueOrNull;
        if (appState?.userPreferences.contentFilteringEnabled == true) {
          final contentFilter = ref.read(contentFilterServiceProvider);
          final scanResult = await contentFilter.scanText(parableText);
          if (!scanResult.passed) {
            logEvent('content_filter_blocked', {
              'story_id': parable.storyId,
              'violations': scanResult.violations.length,
            }, level: LogLevel.warn);

            state = state.copyWith(
              isLoading: false,
              errorMessage:
                  'This story was blocked by the content filter. Please try another story.',
            );
            return;
          }
        }
      }

      state = ParablePlayerState(
        currentParable: parable,
        parableText: parableText,
        isLoading: false,
      );

      logEvent('story_load_success', {
        'story_id': parable.storyId,
        'length_bucket': parable.lengthBucket.name,
        'kid_friendly': parable.kidFriendly,
      });
    } catch (e) {
      logEvent('story_load_fail', {
        'story_id': parable.storyId,
        'error_type': e.runtimeType.toString(),
      }, level: LogLevel.error);

      logError('parable_load_failed', 'ParablePlayerNotifier.loadParable',
          storyId: parable.storyId, errorMessage: e.toString());

      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error loading parable: $e',
        clearDownloadProgress: true,
      );
      rethrow;
    }
  }

  /// Play the current parable (with voice consent check via VoiceConsentGate).
  ///
  /// Returns [VoicePlayResult] indicating what happened:
  /// - `played`: Audio started successfully
  /// - `needsConsent`: User hasn't been asked yet - caller MUST show VoiceConsentDialog
  /// - `disabled`: User declined narration - caller may show text-only fallback
  /// - `noParable`: No parable loaded
  /// - `error`: Playback error occurred
  ///
  /// Callers MUST handle `needsConsent` by showing VoiceConsentDialog,
  /// then calling play() again after user grants consent.
  Future<VoicePlayResult> play() async {
    if (state.currentParable == null) return VoicePlayResult.noParable;

    // Check voice consent via VoiceConsentGate (single source of truth)
    final appState = ref.read(appStateProvider);
    final userPrefs = appState.valueOrNull?.userPreferences;
    final gateResult = VoiceConsentGate.checkStoryNarration(userPrefs);

    switch (gateResult) {
      case VoiceGateResult.needsConsent:
        logEvent('voice_consent_needed', {
          'story_id': state.currentParable?.storyId,
          'trigger': 'play_button',
        });
        return VoicePlayResult.needsConsent;

      case VoiceGateResult.blocked:
        logEvent('voice_narration_disabled', {
          'story_id': state.currentParable?.storyId,
        });
        return VoicePlayResult.disabled;

      case VoiceGateResult.allowed:
        // Proceed with playback
        break;
    }

    try {
      await _audioService.play();
      await _ambientService.startIfEnabled();

      logEvent('audio_play_start', {
        'story_id': state.currentParable?.storyId,
      });

      state = state.copyWith(playbackCompleted: false);
      ref.notifyListeners();
      return VoicePlayResult.played;
    } catch (e) {
      logEvent('audio_play_fail', {
        'story_id': state.currentParable?.storyId,
        'error_type': e.runtimeType.toString(),
      }, level: LogLevel.error);

      state = state.copyWith(errorMessage: 'Error playing audio: $e');
      return VoicePlayResult.error;
    }
  }

  /// Pause playback
  Future<void> pause() async {
    await _audioService.pause();
    await _ambientService.forceStop();
    ref.notifyListeners();
  }

  /// Stop playback
  Future<void> stop() async {
    await _audioService.stop();
    await _ambientService.forceStop();
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
  Future<void> _onPlaybackCompleted() async {
    // Stop ambient audio — no ambient during reflection (v1)
    await _ambientService.forceStop();

    // Log playback complete
    final storyId = state.currentParable?.storyId;
    final durationMs = _audioService.duration?.inMilliseconds;

    logEvent('audio_play_complete', {
      'story_id': storyId,
      'duration_ms': durationMs,
    });

    state = state.copyWith(playbackCompleted: true);
    ref.notifyListeners();
  }

  /// Store PAL's response text and verse for display on the player screen.
  void setPalResponse(String? responseText, VerseResponse? verse) {
    state = state.copyWith(palResponseText: responseText, verse: verse);
  }

  /// Clear current parable and reset player
  Future<void> clear() async {
    await _audioService.stop();
    await _ambientService.forceStop();
    state = state.clearParable();
  }
}

/// Parable Player Provider
final parablePlayerProvider =
    NotifierProvider<ParablePlayerNotifier, ParablePlayerState>(
  ParablePlayerNotifier.new,
);
