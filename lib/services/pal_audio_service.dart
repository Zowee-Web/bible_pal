import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../core/app_logger.dart';
import '../core/pal_voice_registry.dart';

// Simple data class for a PAL line (id + text).
class PalLine {
  final String id;
  final String text;
  const PalLine({required this.id, required this.text});
}

/// Outcome of a single resolved PAL line playback.
///
/// Used by the opening greeting flow (Feature 2.0) to emit the
/// `pal_opening_audio_resolution` telemetry event. [source] mirrors the
/// values listed in that event spec: `asset` (selected voice's asset
/// played), `fallback` (selected voice failed, default voice's asset
/// played), or `missing` (neither could be loaded — caller falls back
/// to the SPEC text-only floor).
class PalAudioResolution {
  final String source;
  final bool played;
  final String? errorType;
  // Rich PlayerException fields — populated only when the failure is
  // a `PlayerException` (just_audio). Used by the opening-flow
  // diagnostics to distinguish "asset truly missing" from "iOS
  // session refused the operation" (e.g. code -11849 "Operation
  // Stopped"). Diagnostic only — no playback path reads them.
  final int? errorCode;
  final String? errorMessage;
  final int? errorIndex;
  final String? errorString;

  const PalAudioResolution._({
    required this.source,
    required this.played,
    this.errorType,
    this.errorCode,
    this.errorMessage,
    this.errorIndex,
    this.errorString,
  });
}

/// Extract diagnostic-only fields from any thrown audio-load error.
/// Recognises just_audio's [PlayerException] and
/// [PlayerInterruptedException]; falls back to runtime type + toString
/// for anything else. Always safe — no exception escapes.
Map<String, Object?> _extractAudioErrorFields(Object e) {
  if (e is PlayerException) {
    return {
      'exception_type': 'PlayerException',
      'exception_string': e.toString(),
      'error_code': e.code,
      'error_message': e.message,
      'error_index': e.details['index'],
    };
  }
  if (e is PlayerInterruptedException) {
    return {
      'exception_type': 'PlayerInterruptedException',
      'exception_string': e.toString(),
      'error_message': e.message,
    };
  }
  return {
    'exception_type': e.runtimeType.toString(),
    'exception_string': e.toString(),
  };
}

// Offline PAL audio playback service.
// Loads curated lines from pal_lines.json and plays pre-rendered MP3 assets.
// Name-prefix clips (generated via proxy TTS) can be stitched before prompts.
class PalAudioService {
  final Random _random;
  // Mutable so `recoverFromOperationStopped()` can dispose and
  // replace the AVPlayer underneath when iOS PlayerException -11849
  // leaves the current player wedged for subsequent setAsset calls.
  AudioPlayer _player;
  // Tracks whether `ensureAudioSessionActive()` has run a full
  // configure + setActive + settle cycle. Subsequent calls only
  // re-confirm setActive(true).
  bool _sessionActive = false;

  // Loaded line pools (lazy-init)
  Map<String, List<PalLine>> _prompts = {};
  Map<String, List<PalLine>> _microResponses = {};

  // Last selected lines (for UI text display)
  PalLine? _lastPrompt;
  PalLine? _lastMicroResponse;

  // Lazy init
  Completer<void>? _initCompleter;

  // Playback lock — prevents overlapping audio
  Completer<void>? _playbackLock;

  // Name prefix allowlist for micro-responses (only these IDs may get a name prefix)
  static const Set<String> _nameAllowedMicroResponses = {
    'RESP_NEU_02',
    'RESP_NEU_04',
    'RESP_WEARY_06',
    'RESP_ANX_04',
    'RESP_JOY_06',
  };

  // Phrases that must never get a name prefix
  static const List<String> _nameBlockedPhrases = [
    'God sees you',
    "You're not alone",
  ];

  PalAudioService({Random? random, AudioPlayer? player})
      : _random = random ?? Random(),
        _player = player ?? AudioPlayer();

  /// Ensure pal_lines.json is loaded. Safe to call multiple times.
  Future<void> _ensureInit() async {
    if (_prompts.isNotEmpty) return; // Already loaded

    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }

