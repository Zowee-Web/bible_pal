// Smart Offline Library v1 — eviction, favorite protection, soft budget.
// SPEC Feature 27 + INVARIANT: Favorited Audio Protection.
//
// These tests use the existing _cloud_audio_test_helpers.dart setup. They
// override the cache budget via setAudioCacheBudgetForTesting so we don't
// need to allocate real 600 MB fixtures.

import 'dart:io';

import 'package:bible_pal/models/favorite.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_cloud_audio_test_helpers.dart';

/// A real-manifest storyId + its actual audioFilePath. We use real manifest
/// entries so _getProtectedAudioPaths() can resolve storyId -> audioFilePath
/// via the existing _loadManifest() codepath.
const _favoritedStoryId = 'story_2000_joyful_short_creative';
const _favoritedAudioPath = 'creative/2000/audio_2000_story_short.mp3';

const _otherStoryId1 = 'story_2001_anxious_short_creative';
const _otherAudioPath1 = 'creative/2001/audio_2001_story_short.mp3';

const _otherStoryId2 = 'story_2002_weary_short_creative';
const _otherAudioPath2 = 'creative/2002/audio_2002_story_short.mp3';

const _otherAudioPath3 = 'creative/2003/audio_2003_story_short.mp3';

/// Writes a fake cached audio file with the given size and mtime.
Future<File> _writeCachedFile(
  Directory cacheDir,
  String relativePath, {
  required int sizeBytes,
  required DateTime mtime,
}) async {
  final f = File('${cacheDir.path}/$relativePath');
  await f.parent.create(recursive: true);
  await f.writeAsBytes(List<int>.filled(sizeBytes, 0));
  await f.setLastModified(mtime);
  return f;
}

Future<void> _addFavorite(StorageService storage, String storyId) async {
  await storage.addFavorite(Favorite(
    storyId: storyId,
    title: 'Test',
    mood: 'joyful',
    length: 0,
    dateSaved: DateTime.now(),
  ));
}

