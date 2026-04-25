// Cloud Foundation v1 — Android resolution order: cache > bundled > remote.
// SPEC Feature 27, Plan: Test #8.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '_cloud_audio_test_helpers.dart';

void main() {
  test(
    'Android: cached file beats R2 (cache hit prevents network call)',
    () async {
      // Server would return a DIFFERENT body if reached.
      final fake = await startFakeAudioServer(body: const [9, 9, 9, 9]);
      addTearDown(() => fake.server.close(force: true));

      final ctx = await setupCloudAudioTest(audioBaseUrl: fake.baseUrl);
      final parable = testParable();

      // Pre-populate the cache with KNOWN bytes.
      final cacheDir = await ctx.service.getAudioCacheDirForTesting();
      final cachedFile = File('${cacheDir.path}/${parable.audioFilePath}');
      await cachedFile.parent.create(recursive: true);
      await cachedFile.writeAsBytes(sampleAudioBytes);

      final result = await ctx.service.getAudioFileWithCloudFallbackForTesting(parable);

      expect(result, isNotNull);
      // If the cache had been bypassed, the bytes would equal [9,9,9,9].
      expect(await result!.readAsBytes(), sampleAudioBytes);
    },
  );

  test(
    'Android: when cache is empty and no asset is bundled, downloads from R2',
    () async {
      final fake = await startFakeAudioServer(body: sampleAudioBytes);
      addTearDown(() => fake.server.close(force: true));

      final ctx = await setupCloudAudioTest(audioBaseUrl: fake.baseUrl);
      final parable = testParable();

      final result = await ctx.service.getAudioFileWithCloudFallbackForTesting(parable);

      expect(result, isNotNull);
      expect(await result!.readAsBytes(), sampleAudioBytes);
    },
  );
}
