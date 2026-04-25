// Cloud Foundation v1.1 — public-style iOS bundle: graceful failure when
// asset is not bundled, R2 fails, and cache is empty.
// SPEC Feature 27.
//
// In the public TestFlight bundle, story audio for 1005-1120 lives only on
// R2. If R2 is unreachable AND the asset isn't bundled, the resolver must
// return null and surface an actionable AudioResolveError so the UI can
// show a graceful "no network" message instead of crashing.

import 'package:bible_pal/services/parable_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '_cloud_audio_test_helpers.dart';

void main() {
  test(
    'Cloud failure surfaces AudioResolveError.downloadFailed for graceful UI',
    () async {
      // No AUDIO_BASE_URL configured → R2 leg short-circuits.
      final ctx = await setupCloudAudioTest();
      final parable = testParable();

      final result =
          await ctx.service.getAudioFileWithCloudFallbackForTesting(parable);

      expect(result, isNull, reason: 'no asset, no R2 base → null');
      expect(
        ctx.service.lastAudioError,
        AudioResolveError.downloadFailed,
        reason: 'UI must be able to distinguish a graceful failure',
      );
    },
  );

  test('R2 404 surfaces AudioResolveError.remoteNotFound', () async {
    final fake = await startFakeAudioServer(body: const [], statusCode: 404);
    addTearDown(() => fake.server.close(force: true));

    final ctx = await setupCloudAudioTest(audioBaseUrl: fake.baseUrl);
    final parable = testParable();

    final result =
        await ctx.service.getAudioFileWithCloudFallbackForTesting(parable);

    expect(result, isNull);
    expect(
      ctx.service.lastAudioError,
      AudioResolveError.remoteNotFound,
      reason: 'distinct error code lets UI message specifically for missing '
          'cloud content vs. transient network failure',
    );
  });

  test('Successful R2 download clears lastAudioError back to none', () async {
    final fake = await startFakeAudioServer(body: sampleAudioBytes);
    addTearDown(() => fake.server.close(force: true));

    final ctx = await setupCloudAudioTest(audioBaseUrl: fake.baseUrl);
    final parable = testParable();

    final result =
        await ctx.service.getAudioFileWithCloudFallbackForTesting(parable);

    expect(result, isNotNull);
    expect(ctx.service.lastAudioError, AudioResolveError.none,
        reason: 'success path must reset error state');
  });
}