void main() {
  tearDown(() {
    // Always restore the production budget so tests don't bleed into each other.
    ParableService.resetAudioCacheBudgetForTesting();
  });

  test('Test 1: favorited audio survives an over-budget eviction pass',
      () async {
    final ctx = await setupCloudAudioTest();
    // Get the storage instance the service uses.
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.create();
    final service = ParableService(storage, null, true);

    final cacheDir = await service.getAudioCacheDirForTesting();
    // Budget is 200 bytes. We will create 4 files of 100 bytes = 400 total.
    ParableService.setAudioCacheBudgetForTesting(200);

    // Pre-populate cache: 1 favorited (oldest), 3 non-favorited (newer).
    final now = DateTime.now();
    final favFile = await _writeCachedFile(
      cacheDir,
      _favoritedAudioPath,
      sizeBytes: 100,
      mtime: now.subtract(const Duration(hours: 10)),
    );
    final other1 = await _writeCachedFile(
      cacheDir,
      _otherAudioPath1,
      sizeBytes: 100,
      mtime: now.subtract(const Duration(hours: 5)),
    );
    final other2 = await _writeCachedFile(
      cacheDir,
      _otherAudioPath2,
      sizeBytes: 100,
      mtime: now.subtract(const Duration(hours: 3)),
    );
    final other3 = await _writeCachedFile(
      cacheDir,
      _otherAudioPath3,
      sizeBytes: 100,
      mtime: now.subtract(const Duration(hours: 1)),
    );

    // Mark the favorited story as favorited.
    await _addFavorite(storage, _favoritedStoryId);

    await service.evictIfOverBudgetForTesting();

    // Favorited file MUST survive even though it has the oldest mtime.
    expect(await favFile.exists(), isTrue,
        reason: 'favorited audio must NEVER be evicted');
    // Cache should now be at or under budget.
    final total = await service.getAudioCacheTotalBytesForTesting();
    expect(total, lessThanOrEqualTo(200));
    // At least one non-favorited file got evicted.
    final survivors = [other1, other2, other3];
    final survivorCount =
        (await Future.wait(survivors.map((f) => f.exists())))
            .where((e) => e)
            .length;
    expect(survivorCount, lessThan(3),
        reason: 'at least one non-favorited file should have been evicted');
    // Use ctx so the analyzer doesn't flag it.
    expect(ctx.root.existsSync(), isTrue);
  });

  test('Test 2: oldest non-favorited files are evicted first', () async {
    await setupCloudAudioTest();
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.create();
    final service = ParableService(storage, null, true);

    final cacheDir = await service.getAudioCacheDirForTesting();
    // Budget = 150 bytes; populate with 3 × 100-byte non-favorited files.
    // Eviction must remove 2 of them (oldest first) to get under budget.
    ParableService.setAudioCacheBudgetForTesting(150);

    final now = DateTime.now();
    final oldest = await _writeCachedFile(
      cacheDir,
      _otherAudioPath1,
      sizeBytes: 100,
      mtime: now.subtract(const Duration(hours: 5)),
    );
    final middle = await _writeCachedFile(
      cacheDir,
      _otherAudioPath2,
      sizeBytes: 100,
      mtime: now.subtract(const Duration(hours: 3)),
    );
    final newest = await _writeCachedFile(
      cacheDir,
      _otherAudioPath3,
      sizeBytes: 100,
      mtime: now.subtract(const Duration(hours: 1)),
    );

    await service.evictIfOverBudgetForTesting();

    expect(await oldest.exists(), isFalse,
        reason: 'oldest file should be evicted first');
    expect(await middle.exists(), isFalse,
        reason: 'second-oldest file should also be evicted to fit budget');
    expect(await newest.exists(), isTrue,
        reason: 'newest file should survive');
  });

  test('Test 3: ensureCachedForFavorite no-ops when already cached', () async {
    // Point at an unreachable URL — if we ever try to download, the test
    // would fail with a connection error.
    final ctx =
        await setupCloudAudioTest(audioBaseUrl: 'http://127.0.0.1:1');
    final cacheDir = await ctx.service.getAudioCacheDirForTesting();

    final cachedFile = File('${cacheDir.path}/$_favoritedAudioPath');
    await cachedFile.parent.create(recursive: true);
    await cachedFile.writeAsBytes(sampleAudioBytes);
    final originalMtime = (await cachedFile.stat()).modified;

    // Use the Android resolver directly (cross-platform test runtime).
    // ensureCachedForFavorite is a thin wrapper around this on Android.
    final parable = testParable(
      storyId: _favoritedStoryId,
      audioFilePath: _favoritedAudioPath,
    );
    final result =
        await ctx.service.getAudioFileWithCloudFallbackForTesting(parable);

    expect(result, isNotNull);
    expect(await result!.readAsBytes(), sampleAudioBytes,
        reason: 'cached file content unchanged');
    // mtime may have been touched by the cache hit (recency signal),
    // but the file must still exist.
    expect(await cachedFile.exists(), isTrue);
    expect(originalMtime, isNotNull); // sanity-check stat() worked
  });

  test('Test 4: ensureCachedForFavorite downloads when not cached', () async {
    final fake = await startFakeAudioServer(body: sampleAudioBytes);
    addTearDown(() => fake.server.close(force: true));

    final ctx = await setupCloudAudioTest(audioBaseUrl: fake.baseUrl);
    final cacheDir = await ctx.service.getAudioCacheDirForTesting();

    // Use a path that is NOT bundled in pubspec.yaml so Tier 2 (asset) fails
    // and the resolver falls through to Tier 3 (R2 download). The default
    // testParable() points at creative/9999/... which is not a real story.
    final parable = testParable();

    // Use the Android resolver directly because Platform.isAndroid is false
    // on the test host. ensureCachedForFavorite is a thin wrapper.
    final result =
        await ctx.service.getAudioFileWithCloudFallbackForTesting(parable);

    expect(result, isNotNull);
    final cachedFile = File('${cacheDir.path}/${parable.audioFilePath}');
    expect(await cachedFile.exists(), isTrue);
    expect(await cachedFile.readAsBytes(), sampleAudioBytes);
  });

  test(
      'Test 4b: ensureCachedForFavorite is a safe no-op on non-Android host',
      () async {
    // On the test host (macOS), Platform.isAndroid is false, so the public
    // method must return without throwing AND without touching the cache.
    final ctx =
        await setupCloudAudioTest(audioBaseUrl: 'http://127.0.0.1:1');
    final parable = testParable(
      storyId: _favoritedStoryId,
      audioFilePath: _favoritedAudioPath,
    );

    // Should not throw.
    await ctx.service.ensureCachedForFavorite(parable);

    final cacheDir = await ctx.service.getAudioCacheDirForTesting();
    final cachedFile = File('${cacheDir.path}/$_favoritedAudioPath');
    expect(await cachedFile.exists(), isFalse,
        reason: 'no-op on non-Android host must not write to cache');
  });

  test('Test 5: unfavoriting does NOT immediately delete cached audio',
      () async {
    await setupCloudAudioTest();
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.create();
    final service = ParableService(storage, null, true);

    final cacheDir = await service.getAudioCacheDirForTesting();
    final cachedFile = await _writeCachedFile(
      cacheDir,
      _favoritedAudioPath,
      sizeBytes: 100,
      mtime: DateTime.now(),
    );

    await _addFavorite(storage, _favoritedStoryId);
    expect(await storage.isFavorited(_favoritedStoryId), isTrue);

    await storage.removeFavorite(_favoritedStoryId);
    expect(await storage.isFavorited(_favoritedStoryId), isFalse);

    // The audio file MUST still exist immediately after unfavoriting.
    // (It only becomes evictable on the NEXT over-budget eviction pass.)
    expect(await cachedFile.exists(), isTrue,
        reason: 'unfavoriting must NOT immediately delete cached audio');
  });

  test('Test 6: soft budget overrun is allowed when only favorites remain',
      () async {
    await setupCloudAudioTest();
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.create();
    final service = ParableService(storage, null, true);

    final cacheDir = await service.getAudioCacheDirForTesting();
    // Budget = 100 bytes; cache will hold 3 × 100-byte files all favorited
    // (300 bytes total — 3x the budget).
    ParableService.setAudioCacheBudgetForTesting(100);

    final f1 = await _writeCachedFile(
      cacheDir,
      _favoritedAudioPath,
      sizeBytes: 100,
      mtime: DateTime.now().subtract(const Duration(hours: 3)),
    );
    final f2 = await _writeCachedFile(
      cacheDir,
      _otherAudioPath1,
      sizeBytes: 100,
      mtime: DateTime.now().subtract(const Duration(hours: 2)),
    );
    final f3 = await _writeCachedFile(
      cacheDir,
      _otherAudioPath2,
      sizeBytes: 100,
      mtime: DateTime.now().subtract(const Duration(hours: 1)),
    );

    await _addFavorite(storage, _favoritedStoryId);
    await _addFavorite(storage, _otherStoryId1);
    await _addFavorite(storage, _otherStoryId2);

    await service.evictIfOverBudgetForTesting();

    // Soft budget: when ALL remaining files are favorited, NOTHING is
    // evicted, even though we are 3x over budget.
    expect(await f1.exists(), isTrue);
    expect(await f2.exists(), isTrue);
    expect(await f3.exists(), isTrue);
    final total = await service.getAudioCacheTotalBytesForTesting();
    expect(total, 300,
        reason: 'favorites must never be evicted, overrun is honored');
  });
}
