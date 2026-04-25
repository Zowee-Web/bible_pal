// Cloud Foundation v1.1 — iOS path: shared three-tier resolver.
// SPEC Feature 27.
//
// In v1.1, iOS uses the same cache → bundled → R2 resolver as Android.
// Platform.isIOS reports the host OS in unit tests, so we exercise the
// shared resolver directly via getAudioFileWithCloudFallbackForTesting,
// which is the same code path entered on iOS at runtime.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '_cloud_audio_test_helpers.dart';

void main() {
  test(
    'iOS resolver: missing asset falls through to R2 download (v1.1)',
    () async {
      final fake = await startFakeAudioServer(body: sampleAudioBytes);
      addTearDown(() => fake.server.close(force: true));

      final ctx = await setupCloudAudioTest(audioBaseUrl: fake.baseUrl);
      final parable = testParable();

      final result =
          await ctx.service.getAudioFileWithCloudFallbackForTesting(parable);

      expect(result, isNotNull,
          reason: 'iOS v1.1 must fall through to R2 when asset is missing');
      expect(await result!.readAsBytes(), sampleAudioBytes);

      final cacheDir = await ctx.service.getAudioCacheDirForTesting();
      final cachedFile = File('${cacheDir.path}/${parable.audioFilePath}');
      expect(await cachedFile.exists(), isTrue,
          reason: 'iOS v1.1 must persist downloaded audio to local cache');
    },
  );

  test(
    'iOS resolver: returns null gracefully when no R2 base URL is set',
    () async {
      final ctx = await setupCloudAudioTest();
      final parable = testParable();

      final result =
          await ctx.service.getAudioFileWithCloudFallbackForTesting(parable);

      expect(result, isNull,
          reason: 'no asset, no AUDIO_BASE_URL → null without throwing');
    },
  );
}