    _initCompleter = Completer<void>();
    try {
      final jsonStr =
          await rootBundle.loadString('assets/pal/pal_lines.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Load prompts (16 buckets)
      final promptsData = data['prompts'] as Map<String, dynamic>;
      _prompts = {};
      for (final entry in promptsData.entries) {
        _prompts[entry.key] =
            _parseLines(entry.value as List<dynamic>);
      }

      // Load micro-responses (5 mood buckets)
      final microData = data['microResponses'] as Map<String, dynamic>;
      _microResponses = {};
      for (final entry in microData.entries) {
        _microResponses[entry.key] =
            _parseLines(entry.value as List<dynamic>);
      }

      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      debugPrint('[PalAudioService] Failed to load pal_lines.json: $e');
    }
  }

  List<PalLine> _parseLines(List<dynamic> items) {
    return items
        .map((item) => PalLine(
              id: item['id'] as String,
              text: item['text'] as String,
            ))
        .toList();
  }

  /// Build the deterministic asset path for a line + voice.
  static String assetPath(String voiceKey, String lineId) {
    return 'assets/pal/audio/$voiceKey/$lineId.mp3';
  }

  /// Acquire the playback lock. Waits if another playback is in progress.
  Future<void> _acquireLock() async {
    while (_playbackLock != null) {
      await _playbackLock!.future;
    }
    _playbackLock = Completer<void>();
  }

  /// Release the playback lock.
  void _releaseLock() {
    _playbackLock?.complete();
    _playbackLock = null;
  }

  /// Play a specific prompt line. Returns display text.
  /// Name prefix splicing: 30% probability (unchanged from greetings).
  Future<String> playPrompt(
    String lineId,
    String voiceKey, {
    File? nameClipFile,
    String? nameClipText,
  }) async {
    await _ensureInit();

    // Find the line text from loaded data
    final lineText = _findLineText(lineId, _prompts);
    _lastPrompt = PalLine(id: lineId, text: lineText);

    final clipFile = nameClipFile;
    final includeName = clipFile != null &&
        nameClipText != null &&
        await clipFile.exists() &&
        _random.nextDouble() < 0.70;

    await _acquireLock();
    try {
      if (includeName) {
        await _playWithNamePrefix(voiceKey, lineId, clipFile);
        return '$nameClipText $lineText';
      } else {
        await _playAsset(voiceKey, lineId);
        return lineText;
      }
    } finally {
      _releaseLock();
    }
  }

  /// Play a specific micro-response line. Returns display text.
  /// Name prefix splicing: beta-calibrated with allowlist.
  Future<String> playMicroResponse(
    String lineId,
    String mood,
    String voiceKey, {
    File? nameClipFile,
    String? nameClipText,
    String? timeWindow,
  }) async {
    await _ensureInit();

    // Find the line text from loaded data
    final lineText = _findLineText(lineId, _microResponses);
    _lastMicroResponse = PalLine(id: lineId, text: lineText);

    // Check allowlist first, then apply probability
    final isAllowed = _isNamePrefixAllowed(lineId, lineText);
    final probability = (timeWindow == 'lateNight') ? 0.30 : 0.40;

    final clipFile = nameClipFile;
    final includeName = isAllowed &&
        clipFile != null &&
        nameClipText != null &&
        await clipFile.exists() &&
        _random.nextDouble() < probability;

    await _acquireLock();
    try {
      if (includeName) {
        await _playWithNamePrefix(voiceKey, lineId, clipFile);
        return '$nameClipText $lineText';
      } else {
        await _playAsset(voiceKey, lineId);
        return lineText;
      }
    } finally {
      _releaseLock();
    }
  }

  /// Check if a micro-response line is allowed to have a name prefix.
  bool _isNamePrefixAllowed(String lineId, String lineText) {
    // Never apply to any RESP_HURT_*
    if (lineId.startsWith('RESP_HURT_')) return false;

    // Never apply if text contains blocked phrases
    for (final phrase in _nameBlockedPhrases) {
      if (lineText.contains(phrase)) return false;
    }

    // Only apply to explicitly allowed IDs
    return _nameAllowedMicroResponses.contains(lineId);
  }

  /// Find line text by ID across all buckets in a map.
  String _findLineText(
      String lineId, Map<String, List<PalLine>> lineMap) {
    for (final pool in lineMap.values) {
      for (final line in pool) {
        if (line.id == lineId) return line.text;
      }
    }
    return '';
  }

