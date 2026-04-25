// Cloud Foundation v1 — Android: cache hit returns local file without network.
// SPEC Feature 27, Plan: Test #2.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '_cloud_audio_test_helpers.dart';

void main() {
  test('Android: cache hit returns local file without network', () async {
    final ctx = await setupCloudAudioTest(audioBaseUrl: 'http://0.0.0.0:1');
    final parable = testParable();

    // Pre-populate the cache directory with the expected file.
    final cacheDir = await ctx.service.getAudioCacheDirForTesting();
    final cachedFile = File('${cacheDir.path}/${parable.audioFilePath}');
    await cachedFile.parent.create(recursive: true);
    await cachedFile.writeAsBytes(sampleAudioBytes);

    // No HTTP server running on 0.0.0.0:1 — if the resolver tries to fetch
    // from the network this would fail. A cache hit must NOT touch the network.
    final result = await ctx.service.getAudioFileWithCloudFallbackForTesting(parable);

    expect(result, isNotNull);
    expect(result!.path, cachedFile.path);
    expect(await result.readAsBytes(), sampleAudioBytes);
  });
}
