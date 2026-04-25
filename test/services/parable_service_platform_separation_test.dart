// Cloud Foundation v1.1 — Smart Offline Library is Android-only.
// SPEC Feature 27, INVARIANTS: File Integrity + Favorited Audio Protection.
//
// In v1.1, iOS uses the shared cache → bundled → R2 resolver but does NOT
// run the Smart Offline Library logic (favorite-triggered downloads, cache
// eviction). This test verifies the public favorite-pinning entry point is
// a no-op on non-Android platforms (deferred to v2 for iOS).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '_cloud_audio_test_helpers.dart';

void main() {
  test(
    'ensureCachedForFavorite is a no-op on non-Android (iOS v1.1 deferred)',
    () async {
      final fake = await startFakeAudioServer(body: sampleAudioBytes);
      addTearDown(() => fake.server.close(force: true));

      final ctx = await setupCloudAudioTest(audioBaseUrl: fake.baseUrl);
      final parable = testParable();

      // On the test host, Platform.isAndroid is false (mirrors iOS at runtime
      // for this contract). Smart Offline favorite-pinning must be skipped.
      await ctx.service.ensureCachedForFavorite(parable);

      final cacheDir = await ctx.service.getAudioCacheDirForTesting();
      final cachedFile = File('${cacheDir.path}/${parable.audioFilePath}');
      expect(
        await cachedFile.exists(),
        isFalse,
        reason: 'iOS v1.1 must NOT pre-download favorited audio '
            '(Smart Offline deferred to v2)',
      );
    },
  );
}
