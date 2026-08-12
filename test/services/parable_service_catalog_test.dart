// Phase 2 / Slice 2 integration tests for catalog wiring in
// ParableService. Verifies the cache → bundled cascade, the single
// `manifest_source` log emission per launch, fire-and-forget background
// refresh, and that offline-first behavior is preserved.

import 'dart:convert';
import 'dart:io';

import 'package:bible_pal/core/app_logger.dart';
import 'package:bible_pal/core/bible_translation_registry.dart';
import 'package:bible_pal/core/story_length_bucket.dart';
import 'package:bible_pal/features/journey/journey.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/services/catalog_service.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _parableMap({
  String storyId = 'story_catalog_test_001',
  String mood = 'joyful',
}) {
  return {
    'storyId': storyId,
    'title': 'Catalog Test Story',
    'mood': mood,
    'storytellingMode': 'traditional',
    'kidFriendly': false,
    'translationId': 'WEB',
    'languageStyle': 'WEB',
    'storyLength': 'short',
    'audioFilePath': 'traditional/9999/audio_9999_story_short.mp3',
    'textFilePath': 'traditional/9999/story_9999_traditional_web_short.txt',
    'bibleSourceRef': 'Matthew 1:1',
    'bibleStoryKey': 'catalog_test',
  };
}

String _catalogJson({
  required int version,
  required List<Map<String, dynamic>> parables,
}) =>
    jsonEncode({'version': version, 'parables': parables});

/// Builds a ParableService wired with an injected CatalogService that
/// reads its docs-dir from [docs], its bundled fallback from a fake
/// rootBundle alternative, and its http client from [handler].
Future<({ParableService service, Directory docs})> _buildService({
  required MockClientHandler handler,
  String? baseUrl = 'https://example.test',
  bool primeCache = false,
  String? cacheBody,
  Future<String> Function()? bundledLoader,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues({});
  AppLogger.instance.clearBreadcrumbs();

  final docs = await Directory.systemTemp.createTemp('bp_catalog_int_');

  // Mock path_provider so any code path that calls
  // getApplicationDocumentsDirectory() lands inside the temp dir.
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'getApplicationDocumentsDirectory':
        return docs.path;
      case 'getTemporaryDirectory':
        return docs.path;
      case 'getApplicationSupportDirectory':
        return docs.path;
      default:
        return null;
    }
  });

  dotenv.testLoad(
    fileInput: baseUrl == null ? '' : 'AUDIO_BASE_URL=$baseUrl',
  );

  if (primeCache && cacheBody != null) {
    final cacheFile = File('${docs.path}/catalog_cache/manifest.json');
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString(cacheBody);
  }

  final catalog = CatalogService(
    client: MockClient(handler),
    docsDirProvider: () async => docs,
    baseUrlProvider: () => baseUrl,
    bundledLoader: bundledLoader,
  );

  final storage = await StorageService.create();
  // testMode=false so the catalog cascade actually runs.
  final service = ParableService(storage, null, false, catalog);
  return (service: service, docs: docs);
}

List<Breadcrumb> _breadcrumbsByEvent(String event) {
  return AppLogger.instance
      ._breadcrumbsForTest()
      .where((b) => b.event == event)
      .toList();
}