  /// Stitch a name-prefix clip (local file) + prompt/response asset into one
  /// gapless sequence using ConcatenatingAudioSource.
  Future<void> _playWithNamePrefix(
    String voiceKey,
    String lineId,
    File nameClipFile,
  ) async {
    final path = assetPath(voiceKey, lineId);
    try {
      final playlist = ConcatenatingAudioSource(children: [
        AudioSource.file(nameClipFile.path),
        AudioSource.asset(path),
      ]);
      await _player.setAudioSource(playlist);
      await _waitForPlayerReady();
      await _player.play();
    } catch (e) {
      debugPrint('[PalAudioService] Name prefix playback failed: $e');
      // Fallback: play line only
      await _playAsset(voiceKey, lineId);
    }
  }

  /// Preview line ID used for Settings voice preview.
  /// Uses a new PAL opening line instead of the legacy preview_01 asset.
  static const String previewLineId = 'OPENING_GENTLE_01';

  /// Play the preview line (for Settings voice preview).
  Future<void> playPreview(String voiceKey) async {
    await _playAsset(voiceKey, previewLineId);
  }

  /// Get the text of the last played prompt.
  String? getLastPromptText() => _lastPrompt?.text;

  /// Get the text of the last played micro-response.
  String? getLastMicroResponseText() => _lastMicroResponse?.text;

  /// Play an asset with fallback chain: selected voice → default voice → silent.
  Future<void> _playAsset(String voiceKey, String lineId) async {
    final path = assetPath(voiceKey, lineId);
    try {
      await _player.setAsset(path);
      await _waitForPlayerReady();
      await _player.play();
    } catch (e) {
      debugPrint('[PalAudioService] Asset not found: $path');
      // Fallback: try default voice
      if (voiceKey != PalVoiceRegistry.defaultVoiceKey) {
        final fallbackPath =
            assetPath(PalVoiceRegistry.defaultVoiceKey, lineId);
        try {
          await _player.setAsset(fallbackPath);
          await _waitForPlayerReady();
          await _player.play();
        } catch (e2) {
          debugPrint('[PalAudioService] Fallback also missing: $fallbackPath');
          // Text-only fallback — no crash
        }
      }
    }
  }

  /// Play a single PAL line and report how it resolved.
  ///
  /// Used by the opening greeting flow (Feature 2.0) so the caller can
  /// emit the `pal_opening_audio_resolution` telemetry event. Same
  /// fallback chain as [playLine] with one addition: when [voiceKey]
  /// is the default voice and the first `setAsset` fails, a brief
  /// 200ms delay precedes a same-asset retry. Without this, the
  /// default voice (Ruth) gets only one `setAsset` attempt while
  /// non-default voices get two (their cross-voice fallback to the
  /// default voice). The asymmetry caused the default voice to drop
  /// the very-first-after-launch opening greeting whenever the iOS
  /// audio session was still warming up (PlayerException -11849
  /// "Operation Stopped").
  ///
  /// Never throws — the failure surfaces as a `missing` resolution.
  /// Wait until the player's processingState reaches `ready`, with a
  /// 2-second timeout. After [AudioPlayer.setAsset] returns, the
  /// platform decoder may still be preparing the asset for playback;
  /// calling [AudioPlayer.play] before this ready transition is what
  /// triggered the intermittent silent-greeting bug on iOS. Throws
  /// [TimeoutException] if the player gets stuck — caller's existing
  /// failure path handles that uniformly with any other throw.
  Future<void> _waitForPlayerReady() async {
    await _player.processingStateStream
        .firstWhere((s) => s == ProcessingState.ready)
        .timeout(const Duration(seconds: 2));
  }

