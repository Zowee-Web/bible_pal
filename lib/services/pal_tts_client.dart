import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/app_logger.dart';
import '../core/pal_voice_registry.dart';

/// HTTP client for Bible PAL TTS.
///
/// Primary path: forwards {voiceKey, text} to the proxy server which maps
/// voiceKey → ElevenLabs voice ID. No API keys or voice IDs in the app.
///
/// Direct path: if [elevenLabsApiKey] is provided and the configured server URL
/// is localhost (unreachable on a real device), calls ElevenLabs directly.
///
/// Server URL is configured via --dart-define=PAL_TTS_SERVER_URL.
class PalTtsClient {
  final http.Client _client;
  final String _baseUrl;
  final String? _elevenLabsApiKey;

  static const _timeout = Duration(seconds: 15);
  static const _elevenLabsBaseUrl = 'https://api.elevenlabs.io/v1';

  PalTtsClient({http.Client? client, String? baseUrl, String? elevenLabsApiKey})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ??
            const String.fromEnvironment('PAL_TTS_SERVER_URL',
                defaultValue: 'http://localhost:8080'),
        _elevenLabsApiKey = elevenLabsApiKey;

  bool get _isLocalhost =>
      _baseUrl.contains('localhost') || _baseUrl.contains('127.0.0.1');

  /// Generate a short name-prefix TTS clip.
  ///
  /// Uses direct ElevenLabs when an API key is available and the proxy URL is
  /// localhost (not reachable on a real device). Otherwise uses the proxy.
  ///
  /// Returns MP3 bytes on success, or null on any failure.
  /// Never throws — all errors are logged and return null.
  Future<Uint8List?> synthesizeNamePrefix({
    required String voiceKey,
    required String text,
  }) async {
    if (_elevenLabsApiKey != null && _isLocalhost) {
      return _synthesizeDirect(voiceKey: voiceKey, text: text);
    }
    return _synthesizeViaProxy(voiceKey: voiceKey, text: text);
  }

  Future<Uint8List?> _synthesizeViaProxy({
    required String voiceKey,
    required String text,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/tts/name-prefix');
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'voice': voiceKey, 'text': text}),
          )
          .timeout(_timeout);

      if (response.statusCode == 200 &&
          response.headers['content-type']?.contains('audio/mpeg') == true) {
        return response.bodyBytes;
      }

      debugPrint(
          '[PalTtsClient] Server error ${response.statusCode}: ${response.body}');
      logEvent('name_tts_error', {
        'status': response.statusCode,
        'voiceKey': voiceKey,
      }, level: LogLevel.warn);
      return null;
    } catch (e) {
      debugPrint('[PalTtsClient] Proxy request failed: $e');
      logEvent('name_tts_error', {
        'error': e.runtimeType.toString(),
        'voiceKey': voiceKey,
      }, level: LogLevel.warn);
      return null;
    }
  }

  Future<Uint8List?> _synthesizeDirect({
    required String voiceKey,
    required String text,
  }) async {
    try {
      final voice = PalVoiceRegistry.getVoice(voiceKey);
      final voiceId = voice.elevenLabsId;
      final uri = Uri.parse('$_elevenLabsBaseUrl/text-to-speech/$voiceId');

      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'xi-api-key': _elevenLabsApiKey!,
              'Accept': 'audio/mpeg',
            },
            body: jsonEncode({
              'text': text,
              'model_id': 'eleven_turbo_v2',
              'voice_settings': {
                'stability': 0.5,
                'similarity_boost': 0.75,
              },
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }

      debugPrint(
          '[PalTtsClient] ElevenLabs error ${response.statusCode}: ${response.body}');
      logEvent('name_tts_error', {
        'status': response.statusCode,
        'voiceKey': voiceKey,
        'path': 'direct',
      }, level: LogLevel.warn);
      return null;
    } catch (e) {
      debugPrint('[PalTtsClient] Direct ElevenLabs request failed: $e');
      logEvent('name_tts_error', {
        'error': e.runtimeType.toString(),
        'voiceKey': voiceKey,
        'path': 'direct',
      }, level: LogLevel.warn);
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}
