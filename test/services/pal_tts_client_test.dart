import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/pal_tts_client.dart';

void main() {
  group('PalTtsClient', () {
    test('can be constructed without throwing', () {
      expect(() => PalTtsClient(), returnsNormally);
    });

    test('synthesizeNamePrefix returns null when server is unavailable', () async {
      final client = PalTtsClient();
      // localhost:8080 is not running in test — should return null, not throw
      final result = await client.synthesizeNamePrefix(
        voiceKey: 'VOICE_GRACE',
        text: 'Hey, Grace!',
      );
      expect(result, isNull,
          reason: 'Should return null when server is unavailable');
      client.dispose();
    });

    test('synthesizeNamePrefix rejects empty voiceKey', () async {
      final client = PalTtsClient();
      final result = await client.synthesizeNamePrefix(
        voiceKey: '',
        text: 'Hey, Grace!',
      );
      expect(result, isNull,
          reason: 'Should return null for empty voiceKey');
      client.dispose();
    });

    test('synthesizeNamePrefix rejects empty text', () async {
      final client = PalTtsClient();
      final result = await client.synthesizeNamePrefix(
        voiceKey: 'VOICE_GRACE',
        text: '',
      );
      expect(result, isNull,
          reason: 'Should return null for empty text');
      client.dispose();
    });
  });
}
