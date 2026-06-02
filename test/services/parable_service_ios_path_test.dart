// Asset-loading helper contract — used by the desktop/test branch of
// getAudioFile when _useAssets is set. After Step 1 (iOS R2 resolver parity)
// this helper is no longer the iOS production path; iOS now routes through
// _getAudioFileAndroid (cache → bundled → R2), same as Android. The helper
// still exists and is still exercised by desktop/test runs and the public
// test seam, so its no-network contract is documented here.

import 'package:flutter_test/flutter_test.dart';

import '_cloud_audio_test_helpers.dart';

void main() {
  test(
    'asset helper returns null when asset is missing — no network involved',
    () async {
      // Even with a base URL set, the asset helper must NOT touch the network.
      final ctx = await setupCloudAudioTest(audioBaseUrl: 'http://0.0.0.0:1');
      final parable = testParable();

      // No bundled asset exists in the test runtime — should return null
      // gracefully without throwing or attempting an HTTP request.
      final result = await ctx.service.getAudioFileFromAssetsForTesting(parable);

      expect(result, isNull,
          reason: 'asset helper has no network fallback; missing asset → null');
    },
  );
}
