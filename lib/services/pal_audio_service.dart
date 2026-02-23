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
// Name-prefix clips (generated via proxy TTS) can be stitched before greetings.
class PalAudioService {
  final Random _random;
  final AudioPlayer _player;

  // Loaded line pools (lazy-init)
  List<PalLine> _greetings = [];
  List<PalLine> _preview = [];
  Map<String, List<PalLine>> _replies = {};

  // Ring buffers to avoid repeats (last 5 per category)
  static const int _ringSize = 5;
  final List<String> _recentGreetings = [];
  final Map<String, List<String>> _recentReplies = {
    'positive': [],
    'neutral': [],
    'negative': [],
  };

  // Last selected lines (for UI text display)
  PalLine? _lastGreeting;
  PalLine? _lastReply;

  // Lazy init
  Completer<void>? _initCompleter;

  // Playback lock — prevents overlapping audio
  Completer<void>? _playbackLock;

  PalAudioService({Random? random, AudioPlayer? player})
      : _random = random ?? Random(),
        _player = player ?? AudioPlayer();

  /// Ensure pal_lines.json is loaded. Safe to call multiple times.
  Future<void> _ensureInit() async {
    if (_greetings.isNotEmpty) return; // Already loaded

    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }

    _initCompleter = Completer<void>();
    try {
      final jsonStr =
          await rootBundle.loadString('assets/pal/pal_lines.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      _greetings = _parseLines(data['greetings'] as List<dynamic>);
      _preview = _parseLines(data['preview'] as List<dynamic>);

      final repliesData =
          data['compassionateReplies'] as Map<String, dynamic>;
      _replies = {
        'positive': _parseLines(repliesData['positive'] as List<dynamic>),
        'neutral': _parseLines(repliesData['neutral'] as List<dynamic>),
        'negative': _parseLines(repliesData['negative'] as List<dynamic>),
      };

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

  /// Map the 5 detected moods to 3 PAL reply buckets.
  static String moodToBucket(String mood) {
    switch (mood) {
      case 'joyful':
        return 'positive';
      case 'weary':
      case 'anxious':
      case 'hurting':
        return 'negative';
      case 'neutral':
      default:
        return 'neutral';
    }
  }

  /// Build the deterministic asset path for a line + voice.
  static String assetPath(String voiceKey, String lineId) {
    return 'assets/pal/audio/$voiceKey/$lineId.mp3';
  }

  /// Pick a random line from a pool, avoiding recent IDs (ring buffer).
  PalLine _pickRandom(List<PalLine> pool, List<String> recentIds) {
    if (pool.isEmpty) {
      return const PalLine(id: 'fallback', text: '');
    }

    // Filter out recently used
    var candidates = pool.where((l) => !recentIds.contains(l.id)).toList();
    if (candidates.isEmpty) {
      // Ring exhausted — reset and use full pool
      recentIds.clear();
      candidates = pool;
    }

    final picked = candidates[_random.nextInt(candidates.length)];

    // Update ring buffer
    recentIds.add(picked.id);
    if (recentIds.length > _ringSize) {
      recentIds.removeAt(0);
    }

    return picked;
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

  /// Play a greeting in the selected voice. Returns the display text.
  ///
  /// If [nameClipFile] and [nameClipText] are provided, there's a 30% chance
  /// the name prefix clip is stitched before the greeting using
  /// ConcatenatingAudioSource for gapless playback.
  Future<String> playGreeting(
    String voiceKey, {
    File? nameClipFile,
    String? nameClipText,
  }) async {
    await _ensureInit();

    final line = _pickRandom(_greetings, _recentGreetings);
    _lastGreeting = line;

    final includeName = nameClipFile != null &&
        nameClipText != null &&
        await nameClipFile.exists() &&
        _random.nextDouble() < 0.30;

    await _acquireLock();
    try {
      if (includeName) {
        await _playWithNamePrefix(voiceKey, line.id, nameClipFile);
        return '$nameClipText ${line.text}';
      } else {
        await _playAsset(voiceKey, line.id);
        return line.text;
      }
    } finally {
      _releaseLock();
    }
  }

  /// Play a compassionate reply for the given mood bucket. Returns the display text.
  ///
  /// If [nameClipFile] and [nameClipText] are provided, there's a 20% chance
  /// the name prefix clip is stitched before the reply.
  Future<String> playCompassionateReply(
    String moodBucket,
    String voiceKey, {
    File? nameClipFile,
    String? nameClipText,
  }) async {
    await _ensureInit();

    final pool = _replies[moodBucket] ?? _replies['neutral']!;
    final recentIds = _recentReplies[moodBucket] ?? [];
    final line = _pickRandom(pool, recentIds);
    _lastReply = line;

    final includeName = nameClipFile != null &&
        nameClipText != null &&
        await nameClipFile.exists() &&
        _random.nextDouble() < 0.20;

    await _acquireLock();
    try {
      if (includeName) {
        await _playWithNamePrefix(voiceKey, line.id, nameClipFile);
        return '$nameClipText ${line.text}';
      } else {
        await _playAsset(voiceKey, line.id);
        return line.text;
      }
    } finally {
      _releaseLock();
    }
  }

  /// Stitch a name-prefix clip (local file) + greeting/reply asset into one
  /// gapless sequence using ConcatenatingAudioSource.
  Future<void> _playWithNamePrefix(
    String voiceKey,
    String lineId,
    File nameClipFile,
  ) async {
    final greetingPath = assetPath(voiceKey, lineId);
    try {
      final playlist = ConcatenatingAudioSource(children: [
        AudioSource.file(nameClipFile.path),
        AudioSource.asset(greetingPath),
      ]);
      await _player.setAudioSource(playlist);
      await _player.play();
    } catch (e) {
      debugPrint('[PalAudioService] Name prefix playback failed: $e');
      // Fallback: play greeting only
      await _playAsset(voiceKey, lineId);
    }
  }

  /// Play the preview line (for Settings voice preview).
  Future<void> playPreview(String voiceKey) async {
    await _ensureInit();

    final line = _preview.isNotEmpty
        ? _preview.first
        : const PalLine(id: 'preview_01', text: '');

    await _playAsset(voiceKey, line.id);
  }

  /// Get the text of the last played greeting.
  String? getLastGreetingText() => _lastGreeting?.text;

  /// Get the text of the last played reply.
  String? getLastReplyText() => _lastReply?.text;

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

  /// Stop any currently playing audio.
  Future<void> stop() async {
    await _player.stop();
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await _player.dispose();
  }
}
