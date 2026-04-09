// Cloud Foundation v1 — interrupted download leaves no partial files.
// SPEC Feature 27, Plan: Test #5.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '_cloud_audio_test_helpers.dart';

void main() {
  test('Failed download (HTTP 500) leaves no partial files', () async {
    final fake = await startFakeAudioServer(
      body: const [],
      statusCode: 500,
    );
    addTearDown(() => fake.server.close(force: true));

    final ctx = await setupCloudAudioTest(audioBaseUrl: fake.baseUrl);
    final parable = testParable();

    final result = await ctx.service.getAudioFileAndroidForTesting(parable);
    expect(result, isNull, reason: 'failed download must not return a file');

    final cacheDir = await ctx.service.getAudioCacheDirForTesting();
    final finalFile = File('${cacheDir.path}/${parable.audioFilePath}');
    final tmpFile = File('${finalFile.path}.tmp');

    expect(
      await finalFile.exists(),
      isFalse,
      reason: 'no partial file should be promoted to the final cache path',
    );
    expect(
      await tmpFile.exists(),
      isFalse,
      reason: '.tmp must be cleaned up on failure',
    );
  });

  test('Stale .tmp file from prior failure is cleared on next download attempt',
      () async {
    final fake = await startFakeAudioServer(body: sampleAudioBytes);
    addTearDown(() => fake.server.close(force: true));

    final ctx = await setupCloudAudioTest(audioBaseUrl: fake.baseUrl);
    final parable = testParable();

    // Plant a stale .tmp file as if a previous download had been killed.
    final cacheDir = await ctx.service.getAudioCacheDirForTesting();
    final finalFile = File('${cacheDir.path}/${parable.audioFilePath}');
    await finalFile.parent.create(recursive: true);
    final staleTmp = File('${finalFile.path}.tmp');
    await staleTmp.writeAsBytes(const [0xDE, 0xAD]);
    expect(await staleTmp.exists(), isTrue);

    final result = await ctx.service.getAudioFileAndroidForTesting(parable);
    expect(result, isNotNull);
    expect(await result!.readAsBytes(), sampleAudioBytes);
    expect(await staleTmp.exists(), isFalse,
        reason: 'stale .tmp must not survive a successful download');
  });
}