  /// Recover the PAL audio stack after a fatal PlayerException -11849
  /// ("Operation Stopped") on iOS. The previous AVPlayer instance
  /// stays wedged — every subsequent `setAsset` on it returns the
  /// same -11849 — so the only reliable cleanup is to dispose it,
  /// stand up a fresh `AudioPlayer`, and force the audio session
  /// through a `setActive(false)` → `setActive(true)` cycle. Caller
  /// must hold the conversation reentrancy guard for the entire
  /// duration of this method so a new tap can't enter while the
  /// session is mid-cycle.
  ///
  /// Total wall-time: ~950ms (200ms between deactivate/reactivate
  /// + 750ms settle).
  Future<void> recoverFromOperationStopped() async {
    final stopwatch = Stopwatch()..start();
    var success = false;
    try {
      // Stop and dispose the wedged player.
      try {
        await _player.stop();
      } catch (_) {/*ignore*/}
      final old = _player;
      _player = AudioPlayer();
      unawaited(old.dispose().catchError((Object _) {}));

      // Deactivate → reactivate audio session.
      try {
        final session = await AudioSession.instance;
        await session.setActive(false);
        await Future.delayed(const Duration(milliseconds: 200));
        await session.setActive(true);
        _sessionActive = true;
      } catch (e) {
        debugPrint('[PalAudioService] Session reactivate failed: $e');
      }

      // Settle delay — gives iOS time to fully reactivate before
      // any subsequent setAsset attempt.
      await Future.delayed(const Duration(milliseconds: 750));
      success = true;
    } catch (e) {
      debugPrint('[PalAudioService] Recovery failed: $e');
    } finally {
      logEvent('pal_audio_recovery_complete', {
        'elapsed_ms': stopwatch.elapsedMilliseconds,
        'success': success,
      });
    }
  }

