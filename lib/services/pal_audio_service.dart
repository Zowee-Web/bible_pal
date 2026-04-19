import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../core/pal_voice_registry.dart';

// Simple data class for a PAL line (id + text).
class PalLine {
  final String id;
  final String text;
  const PalLine({required this.id, required this.text});
}

// Offline PAL audio playback service.
// Loads curated lines from pal_lines.json and plays pre-rendered MP3 assets.
// Name-prefix clips (generated via proxy TTS) can be stitched before prompts.
class PalAudioService {
  final Random _random;
  final AudioPlayer _player;

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
      await _player.play();
    } catch (e) {
      debugPrint('[PalAudioService] Asset not found: $path');
      // Fallback: try default voice
      if (voiceKey != PalVoiceRegistry.defaultVoiceKey) {
        final fallbackPath =
            assetPath(PalVoiceRegistry.defaultVoiceKey, lineId);
        try {
          await _player.setAsset(fallbackPath);
          await _player.play();
        } catch (e2) {
          debugPrint('[PalAudioService] Fallback also missing: $fallbackPath');
          // Text-only fallback — no crash
        }
      }
    }
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
