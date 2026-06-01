// Phase 2 / Slice 2 integration tests for catalog wiring in
// ParableService. Verifies the cache → bundled cascade, the single
// `manifest_source` log emission per launch, fire-and-forget background
// refresh, and that offline-first behavior is preserved.

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
