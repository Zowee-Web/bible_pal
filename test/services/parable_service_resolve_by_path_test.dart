// Slice 3 parity test: _resolveByPath (helper) and _getAudioFileAndroid
// (thin wrapper) must produce identical results for the same inputs.
//
// One Tier 1 (cache hit) scenario is enough — the wrapper does nothing
// but forward arguments, so any divergence in the cascade would also
// surface in the broader parable_service_android_* tests.

import 'dart:io';

import 'package:bible_pal/services/parable_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '_cloud_audio_test_helpers.dart';

void main() {
  test(
      'parity: getAudioFileAndroidForTesting and resolveByPathForTesting '
      'resolve the same Tier 1 cache file', () async {
    final ctx = await setupCloudAudioTest(audioBaseUrl: 'http://0.0.0.0:1');
    final parable = testParable();

    // Pre-populate the cache so both entry points hit Tier 1 without
    // touching the network.
    final cacheDir = await ctx.service.getAudioCacheDirForTesting();
    final cachedFile = File('${cacheDir.path}/${parable.audioFilePath}');
    await cachedFile.parent.create(recursive: true);
    await cachedFile.writeAsBytes(sampleAudioBytes);

    final viaWrapper =
        await ctx.service.getAudioFileAndroidForTesting(parable);
    final viaHelper = await ctx.service.resolveByPathForTesting(
      parable.audioFilePath!,
      storyId: parable.storyId,
      lengthBucket: parable.lengthBucket.name,
      kind: AudioKind.story,
    );

    expect(viaWrapper, isNotNull);
    expect(viaHelper, isNotNull);
    expect(viaHelper!.path, viaWrapper!.path);
    expect(await viaHelper.readAsBytes(), await viaWrapper.readAsBytes());
  });
}
