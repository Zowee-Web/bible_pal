// Cloud Foundation v1 — iOS path: asset playback works, no network calls.
// SPEC Feature 27, Plan: Test #1.
//
// On the Flutter test runtime, Platform.isIOS reports the host OS, so we
// cannot directly exercise the platform branch. Instead we verify the iOS
// helper (which is the entire iOS code path) by calling it explicitly.

import 'package:flutter_test/flutter_test.dart';

import '_cloud_audio_test_helpers.dart';

void main() {
  test(
    'iOS asset helper returns null when asset is missing — no network involved',
    () async {
      // Even with a base URL set, the iOS helper must NOT touch the network.
      final ctx = await setupCloudAudioTest(audioBaseUrl: 'http://0.0.0.0:1');
      final parable = testParable();

      // No bundled asset exists in the test runtime — should return null
      // gracefully without throwing or attempting an HTTP request.
      final result = await ctx.service.getAudioFileFromAssetsForTesting(parable);

      expect(result, isNull,
          reason: 'iOS helper has no network fallback; missing asset → null');
    },
  );
}
