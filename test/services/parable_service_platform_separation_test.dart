// Asset-loading helper contract — verifies that the helper does not create
// or read the cache directory used by the three-tier resolver. After Step 1
// (iOS R2 resolver parity) the helper is no longer the iOS production path,
// but it is still used by the desktop/test branch of getAudioFile, so its
// no-cache-side-effects contract is documented here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '_cloud_audio_test_helpers.dart';

void main() {
  test(
    'asset helper does not create or read the audio_cache directory',
    () async {
      final ctx = await setupCloudAudioTest(audioBaseUrl: 'http://0.0.0.0:1');
      final parable = testParable();

      // Snapshot the documents dir BEFORE the call to detect any cache
      // directory creation by the asset helper.
      final docsBefore = Directory('${ctx.root.path}/documents');
      final cacheBefore = Directory('${docsBefore.path}/audio_cache');
      expect(await cacheBefore.exists(), isFalse,
          reason: 'cache should not exist before any call');

      await ctx.service.getAudioFileFromAssetsForTesting(parable);

      expect(
        await cacheBefore.exists(),
        isFalse,
        reason: 'asset helper must NOT create the audio_cache directory',
      );
    },
  );
}
