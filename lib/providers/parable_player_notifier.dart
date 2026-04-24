import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/services/ambient_audio_service.dart';
import 'package:bible_pal/services/audio_service.dart';
import 'package:bible_pal/services/completed_stories_store.dart';
import 'package:bible_pal/services/parable_service.dart' show AudioResolveError;
import 'package:bible_pal/services/verse_service.dart';
import 'package:bible_pal/services/voice_consent_gate.dart';
import 'package:bible_pal/core/analytics_events.dart';
import 'package:bible_pal/core/app_logger.dart';
import 'package:bible_pal/features/paths/path_launch_context.dart';
import 'package:bible_pal/features/paths/path_type.dart';
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

  /// Whether the current error is retryable (e.g. offline or download failed).
  final bool canRetry;

  /// PALs Paths launch context (SPEC Feature 50.6 — LOCKED). Non-null when
  /// the player was opened from a path; null for mood, favorite, history,
  /// or standalone search launches. The canonical player uses this to
  /// decide whether to render "Next in Your Journey" — rendered only when
  /// this field is non-null. Path order is sacred: advancement does NOT
  /// skip completed stories.
  final PathLaunchContext? launchContext;

  const ParablePlayerState({
    this.currentParable,
    this.parableText,
    this.isLoading = false,
    this.errorMessage,
    this.playbackCompleted = false,
    this.palResponseText,
    this.verse,
    this.downloadProgress,
    this.canRetry = false,
    this.launchContext,
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
    bool? canRetry,
    PathLaunchContext? launchContext,
    bool clearLaunchContext = false,
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
      canRetry: canRetry ?? this.canRetry,
      launchContext: clearLaunchContext
          ? null
          : (launchContext ?? this.launchContext),
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

  /// True once the ≥ 90% completion hook has fired for the currently
  /// loaded story. Reset on every [loadParable] so the next story gets a
  /// fresh one-shot. Gates both `story_completed` telemetry and
  /// `CompletedStoriesStore.markCompleted()` (idempotency is also enforced
  /// inside the store, but this flag avoids the round-trip per tick).
  /// SPEC Feature 50.4 — LOCKED.
  bool _completionFiredForCurrentLoad = false;

  /// Subscription to the main audio position stream used to detect the
  /// story-body ≥ 90% completion threshold (SPEC Feature 50.4). Story body
  /// only — reflection audio plays through a separate AudioPlayer on the
  /// player screen and does NOT pass through [_audioService].
  StreamSubscription<Duration>? _completionPositionSub;

  /// Subscription to playerStateStream for UI-refresh notifications.
  StreamSubscription<dynamic>? _playerStateSub;

  /// Subscription to playbackCompletedStream for natural-end detection.
  StreamSubscription<dynamic>? _playbackCompletedSub;

  @override
  ParablePlayerState build() {
    // Get services
    _audioService = ref.watch(audioServiceProvider);
    _ambientService = ref.watch(ambientAudioServiceProvider);
    // ParableService is FutureProvider - we'll await it when needed in async methods

    // Listen to audio state changes
    _listenToAudioState();

    ref.onDispose(() {
      _completionPositionSub?.cancel();
      _playerStateSub?.cancel();
      _playbackCompletedSub?.cancel();
    });

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

  /// Listen to audio state changes.
  /// Subscriptions are stored so they can be cancelled in [ref.onDispose],
  /// preventing stale listeners if the notifier is ever torn down.
  void _listenToAudioState() {
    _playerStateSub = _audioService.playerStateStream.listen((_) {
      // Notify listeners when audio state changes so widgets watching
      // playback state (play/pause button icon, seek slider) rebuild.
      ref.notifyListeners();
    });

    _playbackCompletedSub = _audioService.playbackCompletedStream.listen((_) {
      _onPlaybackCompleted();
    });
  }

  /// Load and prepare a parable for playback.
  ///
  /// [launchContext] is optional and defaults to null. Non-null values are
  /// passed by PALs Paths launches (SPEC Feature 50.6) so the player can
  /// render "Next in Your Journey" and so `story_completed` telemetry
  /// records the launch source.
  ///
  /// Returns true if audio loaded successfully, false on error.
  Future<bool> loadParable(
    Parable parable, {
    PathLaunchContext? launchContext,
  }) async {
    // Reset the one-shot completion flag and tear down any stale
    // position listener from a previous load. Each loadParable() call
    // starts a fresh ≥ 90% completion window.
    _completionFiredForCurrentLoad = false;
    await _completionPositionSub?.cancel();
    _completionPositionSub = null;

    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      canRetry: false,
      launchContext: launchContext,
      clearLaunchContext: launchContext == null,
    );

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
        final reason = parableService.lastAudioError;
        logEvent(
            'audio_asset_missing',
            {
              'story_id': parable.storyId,
              'expected_path': parable.audioFilePath,
              'resolve_error': reason.name,
            },
            level: LogLevel.error);

        final (message, retryable) = switch (reason) {
          AudioResolveError.offlineNotCached => (
              'This story needs an internet connection the first time you play it.',
              true,
            ),
          AudioResolveError.downloadFailed => (
              "Couldn't download this story. Check your connection and try again.",
              true,
            ),
          AudioResolveError.remoteNotFound => (
              "This story isn't available right now. Try a different one.",
              false,
            ),
          AudioResolveError.none => (
              "Couldn't load this story right now.",
              true,
            ),
        };
        state = state.copyWith(
          isLoading: false,
          errorMessage: message,
          canRetry: retryable,
          clearDownloadProgress: true,
        );
        return false;
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
            return false;
          }
        }
      }

      state = ParablePlayerState(
        currentParable: parable,
        parableText: parableText,
        isLoading: false,
        launchContext: launchContext,
      );

      // Attach the ≥ 90% story-body completion listener for this load.
      // Story body only — reflection audio uses a separate AudioPlayer
      // instance on the player screen and is invisible to _audioService.
      // Write-once per load; idempotent with CompletedStoriesStore.
      _attachCompletionWatcher(parable, launchContext);

      logEvent('story_load_success', {
        'story_id': parable.storyId,
        'length_bucket': parable.lengthBucket.name,
        'kid_friendly': parable.kidFriendly,
      });
      return true;
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

  /// Swap the loaded story to a different variant (length or translation)
  /// without resetting display-only state (verse, palResponseText,
  /// launchContext). Used by the player-screen variant controls to avoid
  /// the layout jump that [loadParable]'s fresh-state construction causes.
  ///
  /// Stops current audio, loads the new variant's audio + text, then
  /// updates state via [copyWith]. Returns true on success.
  Future<bool> switchVariant(Parable newVariant) async {
    _completionFiredForCurrentLoad = false;
    await _completionPositionSub?.cancel();
    _completionPositionSub = null;

    // Stop current playback (caller captures wasPlaying beforehand).
    await _audioService.stop();
    await _ambientService.forceStop();

    try {
      final parableService = await ref.read(parableServiceProvider.future);

      final audioFile = await parableService.getAudioFile(
        newVariant,
        onProgress: Platform.isAndroid
            ? (progress) {
                state = state.copyWith(downloadProgress: progress);
              }
            : null,
      );
      if (state.downloadProgress != null) {
        state = state.copyWith(clearDownloadProgress: true);
      }
      if (audioFile == null) {
        return false;
      }

      await _audioService.loadAudio(audioFile, storyId: newVariant.storyId);
      final parableText = await parableService.getParableText(newVariant);

      // copyWith preserves verse, palResponseText, launchContext.
      state = state.copyWith(
        currentParable: newVariant,
        parableText: parableText,
        isLoading: false,
        playbackCompleted: false,
      );

      _attachCompletionWatcher(newVariant, state.launchContext);
      return true;
    } catch (e) {
      logError('variant_switch_failed', 'ParablePlayerNotifier.switchVariant',
          storyId: newVariant.storyId, errorMessage: e.toString());
      return false;
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

    // Natural playback-complete also counts as ≥ 90% for the purposes of
    // SPEC Feature 50.4 (story body only, reflection ignored). The
    // position-stream listener usually fires first, but on some codecs
    // position reporting can stop short of exact duration — catch that
    // here. Guarded by the one-shot flag, so this is a no-op if the
    // position listener already triggered completion.
    final parable = state.currentParable;
    if (parable != null) {
      await _maybeFireStoryCompleted(parable, state.launchContext);
    }

    state = state.copyWith(playbackCompleted: true);
    ref.notifyListeners();
  }

  /// Attach the ≥ 90% story-body completion watcher (SPEC Feature 50.4 —
  /// LOCKED). Samples the main audio position stream; fires once when
  /// `position / duration ≥ 0.90`. Write-once per load via
  /// [_completionFiredForCurrentLoad], and idempotent against
  /// [CompletedStoriesStore] as a second safety net.
  ///
  /// Reflection audio is orthogonal — it plays through a separate
  /// [AudioPlayer] instance owned by the player screen, not through
  /// [_audioService], so this listener samples story-body playback only.
  void _attachCompletionWatcher(
    Parable parable,
    PathLaunchContext? launchContext,
  ) {
    _completionPositionSub = _audioService.positionStream.listen((position) {
      if (_completionFiredForCurrentLoad) return;

      final duration = _audioService.duration;
      if (duration == null || duration.inMilliseconds <= 0) return;

      final ratio = position.inMilliseconds / duration.inMilliseconds;
      if (ratio >= 0.90) {
        // Fire-and-forget — never block audio thread on persistence.
        unawaited(_maybeFireStoryCompleted(parable, launchContext));
      }
    });
  }

  /// Idempotently mark a story completed and fire `story_completed`
  /// telemetry. Write-once per loadParable() call. Safe-fail — exceptions
  /// in persistence or telemetry MUST NEVER break the player.
  ///
  /// Phase 3 additions:
  /// 1. When `launchContext != null`, compute the `willCompletePath`
  ///    predicate BEFORE marking the current story completed. This
  ///    detects whether the current story is the last remaining
  ///    incomplete story in the active path (SPEC Feature 50.10,
  ///    strict transition semantics).
  /// 2. After `markCompleted`, invalidate `completedStoryIdsProvider`
  ///    so `pathServiceProvider` rebuilds with the fresh set and UI
  ///    completion markers update reactively.
  /// 3. If `willCompletePath` was true, fire `path_completed`
  ///    telemetry once.
  Future<void> _maybeFireStoryCompleted(
    Parable parable,
    PathLaunchContext? launchContext,
  ) async {
    if (_completionFiredForCurrentLoad) return;
    _completionFiredForCurrentLoad = true;

    // Phase 3: compute path-completion transition BEFORE markCompleted.
    // This lets us detect "path was at <1.0 and will now be at 1.0"
    // without needing persistent path-progress state. Safe-fail —
    // telemetry detection is non-critical and must not block
    // persistence or the fire of story_completed.
    bool willCompletePath = false;
    if (launchContext != null) {
      try {
        final pathService = await ref.read(pathServiceProvider.future);
        final stories = pathService.getPathStories(
          launchContext.pathType,
          launchContext.pathId,
        );
        final inThisPath =
            stories.any((s) => s.storyId == parable.storyId);
        final currentlyIncomplete =
            !pathService.isStoryCompleted(parable.storyId);
        final otherIncompleteCount = stories
            .where((s) =>
                s.storyId != parable.storyId &&
                !pathService.isStoryCompleted(s.storyId))
            .length;
        willCompletePath =
            inThisPath && currentlyIncomplete && otherIncompleteCount == 0;
      } catch (e) {
        // Detection failure is non-fatal — log and continue.
        logEvent('path_completion_detect_fail', {
          'story_id': parable.storyId,
          'path_type': launchContext.pathType.wireId,
          'path_id': launchContext.pathId,
          'error_type': e.runtimeType.toString(),
        }, level: LogLevel.warn);
      }
    }

    try {
      final store = await ref.read(completedStoriesStoreProvider.future);
      await store.markCompleted(parable.storyId);
      // Phase 3: invalidate the reactive snapshot so pathServiceProvider
      // rebuilds with the fresh set. UI widgets reading completion
      // state re-render on the next frame.
      ref.invalidate(completedStoryIdsProvider);
    } catch (e) {
      // Persistence failure is non-fatal — log and continue.
      logEvent('completion_persist_fail', {
        'story_id': parable.storyId,
        'error_type': e.runtimeType.toString(),
      }, level: LogLevel.warn);
    }

    // SPEC Feature 50.10: `source` enum is one of
    // mood | path | favorite | history | search. Phase 1 infers two
    // values: `path` when launched from PALs Paths (launchContext
    // present), `mood` otherwise. Later phases can widen the inference
    // as additional entry points explicitly declare themselves.
    final source = launchContext != null ? 'path' : 'mood';
    AnalyticsEvents.logStoryCompleted(parable, source: source);

    // Phase 3: fire path_completed telemetry on the <1.0 → 1.0
    // transition detected above. Strict: fires only when the active
    // launch context belongs to the path that just transitioned.
    if (willCompletePath && launchContext != null) {
      AnalyticsEvents.logPathCompleted(
        pathType: launchContext.pathType.wireId,
        pathId: launchContext.pathId,
        completionPct: 1.0,
      );
    }
  }

  /// Store PAL's response text and verse for display on the player screen.
  void setPalResponse(String? responseText, VerseResponse? verse) {
    state = state.copyWith(palResponseText: responseText, verse: verse);
  }

  /// Clear current parable and reset player.
  ///
  /// State is wiped *synchronously* on the first line so callers (like
  /// the player screen's back handler) can observe the cleared state
  /// before the next frame paints — without that, the main menu's
  /// `_ReservedPanel` would still see `currentParable != null` while the
  /// back animation runs and only switch to its idle layout afterward,
  /// producing a visible mid-animation height shift. Audio stops are
  /// awaited after the state change since they don't affect visible
  /// layout.
  Future<void> clear() async {
    state = state.clearParable();
    await _audioService.stop();
    await _ambientService.forceStop();
  }
}

/// Parable Player Provider
final parablePlayerProvider =
    NotifierProvider<ParablePlayerNotifier, ParablePlayerState>(
  ParablePlayerNotifier.new,
);
