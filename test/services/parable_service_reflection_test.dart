// Slice 4: reflection audio routes through the same three-tier
// resolver as story audio on Android. Service-level tests cover Tier 1
// (cache hit), Tier 3 (R2 download), and the null case the widget maps
// to the "Connect to play" state.

import 'dart:io';

import 'package:bible_pal/models/parable.dart';
import 'package:flutter_test/flutter_test.dart';

import '_cloud_audio_test_helpers.dart';

Parable _reflectionParable({
  String storyId = 'story_test_001',
  String audioFilePath = 'traditional/9999/audio_9999_story_short.mp3',
  String reflectionAudioPath = 'traditional/9999/audio_9999_reflection.mp3',
}) =>
    Parable(
      storyId: storyId,
      title: 'Test Story',
      mood: 'joyful',
      storytellingMode: 'traditional',
      kidFriendly: false,
      audioFilePath: audioFilePath,
      reflectionAudioPath: reflectionAudioPath,
      storyLength: 'short',
    );

void main() {
  test(
      'getReflectionAudioFile: Tier 1 cache hit returns the cached '
      'reflection file without touching the network', () async {
    // Bind to a closed loopback port so any accidental network call fails.
    final ctx = await setupCloudAudioTest(audioBaseUrl: 'http://0.0.0.0:1');
    final parable = _reflectionParable();

    final cacheDir = await ctx.service.getAudioCacheDirForTesting();
    final cachedFile =
        File('${cacheDir.path}/${parable.reflectionAudioPath}');
    await cachedFile.parent.create(recursive: true);
    await cachedFile.writeAsBytes(sampleAudioBytes);

    final result = await ctx.service.getReflectionAudioFileAndroidForTesting(parable);

    expect(result, isNotNull);
    expect(result!.path, cachedFile.path);
    expect(await result.readAsBytes(), sampleAudioBytes);
  });

  test(
      'getReflectionAudioFile: Tier 3 downloads reflection audio from R2 '
      'and caches it', () async {
    final fake = await startFakeAudioServer(body: sampleAudioBytes);
    addTearDown(() => fake.server.close(force: true));

    final ctx = await setupCloudAudioTest(audioBaseUrl: fake.baseUrl);
    final parable = _reflectionParable();

    final result = await ctx.service.getReflectionAudioFileAndroidForTesting(parable);

    expect(result, isNotNull, reason: 'reflection download should succeed');
    expect(await result!.readAsBytes(), sampleAudioBytes);

    // Subsequent call should hit Tier 1 cache.
    final cacheDir = await ctx.service.getAudioCacheDirForTesting();
    final expectedCachePath =
        '${cacheDir.path}/${parable.reflectionAudioPath}';
    expect(result.path, expectedCachePath,
        reason: 'downloaded reflection must be cached at the canonical path');
  });

  test(
      'getReflectionAudioFile: returns null when all three tiers fail '
      '(offline → widget surfaces "Connect to play")', () async {
    // Closed loopback port + no cache + reflection path not in bundled
    // assets → every tier misses.
    final ctx = await setupCloudAudioTest(audioBaseUrl: 'http://0.0.0.0:1');
    final parable = _reflectionParable();

    final result = await ctx.service.getReflectionAudioFileAndroidForTesting(parable);

    expect(result, isNull,
        reason:
            'all three tiers must fail when offline + uncached + unbundled');
  });

  test(
      'getReflectionAudioFile: returns null when parable has no '
      'reflectionAudioPath', () async {
    final ctx = await setupCloudAudioTest(audioBaseUrl: 'http://0.0.0.0:1');
    final parable = Parable(
      storyId: 'story_no_reflection',
      title: 'No Reflection',
      mood: 'joyful',
      storytellingMode: 'traditional',
      kidFriendly: false,
      audioFilePath: 'traditional/9999/audio_9999_story_short.mp3',
      storyLength: 'short',
      // reflectionAudioPath intentionally omitted
    );

    final result = await ctx.service.getReflectionAudioFileAndroidForTesting(parable);

    expect(result, isNull);
  });
}
