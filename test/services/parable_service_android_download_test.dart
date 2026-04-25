// Cloud Foundation v1 — Android: R2 download succeeds and file is cached.
// SPEC Feature 27, Plan: Test #4.

import 'package:flutter_test/flutter_test.dart';

import '_cloud_audio_test_helpers.dart';

void main() {
  test('Android: R2 download succeeds and file is cached', () async {
    final fake = await startFakeAudioServer(body: sampleAudioBytes);
    addTearDown(() => fake.server.close(force: true));

    final ctx = await setupCloudAudioTest(audioBaseUrl: fake.baseUrl);
    final parable = testParable();

    final progressUpdates = <double>[];
    final result = await ctx.service.getAudioFileWithCloudFallbackForTesting(
      parable,
      onProgress: progressUpdates.add,
    );

    expect(result, isNotNull, reason: 'download should succeed');
    expect(await result!.readAsBytes(), sampleAudioBytes);

    // Subsequent call should hit the cache (no progress callbacks).
    progressUpdates.clear();
    final result2 = await ctx.service.getAudioFileWithCloudFallbackForTesting(
      parable,
      onProgress: progressUpdates.add,
    );
    expect(result2!.path, result.path);
    expect(progressUpdates, isEmpty,
        reason: 'cache hit should not invoke progress callback');
  });
}
