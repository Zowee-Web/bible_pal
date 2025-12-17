import 'dart:convert';

import 'package:flutter/foundation.dart';

class ElevenLabsTts {
  Future<Uint8List> synthesize({
    required String text,
    required String voiceId,
    required String apiKey,
    double stability = 0.5,
    double similarityBoost = 0.75,
  }) async {
    // TODO: implement ElevenLabs API call
    final encoded = jsonEncode({
      'chars': text.length,
      'voiceId': voiceId,
      'stability': stability,
      'similarityBoost': similarityBoost,
      'apiKeyLength': apiKey.length,
    });
    debugPrint('synthesize: $encoded');
    return Uint8List(0);
  }
}
