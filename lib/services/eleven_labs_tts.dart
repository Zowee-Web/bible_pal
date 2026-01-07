import 'dart:convert';

import 'package:flutter/foundation.dart';

/// ElevenLabs TTS Service - INTENTIONALLY UNUSED IN PRODUCTION
///
/// Per SPEC.md #17: "Pre-generated audio files (not live streaming TTS)"
/// Audio for parables is generated via server scripts (server/*.sh), not at runtime.
/// The Flutter app only plays pre-generated MP3 files via AudioService.
///
/// This class is reserved for potential future use:
/// - Dev-only voice preview tooling
/// - Admin features (behind feature flag)
///
/// DO NOT wire this into production code paths without a SPEC update.
class ElevenLabsTts {
  /// Synthesize text to audio using ElevenLabs API.
  ///
  /// NOTE: This is a stub. Production audio is pre-generated via server scripts.
  /// See: server/generate_audio_from_text.sh, server/generate_batch_parables.sh
  Future<Uint8List> synthesize({
    required String text,
    required String voiceId,
    required String apiKey,
    double stability = 0.5,
    double similarityBoost = 0.75,
  }) async {
    // Stub implementation - logs parameters for debugging
    final encoded = jsonEncode({
      'chars': text.length,
      'voiceId': voiceId,
      'stability': stability,
      'similarityBoost': similarityBoost,
      'apiKeyLength': apiKey.length,
    });
    debugPrint('[ElevenLabsTts] synthesize called (stub): $encoded');
    return Uint8List(0);
  }
}
