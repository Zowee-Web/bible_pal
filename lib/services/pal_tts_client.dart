import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/app_logger.dart';

/// HTTP client for the Bible PAL TTS proxy server.
///
/// Sends {voiceKey, text} to the server which maps voiceKey → ElevenLabs
/// voice ID and forwards the request. No API keys or voice IDs in the app.
///
/// Server URL is configured via --dart-define=PAL_TTS_SERVER_URL.
class PalTtsClient {
  final http.Client _client;
  final String _baseUrl;

  static const _timeout = Duration(seconds: 15);

  PalTtsClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ??
            const String.fromEnvironment('PAL_TTS_SERVER_URL',
                defaultValue: 'http://localhost:8080');

  /// Generate a short name-prefix TTS clip via the proxy server.
  ///
  /// Returns MP3 bytes on success, or null on any failure.
  /// Never throws — all errors are logged and return null.
  Future<Uint8List?> synthesizeNamePrefix({
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
      debugPrint('[PalTtsClient] Request failed: $e');
      logEvent('name_tts_error', {
        'error': e.runtimeType.toString(),
        'voiceKey': voiceKey,
      }, level: LogLevel.warn);
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}
