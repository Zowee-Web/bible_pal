import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_logger.dart';
import 'pal_tts_client.dart';

/// Result of picking a random cached name clip.
class NameClipResult {
  final File file;
  final String text;
  const NameClipResult({required this.file, required this.text});
}

/// Service that generates and caches personalized name-greeting audio clips.
///
/// Generates 4 phrase variants via PalTtsClient (proxy server → ElevenLabs),
/// caches them locally keyed by voiceKey + sha256(lower(trim(name))).
///
/// All failures return null — name audio is enhancement-only, never blocks UI.
class NameAudioService {
  final PalTtsClient _ttsClient;
  final Random _random;

  static const _prefCachedNameKey = 'name_audio.cached_name_key';
  static const _prefCachedVoiceKey = 'name_audio.cached_voice_key';
  static const int _clipCount = 4;

  /// Phrase templates. {name} is replaced with the user's name.
  static const List<String> _phraseTemplates = [
    'Hey, {name}!',
    'Hi there, {name}!',
    '{name}, welcome back!',
    'Good to see you, {name}!',
  ];

  int? _lastPickedIndex;

  NameAudioService({required PalTtsClient ttsClient, Random? random})
      : _ttsClient = ttsClient,
        _random = random ?? Random();

  /// Compute a stable cache key from the user's name.
  static String nameKey(String name) {
    final normalized = name.trim().toLowerCase();
    return sha256.convert(utf8.encode(normalized)).toString().substring(0, 16);
  }

  /// Get the cache directory for a given voice + name.
  Future<Directory> _cacheDir(String voiceKey, String nKey) async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/name_audio/$voiceKey/$nKey');
  }

  /// Build the phrase text for a given index.
  static String phraseText(String name, int index) {
    return _phraseTemplates[index % _phraseTemplates.length]
        .replaceAll('{name}', name);
  }

  /// Check if cached clips are available and current for this name + voice.
  Future<bool> isAvailable(String name, String voiceKey) async {
    if (name.trim().isEmpty) return false;

    final nKey = nameKey(name);
    final sp = await SharedPreferences.getInstance();
    final cachedNKey = sp.getString(_prefCachedNameKey);
    final cachedVKey = sp.getString(_prefCachedVoiceKey);

    if (cachedNKey != nKey || cachedVKey != voiceKey) return false;

    final dir = await _cacheDir(voiceKey, nKey);
    if (!await dir.exists()) return false;

    // Check all 4 clips exist
    for (var i = 0; i < _clipCount; i++) {
      final file = File('${dir.path}/prefix_$i.mp3');
      if (!await file.exists()) return false;
    }
    return true;
  }

  /// Get a random cached name clip. Returns null if not available.
  Future<NameClipResult?> getRandomNameClip(
      String name, String voiceKey) async {
    if (name.trim().isEmpty) return null;

    final nKey = nameKey(name);
    final sp = await SharedPreferences.getInstance();
    final cachedNKey = sp.getString(_prefCachedNameKey);
    final cachedVKey = sp.getString(_prefCachedVoiceKey);

    if (cachedNKey != nKey || cachedVKey != voiceKey) return null;

    final dir = await _cacheDir(voiceKey, nKey);
    if (!await dir.exists()) return null;

    // Collect available clips
    final available = <int>[];
    for (var i = 0; i < _clipCount; i++) {
      final file = File('${dir.path}/prefix_$i.mp3');
      if (await file.exists() && (await file.length()) > 0) {
        available.add(i);
      }
    }

    if (available.isEmpty) return null;

    // Exclude the last played clip to avoid back-to-back repeats.
    final candidates = available.length > 1
        ? available.where((i) => i != _lastPickedIndex).toList()
        : available;
    final picked = candidates[_random.nextInt(candidates.length)];
    _lastPickedIndex = picked;
    return NameClipResult(
      file: File('${dir.path}/prefix_$picked.mp3'),
      text: phraseText(name.trim(), picked),
    );
  }

  /// Generate all 4 name-prefix clips via the proxy server and cache locally.
  ///
  /// Returns true if at least one clip was successfully generated.
  /// Fire-and-forget safe — never throws.
  Future<bool> generateNamePhrases({
    required String name,
    required String voiceKey,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return false;

    final nKey = nameKey(trimmedName);

    try {
      final dir = await _cacheDir(voiceKey, nKey);
      await dir.create(recursive: true);

      var successCount = 0;

      for (var i = 0; i < _clipCount; i++) {
        final text = phraseText(trimmedName, i);
        final bytes = await _ttsClient.synthesizeNamePrefix(
          voiceKey: voiceKey,
          text: text,
        );

        if (bytes != null && bytes.isNotEmpty) {
          final file = File('${dir.path}/prefix_$i.mp3');
          await file.writeAsBytes(bytes);
          successCount++;
        }
      }

      if (successCount > 0) {
        // Update cache metadata
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_prefCachedNameKey, nKey);
        await sp.setString(_prefCachedVoiceKey, voiceKey);

        logEvent('name_audio_generated', {
          'clips': successCount,
          'voiceKey': voiceKey,
        });
      }

      debugPrint(
          '[NameAudioService] Generated $successCount/$_clipCount clips for "$trimmedName"');
      return successCount > 0;
    } catch (e) {
      debugPrint('[NameAudioService] Generation failed: $e');
      logEvent('name_audio_error', {
        'error': e.runtimeType.toString(),
      }, level: LogLevel.warn);
      return false;
    }
  }

  /// Invalidate the cached name audio (e.g., on name or voice change).
  Future<void> invalidateCache() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cachedNKey = sp.getString(_prefCachedNameKey);
      final cachedVKey = sp.getString(_prefCachedVoiceKey);

      if (cachedNKey != null && cachedVKey != null) {
        final dir = await _cacheDir(cachedVKey, cachedNKey);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }

      await sp.remove(_prefCachedNameKey);
      await sp.remove(_prefCachedVoiceKey);

      debugPrint('[NameAudioService] Cache invalidated');
    } catch (e) {
      debugPrint('[NameAudioService] Cache invalidation failed: $e');
    }
  }
}
