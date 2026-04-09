// Cloud Foundation v1 — iOS never enters Android download/cache path.
// SPEC Feature 27, Plan: Test #6.
//
// Verifies the platform branch in ParableService.getAudioFile() by checking
// that the iOS helper (the only code path on Platform.isIOS) is purely
// asset-based: no cache directory writes, no HTTP calls.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '_cloud_audio_test_helpers.dart';

void main() {
  test(
    'iOS asset helper does not create or read the Android audio_cache dir',
    () async {
      final ctx = await setupCloudAudioTest(audioBaseUrl: 'http://0.0.0.0:1');
      final parable = testParable();

      // Snapshot the documents dir BEFORE the call to detect any cache
      // directory creation by the iOS helper.
      final docsBefore = Directory('${ctx.root.path}/documents');
      final cacheBefore = Directory('${docsBefore.path}/audio_cache');
      expect(await cacheBefore.exists(), isFalse,
          reason: 'cache should not exist before any call');

      await ctx.service.getAudioFileFromAssetsForTesting(parable);

      expect(
        await cacheBefore.exists(),
        isFalse,
        reason: 'iOS helper must NOT create the Android audio_cache directory',
      );
    },
  );
}
