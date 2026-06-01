// Phase 2 / Slice 7 — end-to-end integration tests for the R2 distribution
// layer. Covers the four scenarios from the slice prompt:
//   1. Airplane-mode launch with cached catalog uses cache; uncached audio
//      surfaces null (the data the widget maps to "Connect to play").
//   2. Online launch with stale cache uses cache now and the background
//      refresh updates the cache for the next launch.
//   3. Reflection cascade parity with story audio (cache hit + R2 download).
//   4. New-story-in-catalog smoke: a parable that exists ONLY in the cached
//      catalog is surfaced by the manifest API and its audio plays via R2.
//
// All tests run at the service layer using loopback HTTP. The "Connect to
// play" UI assertion in scenario 1 is verified at the service-contract
// level: `getReflectionAudioFile` returns null when offline + uncached +
// unbundled. The widget rewire from Slice 4 maps that null to the
// _reflectionUnavailable state.

import 'dart:convert';
import 'dart:io';

import 'package:bible_pal/core/app_logger.dart';
import 'package:bible_pal/services/catalog_service.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_cloud_audio_test_helpers.dart';

// ─── Fixtures ────────────────────────────────────────────────────────────────

Map<String, dynamic> _parableMap({
  required String storyId,
  required String audioFilePath,
  String? reflectionAudioPath,
  String mood = 'joyful',
}) {
  return {
    'storyId': storyId,
    'title': 'Integration Story $storyId',
    'mood': mood,
    'storytellingMode': 'traditional',
    'kidFriendly': false,
    'translationId': 'WEB',
    'languageStyle': 'WEB',
    'storyLength': 'short',
    'audioFilePath': audioFilePath,
    if (reflectionAudioPath != null) 'reflectionAudioPath': reflectionAudioPath,
    'bibleSourceRef': 'Matthew 1:1',
    'bibleStoryKey': 'integration_test_$storyId',
  };
}

String _catalogJson({
  required int version,
  required List<Map<String, dynamic>> parables,
}) =>
    jsonEncode({'version': version, 'parables': parables});