void main() {
  group('ParableService catalog wiring (Slice 2)', () {
    test('cold launch with cached catalog uses cache', () async {
      final cacheBody = _catalogJson(
        version: 7,
        parables: [_parableMap(storyId: 'story_from_cache_001')],
      );
      final ctx = await _buildService(
        handler: (req) async => http.Response(cacheBody, 200),
        primeCache: true,
        cacheBody: cacheBody,
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final parables = await ctx.service.getAllTraditionalParables();
      // Allow the fire-and-forget background refresh to settle before we
      // assert on cache file state.
      await Future<void>.delayed(Duration.zero);

      expect(parables, isNotEmpty);
      expect(parables.any((p) => p.storyId == 'story_from_cache_001'),
          isTrue,
          reason: 'cached parable must be served, not bundled');

      final manifestSourceEvents = _breadcrumbsByEvent('manifest_source');
      expect(manifestSourceEvents, hasLength(1),
          reason: 'manifest_source must fire exactly once');
      expect(manifestSourceEvents.first.data['source'], 'cache');
      expect(manifestSourceEvents.first.data['version'], 7);
    });

    test('cold launch without cache uses bundled', () async {
      final ctx = await _buildService(
        handler: (req) async => http.Response('not reached', 500),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final parables = await ctx.service.getAllTraditionalParables();
      await Future<void>.delayed(Duration.zero);

      // Bundled manifest has many traditional parables; just confirm the
      // service returned a non-empty list — the exact count is unrelated
      // to Slice 2 behavior.
      expect(parables, isNotEmpty);
      final manifestSourceEvents = _breadcrumbsByEvent('manifest_source');
      expect(manifestSourceEvents, hasLength(1));
      expect(manifestSourceEvents.first.data['source'], 'bundled');
    });

    test(
        'second _loadManifest call within the launch reuses memoized result '
        '— manifest_source fires only once', () async {
      final ctx = await _buildService(
        handler: (req) async => http.Response('ignored', 500),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      await ctx.service.getAllTraditionalParables();
      await ctx.service.getAllTraditionalParables();
      await ctx.service.getAllTraditionalParables();

      final manifestSourceEvents = _breadcrumbsByEvent('manifest_source');
      expect(manifestSourceEvents, hasLength(1),
          reason: 'memoization must collapse repeat callers to one emission');
    });

    test('resetManifestCacheForTesting re-runs the cascade', () async {
      final ctx = await _buildService(
        handler: (req) async => http.Response('ignored', 500),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      await ctx.service.getAllTraditionalParables();
      ctx.service.resetManifestCacheForTesting();
      await ctx.service.getAllTraditionalParables();

      expect(_breadcrumbsByEvent('manifest_source'), hasLength(2));
    });

    test('remote fetch failure leaves bundled in place; no cache written',
        () async {
      var hits = 0;
      final ctx = await _buildService(
        handler: (req) async {
          hits++;
          throw const SocketException('boom');
        },
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final parables = await ctx.service.getAllTraditionalParables();
      // Drain the fire-and-forget refresh. CatalogService does one
      // attempt + one retry; both throw synchronously inside the http
      // future, so a microtask drain is enough.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(parables, isNotEmpty);
      expect(_breadcrumbsByEvent('manifest_source').first.data['source'],
          'bundled');
      expect(hits, greaterThanOrEqualTo(2),
          reason: 'background refresh must attempt + retry');
      final cacheFile =
          File('${ctx.docs.path}/catalog_cache/manifest.json');
      expect(await cacheFile.exists(), isFalse,
          reason: 'failed refresh must not write a cache file');
    });

    test('remote fetch success writes cache for next launch', () async {
      final remoteBody = _catalogJson(
        version: 12,
        parables: [_parableMap(storyId: 'story_from_remote_001')],
      );
      final ctx = await _buildService(
        handler: (req) async => http.Response(remoteBody, 200),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      // First launch: cache empty → bundled used. Background refresh
      // populates cache.
      final firstLaunch = await ctx.service.getAllTraditionalParables();
      expect(firstLaunch, isNotEmpty);
      expect(_breadcrumbsByEvent('manifest_source').first.data['source'],
          'bundled');

      // Wait for the fire-and-forget refresh to finish writing.
      // Poll briefly rather than fix a sleep — the http handler resolves
      // synchronously so this completes in a couple microtasks.
      final cacheFile =
          File('${ctx.docs.path}/catalog_cache/manifest.json');
      for (var i = 0; i < 50; i++) {
        if (await cacheFile.exists()) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(await cacheFile.exists(), isTrue,
          reason: 'background refresh should have written cache');
      expect(await cacheFile.readAsString(), remoteBody);

      // Simulate next launch: reset memoization. Catalog now reads cache.
      ctx.service.resetManifestCacheForTesting();
      AppLogger.instance.clearBreadcrumbs();
      final secondLaunch = await ctx.service.getAllTraditionalParables();
      expect(secondLaunch.any((p) => p.storyId == 'story_from_remote_001'),
          isTrue,
          reason: 'second launch must serve the cached remote parable');
      expect(_breadcrumbsByEvent('manifest_source').first.data['source'],
          'cache');
      expect(_breadcrumbsByEvent('manifest_source').first.data['version'],
          12);
    });

    test(
        'downgrade-proofing: stale cached v5 catalog is superseded by the '
        'bundled v6 manifest and deleted', () async {
      // Regression test for the private-beta blocker: a cached older R2
      // catalog (v5, tiny pool) must never shrink the story pool below the
      // newer bundled manifest (v6, full pool).
      final staleCache = _catalogJson(
        version: 5,
        parables: [_parableMap(storyId: 'story_stale_pool_001')],
      );
      final ctx = await _buildService(
        handler: (req) async => http.Response('ignored', 500),
        primeCache: true,
        cacheBody: staleCache,
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final parables = await ctx.service.getAllTraditionalParables();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(parables.any((p) => p.storyId == 'story_stale_pool_001'),
          isFalse,
          reason: 'the stale cached pool must not be served over the bundle');
      final manifestEvents = _breadcrumbsByEvent('manifest_source');
      expect(manifestEvents, hasLength(1));
      expect(manifestEvents.first.data['source'], 'bundled');
      expect(manifestEvents.first.data['version'], 6,
          reason: 'bundled manifest must carry catalog generation 6');

      final cacheFile =
          File('${ctx.docs.path}/catalog_cache/manifest.json');
      expect(await cacheFile.exists(), isFalse,
          reason: 'stale cache must be deleted after the bundle is served');
    });

    test(
        'downgrade-proofing: first launch with remote v5 older than bundled '
        'v6 → remote rejected, no cache written', () async {
      final staleRemote = _catalogJson(
        version: 5,
        parables: [_parableMap(storyId: 'story_stale_remote_001')],
      );
      final ctx = await _buildService(
        handler: (req) async => http.Response(staleRemote, 200),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final parables = await ctx.service.getAllTraditionalParables();
      // Drain the fire-and-forget refresh.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(parables, isNotEmpty);
      expect(_breadcrumbsByEvent('manifest_source').first.data['source'],
          'bundled');

      final rejections = _breadcrumbsByEvent('catalog_refresh_rejected');
      expect(rejections, hasLength(1),
          reason: 'the v5 remote must be version-rejected against bundled v6');
      expect(rejections.first.data['reason'], 'version_not_higher');
      expect(_breadcrumbsByEvent('catalog_refresh_accepted'), isEmpty);

      final cacheFile =
          File('${ctx.docs.path}/catalog_cache/manifest.json');
      expect(await cacheFile.exists(), isFalse,
          reason: 'a rejected remote must never be persisted');
    });
  });

  group('ParableService fails closed when CatalogService rejects', () {
    // The legacy fallback re-read assets/stories/manifest.json with a bare
    // Parable.fromJson and NONE of the catalog gates — so a bundled
    // catalog that CatalogService refused (banned translation, unsafe
    // path, duplicate ids …) was served anyway, one layer down. An empty
    // pool is the correct outcome; the rejection is authoritative.

    test('a bundled catalog carrying a banned translation yields NO stories',
        () async {
      // Pull a banned id from the registry rather than hard-coding a
      // literal so this file does not trip the repo-wide compliance scan.
      final bannedId = BibleTranslationRegistry.bannedTranslations.first.id;
      final poisoned = _catalogJson(
        version: 6,
        parables: [
          {
            ..._parableMap(storyId: 'story_poisoned_001'),
            'translationId': bannedId,
          },
        ],
      );
      final ctx = await _buildService(
        handler: (req) async =>
            throw StateError('network must not be touched'),
        bundledLoader: () async => poisoned,
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final parables = await ctx.service.getAllTraditionalParables();

      expect(parables, isEmpty,
          reason: 'a rejected catalog must never be served by a lower '
              'layer that skips the compliance allowlist');
      final loaded = _breadcrumbsByEvent('story_pool_loaded');
      expect(loaded, isNotEmpty);
      expect(loaded.last.data['source'], 'catalog_rejected_fail_closed');
      expect(loaded.last.data['valid_count'], 0);
    });

    // Journey rescue re-reads BUNDLED entries because the served catalog
    // may be a cache that predates them. It used to do that with
    // rootBundle + jsonDecode + bare Parable.fromJson — every
    // CatalogService gate skipped, including the translation allowlist —
    // so a catalog rejected one layer up could be resurrected here.
    Future<Parable?> rescueAdult(ParableService service) =>
        service.getParableByJourneyStory(
          const JourneyStory(storyNumber: 1000, label: 'Rescue Probe'),
          lengthBucket: StoryLengthBucket.short,
          userPrefs: const UserPreferences(bibleTranslation: 'WEB'),
        );

    Future<Parable?> rescueKid(ParableService service) =>
        service.getParableByJourneyStory(
          const JourneyStory(anchorId: 'jairus_daughter', label: 'Kid Probe'),
          lengthBucket: StoryLengthBucket.short,
          userPrefs: const UserPreferences(bibleTranslation: 'WEB'),
        );

    test('ADULT journey rescue does not resurrect a poisoned bundle',
        () async {
      final bannedId = BibleTranslationRegistry.bannedTranslations.first.id;
      final poisoned = _catalogJson(
        version: 6,
        parables: [
          {
            ..._parableMap(storyId: 'story_1000_weary_short_traditional'),
            'translationId': bannedId,
          },
        ],
      );
      final ctx = await _buildService(
        handler: (req) async =>
            throw StateError('network must not be touched'),
        bundledLoader: () async => poisoned,
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      expect(await rescueAdult(ctx.service), isNull,
          reason: 'the rescue path must not serve an entry from a catalog '
              'CatalogService rejected');
      final failures =
          _breadcrumbsByEvent('journey_bundled_rescue_failed');
      expect(failures, isNotEmpty);
      expect(failures.last.data['reason'], 'bundled_catalog_rejected');
      expect(_breadcrumbsByEvent('journey_bundled_rescue'), isEmpty);
    });

    test('KID journey rescue does not resurrect a poisoned bundle', () async {
      final bannedId = BibleTranslationRegistry.bannedTranslations.first.id;
      final poisoned = _catalogJson(
        version: 6,
        parables: [
          {
            ..._parableMap(storyId: 'kidstory_kid_jairus_daughter_short'),
            'kidFriendly': true,
            'translationId': bannedId,
          },
        ],
      );
      final ctx = await _buildService(
        handler: (req) async =>
            throw StateError('network must not be touched'),
        bundledLoader: () async => poisoned,
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      expect(await rescueKid(ctx.service), isNull,
          reason: 'the kid rescue must not be the one door an unvalidated '
              "catalog uses to reach children's content");
      final failures =
          _breadcrumbsByEvent('journey_kid_bundled_rescue_failed');
      expect(failures, isNotEmpty);
      expect(failures.last.data['reason'], 'bundled_catalog_rejected');
      expect(_breadcrumbsByEvent('journey_kid_bundled_rescue'), isEmpty);
    });

    test('journey rescue still works from a VALID bundle', () async {
      // Fail-closed must not become fail-dark: a clean bundled catalog
      // still rescues a story the served (cached) catalog lacks.
      final bundled = _catalogJson(
        version: 6,
        parables: [
          _parableMap(storyId: 'story_1000_weary_short_traditional'),
        ],
      );
      // Cache is VALID but newer and lacks story 9999, so the served
      // catalog cannot satisfy the journey and rescue must run.
      final cacheBody = _catalogJson(
        version: 9,
        parables: [_parableMap(storyId: 'story_2000_other_short_traditional')],
      );
      final ctx = await _buildService(
        handler: (req) async =>
            throw StateError('network must not be touched'),
        bundledLoader: () async => bundled,
        primeCache: true,
        cacheBody: cacheBody,
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final resolved = await rescueAdult(ctx.service);

      expect(resolved, isNotNull,
          reason: 'a valid bundled catalog must still rescue');
      expect(resolved!.storyId, 'story_1000_weary_short_traditional');
      expect(_breadcrumbsByEvent('journey_bundled_rescue'), isNotEmpty);
    });

    test('an unusable bundled catalog with a VALID cache still serves the cache',
        () async {
      // Fail-closed must not become fail-dark: the emergency cache path
      // is unaffected.
      final cacheBody = _catalogJson(
        version: 9,
        parables: [_parableMap(storyId: 'story_emergency_cache')],
      );
      final ctx = await _buildService(
        handler: (req) async =>
            throw StateError('network must not be touched'),
        bundledLoader: () async => 'not json at all',
        primeCache: true,
        cacheBody: cacheBody,
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final parables = await ctx.service.getAllTraditionalParables();

      expect(parables, hasLength(1));
      expect(parables.first.storyId, 'story_emergency_cache');
    });
  });
}

// AppLogger doesn't expose its breadcrumb queue directly; reach in via
// the public getRecentBreadcrumbs() result, re-hydrating Breadcrumb
// objects for type-safe filtering in tests.
extension _BreadcrumbReadout on AppLogger {
  List<Breadcrumb> _breadcrumbsForTest() {
    return getRecentBreadcrumbs().map((m) {
      return Breadcrumb(
        event: m['event'] as String,
        level: LogLevel.values
            .firstWhere((l) => l.name == (m['level'] as String)),
        timestamp: DateTime.parse(m['ts'] as String),
        data: Map.of(m)
          ..remove('event')
          ..remove('level')
          ..remove('ts'),
      );
    }).toList();
  }
}