  /// Configure and activate the iOS audio session, then wait for it
  /// to settle. Idempotent — first call configures + activates +
  /// waits 300ms; subsequent calls just re-confirm `setActive(true)`
  /// without the configure or settle delay. Called before any PAL
  /// audio playback so AVFoundation has a fully active session
  /// before `setAsset`/`play` runs (rather than racing the lazy
  /// activation that produced PlayerException -11849).
  Future<void> ensureAudioSessionActive() async {
    final stopwatch = Stopwatch()..start();
    final wasActive = _sessionActive;
    var success = false;
    try {
      final session = await AudioSession.instance;
      if (!wasActive) {
        await session.configure(const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.mixWithOthers,
        ));
      }
      await session.setActive(true);
      if (!wasActive) {
        // iOS settle delay — tested-needed on cold launch so the
        // first setAsset doesn't race the activation transition.
        await Future.delayed(const Duration(milliseconds: 300));
      }
      _sessionActive = true;
      success = true;
    } catch (e) {
      debugPrint('[PalAudioService] Audio session activation failed: $e');
    } finally {
      logEvent('pal_audio_session_activated', {
        'elapsed_ms': stopwatch.elapsedMilliseconds,
        'success': success,
        'first_call': !wasActive,
      });
    }
  }

  Future<PalAudioResolution> playLineResolved(
    String lineId,
    String voiceKey,
  ) async {
    await _acquireLock();
    try {
      // Pre-playback reset — defends against a player left in a
      // half-stopped state by a prior failure (e.g. -11849 mid-flow).
      // Suppressed: stop() on an idle player is a no-op; if it does
      // throw, it doesn't affect the upcoming setAsset.
      try {
        await _player.stop();
      } catch (_) {/* ignore */}

      final path = assetPath(voiceKey, lineId);
      try {
        await _player.setAsset(path);
        await _waitForPlayerReady();
        await _player.play();
        return const PalAudioResolution._(source: 'asset', played: true);
      } catch (e) {
        // Diagnostic only — log the rich PlayerException fields for
        // the first attempt. Caller doesn't see this exception
        // (we retry internally), so this is the only place to capture
        // its details.
        final fields1 = _extractAudioErrorFields(e);
        logEvent('pal_audio_player_exception', {
          'attempt': 1,
          'voice_key': voiceKey,
          'line_id': lineId,
          'attempted_path': path,
          ...fields1,
        });
        debugPrint('[PalAudioService] Asset load failed: $path — $e');

        await Future.delayed(const Duration(milliseconds: 200));
        final isDefault = voiceKey == PalVoiceRegistry.defaultVoiceKey;
        final secondaryPath = isDefault
            ? path
            : assetPath(PalVoiceRegistry.defaultVoiceKey, lineId);
        try {
          await _player.setAsset(secondaryPath);
          await _waitForPlayerReady();
          await _player.play();
          return PalAudioResolution._(
            source: isDefault ? 'asset' : 'fallback',
            played: true,
          );
        } catch (e2) {
          // Diagnostic only — log the second attempt's rich fields
          // and surface them on the resolution so the call site can
          // include them in pal_opening_diag_play_returned /
          // pal_opening_audio_resolution events.
          final fields2 = _extractAudioErrorFields(e2);
          logEvent('pal_audio_player_exception', {
            'attempt': 2,
            'voice_key': voiceKey,
            'line_id': lineId,
            'attempted_path': secondaryPath,
            ...fields2,
          });
          debugPrint(
              '[PalAudioService] Secondary attempt failed: $secondaryPath — $e2');
          return _resolutionFromFailure(e2);
        }
      }
    } finally {
      _releaseLock();
    }
  }

  /// Build the failure resolution. Distinguishes the iOS -11849
  /// ("Operation Stopped") AVFoundation refusal from a true
  /// asset-missing failure so telemetry doesn't conflate them.
  PalAudioResolution _resolutionFromFailure(Object e) {
    final isOperationStopped = e is PlayerException && e.code == -11849;
    return PalAudioResolution._(
      source: isOperationStopped ? 'operation_stopped' : 'missing',
      played: false,
      errorType:
          isOperationStopped ? 'operation_stopped' : e.runtimeType.toString(),
      errorCode: e is PlayerException ? e.code : null,
      errorMessage: e is PlayerException
          ? e.message
          : (e is PlayerInterruptedException ? e.message : null),
      errorIndex:
          e is PlayerException ? e.details['index'] as int? : null,
      errorString: e.toString(),
    );
  }

  /// Play a single PAL line by its asset ID.
  ///
  /// Used for opening lines, framing overlay lines, etc.
  /// Falls back silently to text-only if asset not found.
  /// Returns true if audio played, false if asset was missing.
  Future<bool> playLine(String lineId, String voiceKey) async {
    await _acquireLock();
    try {
      final path = assetPath(voiceKey, lineId);
      try {
        await _player.setAsset(path);
        await _waitForPlayerReady();
        await _player.play();
        return true;
      } catch (e) {
        debugPrint('[PalAudioService] Asset not found: $path');
        // Fallback: try default voice
        if (voiceKey != PalVoiceRegistry.defaultVoiceKey) {
          final fallbackPath =
              assetPath(PalVoiceRegistry.defaultVoiceKey, lineId);
          try {
            await _player.setAsset(fallbackPath);
            await _waitForPlayerReady();
            await _player.play();
            return true;
          } catch (e2) {
            debugPrint(
                '[PalAudioService] Fallback also missing: $fallbackPath');
          }
        }
        return false;
      }
    } finally {
      _releaseLock();
    }
  }

  /// Play a sequence of PAL lines with short pauses between them.
  ///
  /// Used for framing overlay: reflection → framing → transition.
  /// Caller can call [stop] to interrupt at any time; the sequence will
  /// exit cleanly when the current line finishes or is stopped.
  Future<void> playSequence(List<String> lineIds, String voiceKey) async {
    await _acquireLock();
    try {
      for (var i = 0; i < lineIds.length; i++) {
        final path = assetPath(voiceKey, lineIds[i]);
        try {
          await _player.setAsset(path);
          await _waitForPlayerReady();
          await _player.play();
        } catch (e) {
          debugPrint('[PalAudioService] Sequence asset missing: $path');
          continue; // Skip missing assets
        }
        // Wait for playback to complete or be stopped
        final completed = await _awaitPlaybackDone();
        if (!completed) return; // Stopped externally — exit sequence
        // Short pause between lines (not after last)
        if (i < lineIds.length - 1) {
          await Future.delayed(const Duration(milliseconds: 400));
        }
      }
    } finally {
      _releaseLock();
    }
  }

  /// Wait for current playback to complete or be stopped.
  /// Returns true if playback completed naturally, false if stopped.
  Future<bool> _awaitPlaybackDone() async {
    final state = await _player.playerStateStream.firstWhere(
      (s) =>
          s.processingState == ProcessingState.completed ||
          s.processingState == ProcessingState.idle,
    );
    return state.processingState == ProcessingState.completed;
  }

  /// Wait for current playback to complete.
  Future<void> awaitPlaybackComplete() async {
    await _player.playerStateStream.firstWhere(
      (state) => state.processingState == ProcessingState.completed,
    );
  }

  /// Stop any currently playing audio.
  Future<void> stop() async {
    await _player.stop();
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await _player.dispose();
  }
}