/// Builds an integration environment with two HTTP channels:
///   - `catalogHandler` intercepts catalog probes (via CatalogService's
///     injected http.Client).
///   - `audioBaseUrl` is the URL ParableService's internal http.Client
///     uses to fetch audio. Point it at a fake server for happy-path
///     downloads or at a closed port (e.g. http://0.0.0.0:1) to
///     simulate airplane mode.
Future<({ParableService service, Directory docs})> _buildEnv({
  required MockClientHandler catalogHandler,
  required String audioBaseUrl,
  String? primedCatalogBody,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues({});
  AppLogger.instance.clearBreadcrumbs();

  final docs = await Directory.systemTemp.createTemp('bp_r2_integration_');

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'getApplicationDocumentsDirectory':
      case 'getTemporaryDirectory':
      case 'getApplicationSupportDirectory':
        return docs.path;
      default:
        return null;
    }
  });

  dotenv.testLoad(fileInput: 'AUDIO_BASE_URL=$audioBaseUrl');

  if (primedCatalogBody != null) {
    final cacheFile = File('${docs.path}/catalog_cache/manifest.json');
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString(primedCatalogBody);
  }

  final catalog = CatalogService(
    client: MockClient(catalogHandler),
    docsDirProvider: () async => docs,
    baseUrlProvider: () => audioBaseUrl,
  );

  final storage = await StorageService.create();
  final service = ParableService(storage, null, false, catalog);
  return (service: service, docs: docs);
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('Phase 2 / Slice 7 — R2 distribution integration', () {
    test(
        '1. Airplane mode + cached catalog: cache used for manifest, '
        'cached story audio plays, uncached reflection surfaces null', () async {
      const storyId = 'story_offline_001';
      const audioPath = 'traditional/9999/audio_9999_story_short.mp3';
      const reflectionPath =
          'traditional/9999/audio_9999_reflection.mp3';

      final cacheBody = _catalogJson(
        version: 2,
        parables: [
          _parableMap(
            storyId: storyId,
            audioFilePath: audioPath,
            reflectionAudioPath: reflectionPath,
          ),
        ],
      );

      final ctx = await _buildEnv(
        catalogHandler: (req) async =>
            throw const SocketException('airplane mode'),
        audioBaseUrl: 'http://0.0.0.0:1', // closed port
        primedCatalogBody: cacheBody,
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      // Pre-populate audio cache for the story file (Tier 1 hit).
      final cacheDir = await ctx.service.getAudioCacheDirForTesting();
      final cachedAudioFile = File('${cacheDir.path}/$audioPath');
      await cachedAudioFile.parent.create(recursive: true);
      await cachedAudioFile.writeAsBytes(sampleAudioBytes);

      // 1a — manifest comes from the cached catalog.
      final parables = await ctx.service.getAllTraditionalParables();
      expect(parables, hasLength(1));
      expect(parables.first.storyId, storyId);

      final manifestEvents = _breadcrumbsByEvent('manifest_source');
      expect(manifestEvents, hasLength(1));
      expect(manifestEvents.first.data['source'], 'cache');
      expect(manifestEvents.first.data['version'], 2);

      // 1b — story audio plays from the Tier 1 cache hit.
      final storyFile =
          await ctx.service.getAudioFileAndroidForTesting(parables.first);
      expect(storyFile, isNotNull);
      expect(storyFile!.path, cachedAudioFile.path);
      expect(await storyFile.readAsBytes(), sampleAudioBytes);

      // 1c — reflection is not cached, not bundled, network unreachable.
      // Service contract: resolver returns null. The widget maps this
      // null to the _reflectionUnavailable state (Slice 4).
      final reflectionFile = await ctx.service
          .getReflectionAudioFileAndroidForTesting(parables.first);
      expect(reflectionFile, isNull,
          reason: 'offline + uncached + unbundled → resolver must return null '
              '(widget surfaces "Connect to play")');
    });

    test(
        '2. Stale cache + fresh remote: launch 1 uses cached v1, '
        'background refresh writes v2, launch 2 uses cached v2', () async {
      const storyA = 'story_stale_v1';
      const storyB = 'story_fresh_v2';
      const audioA = 'traditional/9001/audio_9001_story_short.mp3';
      const audioB = 'traditional/9002/audio_9002_story_short.mp3';

      final cachedV1 = _catalogJson(
        version: 1,
        parables: [_parableMap(storyId: storyA, audioFilePath: audioA)],
      );
      final remoteV2 = _catalogJson(
        version: 2,
        parables: [
          _parableMap(storyId: storyA, audioFilePath: audioA),
          _parableMap(storyId: storyB, audioFilePath: audioB),
        ],
      );

      final ctx = await _buildEnv(
        catalogHandler: (req) async => http.Response(remoteV2, 200),
        audioBaseUrl: 'https://example.test', // unused; catalog is MockClient
        primedCatalogBody: cachedV1,
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      // Launch 1: cache served, v1.
      final launch1 = await ctx.service.getAllTraditionalParables();
      expect(launch1, hasLength(1));
      expect(launch1.first.storyId, storyA);

      var manifestEvents = _breadcrumbsByEvent('manifest_source');
      expect(manifestEvents, hasLength(1));
      expect(manifestEvents.first.data['source'], 'cache');
      expect(manifestEvents.first.data['version'], 1);

      // Poll for the background refresh to update the cache file to v2.
      final cacheFile =
          File('${ctx.docs.path}/catalog_cache/manifest.json');
      for (var i = 0; i < 50; i++) {
        final content = await cacheFile.readAsString();
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        if (decoded['version'] == 2) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final afterRefresh =
          jsonDecode(await cacheFile.readAsString()) as Map<String, dynamic>;
      expect(afterRefresh['version'], 2,
          reason: 'background refresh must have written v2 to cache');

      final refreshEvents = _breadcrumbsByEvent('catalog_refresh_accepted');
      expect(refreshEvents, hasLength(1));
      expect(refreshEvents.first.data['new_version'], 2);

      // Simulate next launch.
      ctx.service.resetManifestCacheForTesting();
      AppLogger.instance.clearBreadcrumbs();

      final launch2 = await ctx.service.getAllTraditionalParables();
      expect(launch2, hasLength(2));
      expect(launch2.map((p) => p.storyId), containsAll([storyA, storyB]));

      manifestEvents = _breadcrumbsByEvent('manifest_source');
      expect(manifestEvents, hasLength(1));
      expect(manifestEvents.first.data['source'], 'cache');
      expect(manifestEvents.first.data['version'], 2);
    });

    test(
        '3. Reflection cascade parity: story and reflection both cache-then-'
        'R2 with matching tier semantics and kind-tagged telemetry', () async {
      final fake = await startFakeAudioServer(body: sampleAudioBytes);
      addTearDown(() => fake.server.close(force: true));

      final ctx = await _buildEnv(
        // Catalog refresh is fire-and-forget; throw so it errors silently.
        catalogHandler: (req) async =>
            throw const SocketException('catalog unreachable in this test'),
        audioBaseUrl: fake.baseUrl,
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      // A parable with both paths not in pubspec — Tier 2 misses on both.
      final parable = testParable(
        storyId: 'story_parity_001',
        audioFilePath: 'traditional/9011/audio_9011_story_short.mp3',
        reflectionAudioPath:
            'traditional/9011/audio_9011_reflection.mp3',
      );
      final cacheDir = await ctx.service.getAudioCacheDirForTesting();
      final expectedStoryPath =
          '${cacheDir.path}/${parable.audioFilePath}';
      final expectedReflectionPath =
          '${cacheDir.path}/${parable.reflectionAudioPath}';

      // Round 1: nothing cached. Both go through Tier 3 (R2).
      final story1 =
          await ctx.service.getAudioFileAndroidForTesting(parable);
      final reflection1 = await ctx.service
          .getReflectionAudioFileAndroidForTesting(parable);

      expect(story1, isNotNull);
      expect(story1!.path, expectedStoryPath);
      expect(await story1.readAsBytes(), sampleAudioBytes);

      expect(reflection1, isNotNull);
      expect(reflection1!.path, expectedReflectionPath);
      expect(await reflection1.readAsBytes(), sampleAudioBytes);

      // audio_source telemetry distinguishes kind.
      final r2Events = _breadcrumbsByEvent('audio_source')
          .where((b) => b.data['source'] == 'r2')
          .toList();
      final r2Kinds =
          r2Events.map((b) => b.data['kind'] as String?).toSet();
      expect(r2Kinds, containsAll({'story', 'reflection'}),
          reason: 'both kinds must appear in audio_source breadcrumbs');

      // Round 2: both files should now be cached. Both must hit Tier 1.
      AppLogger.instance.clearBreadcrumbs();
      final story2 =
          await ctx.service.getAudioFileAndroidForTesting(parable);
      final reflection2 = await ctx.service
          .getReflectionAudioFileAndroidForTesting(parable);

      expect(story2!.path, expectedStoryPath);
      expect(reflection2!.path, expectedReflectionPath);

      final cacheEvents = _breadcrumbsByEvent('audio_source')
          .where((b) => b.data['source'] == 'cache')
          .toList();
      final cacheKinds =
          cacheEvents.map((b) => b.data['kind'] as String?).toSet();
      expect(cacheKinds, containsAll({'story', 'reflection'}),
          reason: 'cache-tier hits must also be tagged by kind');
    });

    test(
        '4. New-story-in-catalog smoke: a parable that exists only in the '
        'cached catalog is surfaced AND plays from R2', () async {
      const storyId = 'story_new_remote_only';
      const audioPath = 'traditional/9020/audio_9020_story_short.mp3';

      final cacheBody = _catalogJson(
        version: 2,
        parables: [
          _parableMap(storyId: storyId, audioFilePath: audioPath),
        ],
      );

      final fake = await startFakeAudioServer(body: sampleAudioBytes);
      addTearDown(() => fake.server.close(force: true));

      final ctx = await _buildEnv(
        // Refresh returns the same v2 body → CatalogService rejects on
        // version-not-higher so the cache is unchanged for the assertion.
        catalogHandler: (req) async => http.Response(cacheBody, 200),
        audioBaseUrl: fake.baseUrl,
        primedCatalogBody: cacheBody,
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      // 4a — the new parable surfaces via the manifest API.
      final parables = await ctx.service.getAllTraditionalParables();
      expect(parables, hasLength(1));
      expect(parables.first.storyId, storyId);
      expect(parables.first.audioFilePath, audioPath);

      final manifestEvents = _breadcrumbsByEvent('manifest_source');
      expect(manifestEvents, hasLength(1));
      expect(manifestEvents.first.data['source'], 'cache');
      expect(manifestEvents.first.data['version'], 2);

      // 4b — its audio plays via R2 (Tier 3 download, then cached).
      final audioFile =
          await ctx.service.getAudioFileAndroidForTesting(parables.first);
      expect(audioFile, isNotNull);
      expect(await audioFile!.readAsBytes(), sampleAudioBytes);

      final cacheDir = await ctx.service.getAudioCacheDirForTesting();
      expect(audioFile.path, '${cacheDir.path}/$audioPath',
          reason: 'downloaded audio must be cached at the canonical path');

      final r2Events = _breadcrumbsByEvent('audio_source')
          .where((b) =>
              b.data['source'] == 'r2' && b.data['story_id'] == storyId)
          .toList();
      expect(r2Events, hasLength(1));
      expect(r2Events.first.data['kind'], 'story');
    });
  });
}

// ─── Breadcrumb readout helper ───────────────────────────────────────────────
// Mirrors the small extension in parable_service_catalog_test.dart. Promoting
// to a shared helper isn't worth it for two re-uses; we'll consolidate if a
// third Phase-2 test ever needs it.

List<Breadcrumb> _breadcrumbsByEvent(String event) {
  return AppLogger.instance.getRecentBreadcrumbs().where((m) {
    return m['event'] == event;
  }).map((m) {
    return Breadcrumb(
      event: m['event'] as String,
      level:
          LogLevel.values.firstWhere((l) => l.name == (m['level'] as String)),
      timestamp: DateTime.parse(m['ts'] as String),
      data: Map.of(m)
        ..remove('event')
        ..remove('level')
        ..remove('ts'),
    );
  }).toList();
}
