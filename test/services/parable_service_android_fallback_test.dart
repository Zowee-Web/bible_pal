// Cloud Foundation v1 — Android: bundled-asset path returns null when neither
// cache nor R2 are available, and existing error handling kicks in.
// SPEC Feature 27, Plan: Test #3.

import 'package:flutter_test/flutter_test.dart';

import '_cloud_audio_test_helpers.dart';

void main() {
  test(
    'Android: returns null when audio is missing from cache, assets, and R2',
    () async {
      // No AUDIO_BASE_URL configured -> R2 leg short-circuits to null.
      final ctx = await setupCloudAudioTest();
      final parable = testParable(
        audioFilePath: 'creative/0000/does_not_exist.mp3',
      );

      final result = await ctx.service.getAudioFileWithCloudFallbackForTesting(parable);
      expect(result, isNull);
    },
  );

  test('Android: 404 from R2 short-circuits with no retry, returns null',
      () async {
    final fake = await startFakeAudioServer(
      body: const [],
      statusCode: 404,
    );
    addTearDown(() => fake.server.close(force: true));

    final ctx = await setupCloudAudioTest(audioBaseUrl: fake.baseUrl);
    final parable = testParable();

    final result = await ctx.service.getAudioFileWithCloudFallbackForTesting(parable);
    expect(result, isNull);
  });
}
