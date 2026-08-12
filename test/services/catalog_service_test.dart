// Unit tests for CatalogService.
//
// Phase 2 / Slice 1 scenarios (success, schema rejection, banned-translation
// rejection, oversized rejection, version-not-higher rejection, network
// failure) plus the Catalog Currency & Downgrade-Proofing milestone:
// bundled-first selection, fail-closed bundled version handling, emergency
// cache fallback, strict version floors, persistence-failure containment,
// refresh deduplication, and timeout behavior.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bible_pal/core/app_logger.dart';
import 'package:bible_pal/core/bible_translation_registry.dart';
import 'package:bible_pal/services/catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Minimal valid parable map for catalog tests. Satisfies the full active
/// catalog contract (identity, active mode, canonical translation values,
/// safe relative serving anchors) — not merely `Parable.fromJson`.
Map<String, dynamic> _parable({
  String storyId = 'story_test_001',
  String translationId = 'WEB',
  String languageStyle = 'WEB',
}) {
  return {
    'storyId': storyId,
    'title': 'Test Story',
    'mood': 'joyful',
    'storytellingMode': 'traditional',
    'kidFriendly': false,
    'translationId': translationId,
    'languageStyle': languageStyle,
    'storyLength': 'short',
    'audioFilePath': 'traditional/9999/audio_9999_story_short.mp3',
    'textFilePath': 'traditional/9999/story_9999_traditional_web_short.txt',
  };
}

String _catalogJson({
  required int version,
  required List<Map<String, dynamic>> parables,
}) =>
    jsonEncode({'version': version, 'parables': parables});

/// Default bundled fixture: a valid catalog at generation 1.
String _bundledV1() => _catalogJson(
      version: 1,
      parables: [_parable(storyId: 'story_bundled_001')],
    );

/// Builds a fresh CatalogService backed by a temp docs dir and a
/// MockClient that returns the given handler's response.
({CatalogService service, Directory docs}) _buildService({
  required MockClientHandler handler,
  String? baseUrl = 'https://example.test',
  int maxBodyBytes = CatalogService.defaultMaxBodyBytes,
  String? bundledJson,
  Future<String> Function()? bundledLoader,
  Future<Directory> Function()? docsDirProvider,
  Duration fetchTimeout = CatalogService.defaultFetchTimeout,
}) {
  final docs = Directory.systemTemp.createTempSync('bp_catalog_test_');
  final service = CatalogService(
    client: MockClient(handler),
    docsDirProvider: docsDirProvider ?? (() async => docs),
    bundledLoader: bundledLoader ?? (() async => bundledJson ?? _bundledV1()),
    baseUrlProvider: () => baseUrl,
    maxBodyBytes: maxBodyBytes,
    fetchTimeout: fetchTimeout,
  );
  return (service: service, docs: docs);
}

File _cacheFile(Directory docs) =>
    File('${docs.path}/catalog_cache/manifest.json');

Future<void> _primeCache(Directory docs, String body) async {
  final cache = _cacheFile(docs);
  await cache.parent.create(recursive: true);
  await cache.writeAsString(body);
}

List<Map<String, dynamic>> _events(String name) => AppLogger.instance
    .getRecentBreadcrumbs()
    .where((m) => m['event'] == name)
    .toList();

http.Response _unreachable(http.Request req) =>
    throw StateError('network must not be touched in this test');

/// A response shaped like the real R2 object: raw UTF-8 bytes served as
/// `application/json` with NO charset parameter.
///
/// `http.Response(String, …)` encodes with the charset from the headers
/// and falls back to LATIN-1, so it cannot even represent a non-ASCII
/// catalog — using it as the test double hid the fact that
/// `response.body` would mojibake the real corpus.
http.Response _jsonBytes(String body, {String? contentType}) =>
    http.Response.bytes(
      utf8.encode(body),
      200,
      headers: {'content-type': contentType ?? 'application/json'},
    );

void main() {
  setUp(() {
    AppLogger.instance.clearBreadcrumbs();
  });

  group('CatalogService.refreshFromRemote', () {
    test('success: accepts valid remote catalog and writes cache atomically',
        () async {
      final body = _catalogJson(version: 2, parables: [_parable()]);
      final ctx = _buildService(
        handler: (req) async => http.Response(body, 200),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.accepted);
      expect(result.newVersion, 2);
      expect(result.entryCount, 1);

      final cached = _cacheFile(ctx.docs);
      expect(await cached.exists(), isTrue);
      expect(await cached.readAsString(), body);

      // Atomic-write contract: no stray .tmp left behind.
      final tmp = File('${cached.path}.tmp');
      expect(await tmp.exists(), isFalse);
    });

    test('schema rejection: missing "parables" list', () async {
      final body = jsonEncode({'version': 2, 'notparables': []});
      final ctx = _buildService(
        handler: (req) async => http.Response(body, 200),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.rejectedSchema);
      expect(await _cacheFile(ctx.docs).exists(), isFalse);
    });

    test('schema rejection: empty "parables" list must not replace bundle',
        () async {
      final body = jsonEncode({'version': 99, 'parables': []});
      final ctx = _buildService(
        handler: (req) async => http.Response(body, 200),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.rejectedSchema);
      expect(await _cacheFile(ctx.docs).exists(), isFalse);
    });

    test('banned-translation rejection: copyrighted translationId in any entry',
        () async {
      // Pull a banned id from the registry rather than hard-coding a literal
      // so this test file does not trip repo_wide_compliance_scan_test.dart.
      final bannedId = BibleTranslationRegistry.bannedTranslations.first.id;
      final body = _catalogJson(
        version: 2,
        parables: [_parable(translationId: bannedId)],
      );
      final ctx = _buildService(
        handler: (req) async => http.Response(body, 200),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.rejectedTranslation);
      expect(await _cacheFile(ctx.docs).exists(), isFalse);
    });

    test('oversized rejection: body exceeds maxBodyBytes', () async {
      final body = _catalogJson(version: 2, parables: [_parable()]);
      // Lower the size cap below the response body so the gate trips
      // without having to build a real 5 MB payload.
      final ctx = _buildService(
        handler: (req) async => http.Response(body, 200),
        maxBodyBytes: 16,
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.rejectedOversize);
      expect(await _cacheFile(ctx.docs).exists(), isFalse);
    });

    test('version-not-higher rejection: remote v == cached v', () async {
      final body = _catalogJson(version: 5, parables: [_parable()]);
      final ctx = _buildService(
        handler: (req) async => http.Response(body, 200),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      // Prime the cache with the same version.
      await _primeCache(ctx.docs, body);

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.rejectedVersion);
      expect(result.newVersion, 5);
      // Cache untouched.
      expect(await _cacheFile(ctx.docs).readAsString(), body);
    });

    test('network failure: both attempts throw → networkFailure', () async {
      var attemptCount = 0;
      final ctx = _buildService(
        handler: (req) async {
          attemptCount++;
          throw const SocketException('connection refused');
        },
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.networkFailure);
      // One retry on transient failure → exactly 2 attempts.
      expect(attemptCount, 2);
      expect(await _cacheFile(ctx.docs).exists(), isFalse);
    });
  });

  group('CatalogService.loadCatalog — bundled-first selection', () {
    String bundledV5() => _catalogJson(
          version: 5,
          parables: [_parable(storyId: 'story_bundled_001')],
        );

    test('no cache → bundled', () async {
      final ctx = _buildService(
        handler: (req) async => _unreachable(req),
        bundledJson: bundledV5(),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final result = await ctx.service.loadCatalog();

      expect(result.source, CatalogSource.bundled);
      expect(result.version, 5);
      expect(result.parables.single.storyId, 'story_bundled_001');
    });

    test('cache B-1 → bundled; stale cache deleted', () async {
      final ctx = _buildService(
        handler: (req) async => _unreachable(req),
        bundledJson: bundledV5(),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));
      await _primeCache(
        ctx.docs,
        _catalogJson(
          version: 4,
          parables: [_parable(storyId: 'story_cache_001')],
        ),
      );

      final result = await ctx.service.loadCatalog();

      expect(result.source, CatalogSource.bundled);
      expect(result.version, 5);
      expect(await _cacheFile(ctx.docs).exists(), isFalse,
          reason: 'stale cache must be deleted after bundle is established');
    });

    test('cache B (equal) → bundled; cache deleted', () async {
      final ctx = _buildService(
        handler: (req) async => _unreachable(req),
        bundledJson: bundledV5(),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));
      await _primeCache(
        ctx.docs,
        _catalogJson(
          version: 5,
          parables: [_parable(storyId: 'story_cache_001')],
        ),
      );

      final result = await ctx.service.loadCatalog();

      expect(result.source, CatalogSource.bundled,
          reason: 'equality is never an update — strict > only');
      expect(await _cacheFile(ctx.docs).exists(), isFalse);
    });

    test('cache B+1 → cache served, cache preserved', () async {
      final ctx = _buildService(
        handler: (req) async => _unreachable(req),
        bundledJson: bundledV5(),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));
      await _primeCache(
        ctx.docs,
        _catalogJson(
          version: 6,
          parables: [_parable(storyId: 'story_cache_001')],
        ),
      );

      final result = await ctx.service.loadCatalog();

      expect(result.source, CatalogSource.cache);
      expect(result.version, 6);
      expect(result.parables.single.storyId, 'story_cache_001');
      expect(await _cacheFile(ctx.docs).exists(), isTrue);
    });

    for (final (label, cacheBody) in [
      ('missing version', jsonEncode({
        'parables': [_parable(storyId: 'story_cache_001')]
      })),
      ('wrong-type version (string)', jsonEncode({
        'version': '7',
        'parables': [_parable(storyId: 'story_cache_001')]
      })),
      ('wrong-type version (bool)', jsonEncode({
        'version': true,
        'parables': [_parable(storyId: 'story_cache_001')]
      })),
      ('zero version', jsonEncode({
        'version': 0,
        'parables': [_parable(storyId: 'story_cache_001')]
      })),
      ('negative version', jsonEncode({
        'version': -2,
        'parables': [_parable(storyId: 'story_cache_001')]
      })),
      ('malformed JSON', 'not json at all {{{'),
    ]) {
      test('cache with $label → bundled; cache deleted', () async {
        final ctx = _buildService(
          handler: (req) async => _unreachable(req),
          bundledJson: bundledV5(),
        );
        addTearDown(() => ctx.docs.deleteSync(recursive: true));
        await _primeCache(ctx.docs, cacheBody);

        final result = await ctx.service.loadCatalog();

        expect(result.source, CatalogSource.bundled);
        expect(result.version, 5);
        expect(await _cacheFile(ctx.docs).exists(), isFalse,
            reason: 'invalid cache must be deleted best-effort');
      });
    }

    test('cache with banned translation → bundled; cache deleted', () async {
      final bannedId = BibleTranslationRegistry.bannedTranslations.first.id;
      final ctx = _buildService(
        handler: (req) async => _unreachable(req),
        bundledJson: bundledV5(),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));
      await _primeCache(
        ctx.docs,
        _catalogJson(
          version: 9,
          parables: [_parable(translationId: bannedId)],
        ),
      );

      final result = await ctx.service.loadCatalog();

      expect(result.source, CatalogSource.bundled);
      expect(await _cacheFile(ctx.docs).exists(), isFalse);
    });

    test('cache deletion failure is logged and still returns bundled',
        () async {
      final ctx = _buildService(
        handler: (req) async => _unreachable(req),
        bundledJson: bundledV5(),
      );
      // Stale-but-valid cache (Vc == B) that cannot be deleted: parent dir
      // made read+traverse only.
      await _primeCache(
        ctx.docs,
        _catalogJson(
          version: 5,
          parables: [_parable(storyId: 'story_cache_001')],
        ),
      );
      final cacheDir = _cacheFile(ctx.docs).parent;
      await Process.run('chmod', ['555', cacheDir.path]);
      addTearDown(() async {
        await Process.run('chmod', ['755', cacheDir.path]);
        ctx.docs.deleteSync(recursive: true);
      });

      final result = await ctx.service.loadCatalog();

      expect(result.source, CatalogSource.bundled,
          reason: 'deletion failure must not affect the selected catalog');
      expect(result.version, 5);
      expect(await _cacheFile(ctx.docs).exists(), isTrue,
          reason: 'file survives because deletion failed');
      expect(_events('catalog_cache_delete_failed'), isNotEmpty,
          reason: 'deletion failure must be logged');
    });
  });

  group('CatalogService — bundled version invalid (fail closed)', () {
    for (final (label, bundledBody, reason) in [
      (
        'absent',
        jsonEncode({
          'parables': [_parable(storyId: 'story_bundled_001')]
        }),
        'missing',
      ),
      (
        'wrong type (string)',
        jsonEncode({
          'version': '6',
          'parables': [_parable(storyId: 'story_bundled_001')]
        }),
        'wrong_type',
      ),
      (
        'wrong type (bool)',
        jsonEncode({
          'version': true,
          'parables': [_parable(storyId: 'story_bundled_001')]
        }),
        'wrong_type',
      ),
      (
        'non-positive',
        jsonEncode({
          'version': 0,
          'parables': [_parable(storyId: 'story_bundled_001')]
        }),
        'non_positive',
      ),
    ]) {
      test(
          'bundled version $label → bundled served, cache preserved and NOT '
          'served, remote refresh disabled, warning emitted', () async {
        final remoteBody = _catalogJson(version: 50, parables: [_parable()]);
        final ctx = _buildService(
          handler: (req) async => http.Response(remoteBody, 200),
          bundledJson: bundledBody,
        );
        addTearDown(() => ctx.docs.deleteSync(recursive: true));

        // A fully valid, newer-looking cache exists — its relative currency
        // is unknowable without a trusted B, so it must be preserved but
        // NOT served.
        final cacheBody = _catalogJson(
          version: 9,
          parables: [_parable(storyId: 'story_cache_001')],
        );
        await _primeCache(ctx.docs, cacheBody);

        final result = await ctx.service.loadCatalog();

        expect(result.source, CatalogSource.bundled);
        expect(result.version, isNull);
        expect(result.parables.single.storyId, 'story_bundled_001');

        final warnings = _events('catalog_bundled_version_invalid');
        expect(warnings, hasLength(1),
            reason: 'structured warning must be emitted');
        expect(warnings.single['reason'], reason);

        // External replacement is latched off for this instance.
        final refresh = await ctx.service.refreshFromRemote();
        expect(refresh.outcome,
            CatalogRefreshOutcome.disabledExternalReplacement);

        // Cache preserved byte-for-byte.
        expect(await _cacheFile(ctx.docs).readAsString(), cacheBody);
      });
    }

    test(
        'refreshFromRemote called first (no prior loadCatalog) with invalid '
        'bundled version → disabled, nothing fetched, nothing written',
        () async {
      var fetches = 0;
      final ctx = _buildService(
        handler: (req) async {
          fetches++;
          return http.Response(
            _catalogJson(version: 50, parables: [_parable()]),
            200,
          );
        },
        bundledJson: jsonEncode({
          'parables': [_parable(storyId: 'story_bundled_001')]
        }),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final refresh = await ctx.service.refreshFromRemote();

      expect(
          refresh.outcome, CatalogRefreshOutcome.disabledExternalReplacement);
      expect(fetches, 0,
          reason: 'no trusted baseline → remote must not even be fetched');
      expect(await _cacheFile(ctx.docs).exists(), isFalse);
    });
  });

  group('CatalogService — bundled content failure (emergency path)', () {
    test(
        'bundle unreadable + fully valid cache → cache emergency fallback, '
        'cache preserved, remote disabled', () async {
      final cacheBody = _catalogJson(
        version: 3,
        parables: [_parable(storyId: 'story_cache_001')],
      );
      final ctx = _buildService(
        handler: (req) async =>
            http.Response(_catalogJson(version: 50, parables: [_parable()]),
                200),
        bundledLoader: () async => throw StateError('asset missing'),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));
      await _primeCache(ctx.docs, cacheBody);

      final result = await ctx.service.loadCatalog();

      expect(result.source, CatalogSource.cache);
      expect(result.version, 3);
      expect(result.parables.single.storyId, 'story_cache_001');
      expect(await _cacheFile(ctx.docs).readAsString(), cacheBody,
          reason: 'emergency path must preserve the cache');

      final refresh = await ctx.service.refreshFromRemote();
      expect(
          refresh.outcome, CatalogRefreshOutcome.disabledExternalReplacement,
          reason: 'no trusted bundled watermark → remote advancement off');
    });

    test('bundle with empty parables is content-invalid → emergency cache',
        () async {
      final cacheBody = _catalogJson(
        version: 1,
        parables: [_parable(storyId: 'story_cache_001')],
      );
      final ctx = _buildService(
        handler: (req) async => _unreachable(req),
        bundledJson: jsonEncode({'version': 6, 'parables': []}),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));
      await _primeCache(ctx.docs, cacheBody);

      final result = await ctx.service.loadCatalog();

      expect(result.source, CatalogSource.cache);
      expect(result.version, 1);
    });

    test(
        'bundle unreadable + invalid cache → loadCatalog throws (existing '
        'ParableService fallback path operates); cache not deleted', () async {
      final invalidCache = jsonEncode({
        // No version → not fully valid → unusable for emergency fallback.
        'parables': [_parable(storyId: 'story_cache_001')]
      });
      final ctx = _buildService(
        handler: (req) async => _unreachable(req),
        bundledLoader: () async => 'not json {{{',
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));
      await _primeCache(ctx.docs, invalidCache);

      await expectLater(ctx.service.loadCatalog(), throwsA(isA<StateError>()));
      expect(await _cacheFile(ctx.docs).readAsString(), invalidCache,
          reason: 'cache must never be deleted before the bundle is proven '
              'usable — and here it never was');
    });
  });

  group('CatalogService.refreshFromRemote — version floor', () {
    String bundledV6() => _catalogJson(
          version: 6,
          parables: [_parable(storyId: 'story_bundled_001')],
        );

    test('remote B-1 → rejectedVersion', () async {
      final ctx = _buildService(
        handler: (req) async => http.Response(
            _catalogJson(version: 5, parables: [_parable()]), 200),
        bundledJson: bundledV6(),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.rejectedVersion);
      expect(await _cacheFile(ctx.docs).exists(), isFalse);
    });

    test('remote B (equal) → rejectedVersion', () async {
      final ctx = _buildService(
        handler: (req) async => http.Response(
            _catalogJson(version: 6, parables: [_parable()]), 200),
        bundledJson: bundledV6(),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.rejectedVersion);
      expect(await _cacheFile(ctx.docs).exists(), isFalse);
    });

    test('remote B+1 → accepted', () async {
      final body = _catalogJson(version: 7, parables: [_parable()]);
      final ctx = _buildService(
        handler: (req) async => http.Response(body, 200),
        bundledJson: bundledV6(),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.accepted);
      expect(result.newVersion, 7);
      expect(await _cacheFile(ctx.docs).readAsString(), body);
    });

    for (final (label, versionValue) in <(String, Object?)>[
      ('absent', null),
      ('wrong type (string)', '9'),
      ('wrong type (bool)', true),
      ('zero', 0),
      ('negative', -1),
    ]) {
      test('remote version $label → rejectedSchema', () async {
        final map = <String, dynamic>{
          'parables': [_parable()],
        };
        if (versionValue != null) map['version'] = versionValue;
        final ctx = _buildService(
          handler: (req) async => http.Response(jsonEncode(map), 200),
          bundledJson: bundledV6(),
        );
        addTearDown(() => ctx.docs.deleteSync(recursive: true));

        final result = await ctx.service.refreshFromRemote();

        expect(result.outcome, CatalogRefreshOutcome.rejectedSchema);
        expect(await _cacheFile(ctx.docs).exists(), isFalse);
      });
    }

    test(
        'equal-version remote with DIFFERENT payload is a collision → '
        'rejected, cache not overwritten', () async {
      final cacheBody = _catalogJson(
        version: 8,
        parables: [_parable(storyId: 'story_cache_001')],
      );
      final collidingRemote = _catalogJson(
        version: 8,
        parables: [_parable(storyId: 'story_other_001')],
      );
      final ctx = _buildService(
        handler: (req) async => http.Response(collidingRemote, 200),
        bundledJson: bundledV6(),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));
      await _primeCache(ctx.docs, cacheBody);

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.rejectedVersion);
      expect(await _cacheFile(ctx.docs).readAsString(), cacheBody,
          reason: 'a version collision must never overwrite the cache');
    });

    test(
        'malformed cache with a huge claimed version cannot poison the '
        'remote watermark', () async {
      // Cache claims version 999 but contains a banned translation, so it
      // is NOT fully valid and must contribute nothing to the floor.
      final bannedId = BibleTranslationRegistry.bannedTranslations.first.id;
      final poisoned = _catalogJson(
        version: 999,
        parables: [_parable(translationId: bannedId)],
      );
      final remoteBody = _catalogJson(version: 7, parables: [_parable()]);
      final ctx = _buildService(
        handler: (req) async => http.Response(remoteBody, 200),
        bundledJson: bundledV6(),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));
      await _primeCache(ctx.docs, poisoned);

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.accepted,
          reason: 'floor must be max(B, fully-valid Vc) = 6, so 7 passes');
      expect(await _cacheFile(ctx.docs).readAsString(), remoteBody);
    });

    test('fully valid cache raises the floor above B', () async {
      // B=6, valid cache v9 → remote v8 must be rejected even though 8 > B.
      final cacheBody = _catalogJson(
        version: 9,
        parables: [_parable(storyId: 'story_cache_001')],
      );
      final ctx = _buildService(
        handler: (req) async => http.Response(
            _catalogJson(version: 8, parables: [_parable()]), 200),
        bundledJson: bundledV6(),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));
      await _primeCache(ctx.docs, cacheBody);

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.rejectedVersion);
      expect(await _cacheFile(ctx.docs).readAsString(), cacheBody);
    });
  });

  group('CatalogService — cache size cap (maxBodyBytes)', () {
    // Small injected cap so fixtures stay tiny. Remote/cache bodies in
    // these tests are sized relative to it.
    const cap = 600;

    String oversizedCacheBody({required int version}) => jsonEncode({
          'version': version,
          'parables': [_parable(storyId: 'story_cache_001')],
          'pad': 'x' * cap,
        });

    test(
        'oversized cache claiming a huge version cannot be served → '
        'bundled, cache deleted after fallback established', () async {
      final ctx = _buildService(
        handler: (req) async => _unreachable(req),
        bundledJson: _catalogJson(
          version: 5,
          parables: [_parable(storyId: 'story_bundled_001')],
        ),
        maxBodyBytes: cap,
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));
      await _primeCache(ctx.docs, oversizedCacheBody(version: 999));

      final result = await ctx.service.loadCatalog();

      expect(result.source, CatalogSource.bundled);
      expect(result.version, 5);
      expect(
        _events('catalog_cache_invalid')
            .where((e) => e['reason'] == 'oversized'),
        isNotEmpty,
        reason: 'oversized cache must be classified invalid with a '
            'structured reason',
      );
      expect(await _cacheFile(ctx.docs).exists(), isFalse,
          reason: 'invalid (oversized) cache is deleted best-effort after '
              'the bundled fallback is established');
    });

    test('oversized cache cannot poison the remote watermark', () async {
      final remoteBody = _catalogJson(version: 7, parables: [_parable()]);
      final ctx = _buildService(
        handler: (req) async => http.Response(remoteBody, 200),
        bundledJson: _catalogJson(
          version: 6,
          parables: [_parable(storyId: 'story_bundled_001')],
        ),
        maxBodyBytes: cap,
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));
      await _primeCache(ctx.docs, oversizedCacheBody(version: 999));

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.accepted,
          reason: 'floor must be max(B=6, no valid Vc) so remote v7 passes '
              '— the oversized cache contributes nothing');
      expect(await _cacheFile(ctx.docs).readAsString(), remoteBody);
    });

    test('size gate runs before the cache is read or parsed', () async {
      // Oversized AND unparseable: if the implementation parsed first this
      // would surface as a read/parse failure, not an oversized rejection.
      final ctx = _buildService(
        handler: (req) async => _unreachable(req),
        bundledJson: _catalogJson(
          version: 5,
          parables: [_parable(storyId: 'story_bundled_001')],
        ),
        maxBodyBytes: cap,
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));
      await _primeCache(ctx.docs, 'not json ${'x' * cap}');

      final result = await ctx.service.loadCatalog();

      expect(result.source, CatalogSource.bundled);
      expect(
        _events('catalog_cache_invalid')
            .where((e) => e['reason'] == 'oversized'),
        isNotEmpty,
      );
      // Rejected on size alone: never read, never parsed. The only
      // classification emitted is the size one — no parse failure and no
      // indeterminate-read report.
      expect(
        _events('catalog_cache_invalid')
            .where((e) => e['reason'] == 'parse_error'),
        isEmpty,
        reason: 'the oversized cache must be rejected on size alone, '
            'never read or parsed',
      );
      expect(_events('catalog_cache_read_indeterminate'), isEmpty);
    });

    test(
        'bundle failure + oversized cache → NOT a valid emergency fallback; '
        'loadCatalog throws and the cache is not deleted', () async {
      final oversized = oversizedCacheBody(version: 3);
      final ctx = _buildService(
        handler: (req) async => _unreachable(req),
        bundledLoader: () async => throw StateError('asset missing'),
        maxBodyBytes: cap,
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));
      await _primeCache(ctx.docs, oversized);

      await expectLater(ctx.service.loadCatalog(), throwsA(isA<StateError>()));
      expect(await _cacheFile(ctx.docs).readAsString(), oversized,
          reason: 'emergency-path exhaustion must not delete the cache');
    });
  });

  group('CatalogService.refreshFromRemote — persistence failure', () {
    test('cache write failure → persistenceFailure, NOT accepted, no crash',
        () async {
      final docs = Directory.systemTemp.createTempSync('bp_catalog_pf_');
      addTearDown(() => docs.deleteSync(recursive: true));
      // Make the docs dir path impossible to create: a regular file where
      // the directory chain would need to go.
      final blocker = File('${docs.path}/blocker')..createSync();
      final impossibleDocs = Directory('${blocker.path}/docs');

      final ctx = _buildService(
        handler: (req) async => http.Response(
            _catalogJson(version: 2, parables: [_parable()]), 200),
        docsDirProvider: () async => impossibleDocs,
      );

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.persistenceFailure);
      expect(result.accepted, isFalse);
      expect(result.newVersion, 2);
      expect(_events('catalog_refresh_persist_failed'), isNotEmpty);
      // ctx.docs was replaced by the impossible provider; clean the unused
      // temp dir too.
      ctx.docs.deleteSync(recursive: true);
    });
  });

  group('CatalogService.refreshFromRemote — in-flight deduplication', () {
    test(
        'concurrent same-instance refreshes share one fetch; a later '
        'refresh runs fresh', () async {
      var fetches = 0;
      final ctx = _buildService(
        handler: (req) async {
          fetches++;
          return http.Response(
            _catalogJson(version: 2, parables: [_parable()]),
            200,
          );
        },
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final f1 = ctx.service.refreshFromRemote();
      final f2 = ctx.service.refreshFromRemote();
      expect(identical(f1, f2), isTrue,
          reason: 'concurrent calls must share the in-flight refresh');

      final r1 = await f1;
      final r2 = await f2;
      expect(r1.outcome, CatalogRefreshOutcome.accepted);
      expect(r2.outcome, CatalogRefreshOutcome.accepted);
      expect(fetches, 1,
          reason: 'deduplication must collapse concurrent refreshes to one '
              'network operation — no older/newer response race exists');

      // After completion the dedup slot clears: a new call fetches again
      // and is version-rejected against the now-cached v2.
      final r3 = await ctx.service.refreshFromRemote();
      expect(fetches, 2);
      expect(r3.outcome, CatalogRefreshOutcome.rejectedVersion);
    });
  });

  group('CatalogService.refreshFromRemote — timeout', () {
    test(
        'constructor-injected timeout: slow responses time out on both '
        'attempts → networkFailure, exactly 2 attempts, no uncaught error',
        () async {
      var attempts = 0;
      final ctx = _buildService(
        handler: (req) async {
          attempts++;
          // Complete (with an error, the nastier case) well after the
          // timeout has fired; Future.timeout must swallow it.
          await Future<void>.delayed(const Duration(milliseconds: 150));
          throw const SocketException('late failure after timeout');
        },
        fetchTimeout: const Duration(milliseconds: 40),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.networkFailure);
      expect(attempts, 2, reason: 'one retry after the first timeout');

      // Let the delayed handler futures complete inside the test zone: an
      // uncaught async error here would fail the test.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await _cacheFile(ctx.docs).exists(), isFalse);
    });

    test('default fetch timeout is 60 seconds', () {
      expect(CatalogService.defaultFetchTimeout, const Duration(seconds: 60));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Cache floor preservation: ABSENT / INVALID / VALID / UNKNOWN.
  //
  // The distinction under test is INVALID vs UNKNOWN. Collapsing an
  // indeterminate read to "no usable cache" is what let a readable-later
  // v9 cache be deleted, and let a v8 remote be accepted over it.
  // ───────────────────────────────────────────────────────────────────────
  group('CatalogService — cache state model', () {
    test(
        'UNKNOWN cache (unreadable v9) + bundled v6 + remote v8: remote is '
        'REJECTED and the cache is NOT deleted', () async {
      final ctx = _buildService(
        handler: (req) async => http.Response(
          _catalogJson(version: 8, parables: [_parable()]),
          200,
        ),
        bundledJson: _catalogJson(
          version: 6,
          parables: [_parable(storyId: 'story_bundled_001')],
        ),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final cacheBody =
          _catalogJson(version: 9, parables: [_parable(storyId: 'story_v9')]);
      await _primeCache(ctx.docs, cacheBody);
      final cache = _cacheFile(ctx.docs);
      if (!await _makeUnreadable(cache)) {
        markTestSkipped(
            'filesystem permissions cannot make a file unreadable here '
            '(running as root?) — see the deterministic docs-dir variant '
            'below, which covers the same branch without the OS');
        return;
      }
      addTearDown(() => _restoreReadable(cache));

      // Load: cannot read the cache, so bundled is served — but the cache
      // must survive, because it may hold a HIGHER generation (it does).
      final loaded = await ctx.service.loadCatalog();
      expect(loaded.source, CatalogSource.bundled);
      expect(loaded.version, 6);
      expect(await cache.exists(), isTrue,
          reason: 'an UNKNOWN cache must never be deleted — this one holds '
              'v9, newer than both the bundle and the remote');
      expect(_events('catalog_cache_deleted'), isEmpty);

      // Refresh: the floor cannot be established, so a v8 remote — which
      // is OLDER than the unreadable v9 cache — must not be accepted.
      final refreshed = await ctx.service.refreshFromRemote();
      expect(refreshed.outcome, CatalogRefreshOutcome.cacheStateUnknown);
      expect(_events('catalog_refresh_rejected')
          .where((e) => e['reason'] == 'cache_state_unknown'), isNotEmpty);

      // The v9 cache is intact: restoring access proves nothing was lost
      // and that it is promoted over the bundle once readable again.
      _restoreReadable(cache);
      expect(await cache.readAsString(), cacheBody);
      final relanded = await _buildService(
        handler: (req) async => _unreachable(req),
        bundledJson: _catalogJson(
          version: 6,
          parables: [_parable(storyId: 'story_bundled_001')],
        ),
        docsDirProvider: () async => ctx.docs,
      ).service.loadCatalog();
      expect(relanded.source, CatalogSource.cache);
      expect(relanded.version, 9);
    });

    test(
        'UNKNOWN cache (indeterminate docs dir) is preserved and blocks '
        'remote acceptance — deterministic, no filesystem permissions',
        () async {
      // Deterministic companion to the chmod test above: the docs-dir
      // lookup fails, so the cache cannot be classified at all.
      final docs = Directory.systemTemp.createTempSync('bp_catalog_unknown_');
      addTearDown(() => docs.deleteSync(recursive: true));
      await _primeCache(
        docs,
        _catalogJson(version: 9, parables: [_parable(storyId: 'story_v9')]),
      );

      var allowDocsDir = true;
      final service = CatalogService(
        client: MockClient((req) async => http.Response(
              _catalogJson(version: 8, parables: [_parable()]),
              200,
            )),
        docsDirProvider: () async {
          if (!allowDocsDir) {
            throw const FileSystemException('docs dir unavailable');
          }
          return docs;
        },
        bundledLoader: () async => _catalogJson(
          version: 6,
          parables: [_parable(storyId: 'story_bundled_001')],
        ),
        baseUrlProvider: () => 'https://example.test',
      );

      allowDocsDir = false;
      final loaded = await service.loadCatalog();
      expect(loaded.source, CatalogSource.bundled);
      expect(_events('catalog_cache_deleted'), isEmpty,
          reason: 'an unclassifiable cache must never be deleted');
      expect(
        _events('catalog_cache_read_indeterminate')
            .where((e) => (e['reason'] as String).startsWith('docs_dir_')),
        isNotEmpty,
      );

      final refreshed = await service.refreshFromRemote();
      expect(refreshed.outcome, CatalogRefreshOutcome.cacheStateUnknown);

      // Nothing was written and nothing was destroyed.
      allowDocsDir = true;
      expect(await _cacheFile(docs).exists(), isTrue);
    });

    test('INVALID cache IS deleted — invalidity is positively established',
        () async {
      final ctx = _buildService(
        handler: (req) async => _unreachable(req),
        bundledJson: _catalogJson(
          version: 6,
          parables: [_parable(storyId: 'story_bundled_001')],
        ),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));
      // Parseable JSON, positive version, but the entry violates the
      // active catalog contract — read in full, so positively invalid.
      await _primeCache(
        ctx.docs,
        jsonEncode({
          'version': 99,
          'parables': [
            {..._parable(), 'storytellingMode': 'creative'},
          ],
        }),
      );

      final loaded = await ctx.service.loadCatalog();

      expect(loaded.source, CatalogSource.bundled);
      expect(loaded.version, 6);
      expect(await _cacheFile(ctx.docs).exists(), isFalse,
          reason: 'a positively invalid cache is reclaimed');
      expect(
        _events('catalog_cache_deleted')
            .where((e) => (e['reason'] as String).startsWith('invalid_')),
        isNotEmpty,
      );
      expect(
        _events('catalog_cache_invalid').where(
            (e) => e['reason'] == 'unsupported_storytelling_mode'),
        isNotEmpty,
      );
    });

    test('ABSENT cache is not an error and deletes nothing', () async {
      final ctx = _buildService(handler: (req) async => _unreachable(req));
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final loaded = await ctx.service.loadCatalog();

      expect(loaded.source, CatalogSource.bundled);
      expect(_events('catalog_cache_deleted'), isEmpty);
      expect(_events('catalog_cache_invalid'), isEmpty);
      expect(_events('catalog_cache_read_indeterminate'), isEmpty);
    });

    // ── Deterministic serialization tests ──────────────────────────────
    //
    // No sleeps and no timing-dependent correctness assertions. Both tests
    // park one instance INSIDE the cache critical section on a Completer
    // (via the injected `cacheCriticalSectionBarrier` seam) and observe
    // what a second instance can do while it is parked.
    //
    // `_pumpEventLoop` only gives the other instance every opportunity to
    // proceed; it is never used as evidence that time passed. Under a
    // correct implementation the second instance stays blocked no matter
    // how many turns elapse, because it is waiting on a lock that only the
    // parked instance can release.

    Future<void> pumpEventLoop([int turns = 50]) async {
      for (var i = 0; i < turns; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test(
        'two CatalogService instances sharing a documents directory are '
        'serialized: the second cannot enter the critical section while '
        'the first holds it, and the newer cache survives', () async {
      // The lock is keyed by RESOLVED CACHE PATH and shared across
      // instances, because more than one CatalogService can point at the
      // same directory (public construction, multiple ProviderContainers,
      // DI, tests).
      //
      // The race: instance A loads, classifies the primed v5 cache as
      // stale against bundled v6, and deletes it. Instance B concurrently
      // accepts remote v7 and writes it. Interleaved as
      // A.classify(stale) -> B.write(v7) -> A.delete, the fresh v7 cache
      // is destroyed.
      final docs = Directory.systemTemp.createTempSync('bp_catalog_race_');
      addTearDown(() => docs.deleteSync(recursive: true));
      await _primeCache(
        docs,
        _catalogJson(version: 5, parables: [_parable(storyId: 'story_v5')]),
      );

      String bundled() => _catalogJson(
            version: 6,
            parables: [_parable(storyId: 'story_bundled_001')],
          );

      final aInsideSection = Completer<void>();
      final releaseA = Completer<void>();

      // Instance A parks after classifying the cache as stale but BEFORE
      // deleting it — precisely the window a downgrade would exploit.
      final instanceA = CatalogService(
        client: MockClient((req) async => _unreachable(req)),
        docsDirProvider: () async => docs,
        bundledLoader: () async => bundled(),
        baseUrlProvider: () => null,
        cacheCriticalSectionBarrier: () async {
          if (!aInsideSection.isCompleted) aInsideSection.complete();
          await releaseA.future;
        },
      );

      final remoteV7 =
          _catalogJson(version: 7, parables: [_parable(storyId: 'story_v7')]);
      var bDone = false;
      final instanceB = CatalogService(
        client: MockClient((req) async => _jsonBytes(remoteV7)),
        docsDirProvider: () async => docs,
        bundledLoader: () async => bundled(),
        baseUrlProvider: () => 'https://example.test',
      );

      final aFuture = instanceA.loadCatalog();
      await aInsideSection.future; // deterministic: A holds the lock

      final bFuture = instanceB.refreshFromRemote().then((r) {
        bDone = true;
        return r;
      });

      await pumpEventLoop();
      expect(bDone, isFalse,
          reason: 'B must NOT be able to enter the cache critical section '
              'while A holds the lock for the same cache path');
      expect(await _cacheFile(docs).readAsString(),
          contains('"version":5'),
          reason: 'B must not have written anything yet');

      releaseA.complete();
      final loaded = await aFuture;
      final refresh = await bFuture;

      expect(loaded.source, CatalogSource.bundled,
          reason: 'A saw a stale v5 cache and fell back to bundled v6');
      expect(refresh.outcome, CatalogRefreshOutcome.accepted);

      final cache = _cacheFile(docs);
      expect(await cache.exists(), isTrue,
          reason: "A's stale-cache delete must not destroy the v7 cache B "
              'wrote after it');
      final cached =
          jsonDecode(await cache.readAsString()) as Map<String, dynamic>;
      expect(cached['version'], 7);

      // A third instance sees the surviving v7 over bundled v6.
      final reader = CatalogService(
        client: MockClient((req) async => _unreachable(req)),
        docsDirProvider: () async => docs,
        bundledLoader: () async => bundled(),
        baseUrlProvider: () => null,
      );
      final reloaded = await reader.loadCatalog();
      expect(reloaded.source, CatalogSource.cache);
      expect(reloaded.version, 7);
    });

    test(
        'an instance whose FIRST cache-path resolution fails cannot mutate '
        'the real cache under a fallback lock (v9 is never replaced by v8)',
        () async {
      // The under-lock defect: resolving the lock key separately from the
      // File the work uses meant instance A could fail its first
      // resolution, take a fallback lock, then resolve successfully INSIDE
      // the section and operate on the REAL path — while instance B held
      // the real-path lock. A's v8 could then land on top of B's v9.
      //
      // The fix resolves the File exactly once and derives the key from
      // it, so a failed resolution ends the operation instead of
      // downgrading the lock.
      final docs = Directory.systemTemp.createTempSync('bp_catalog_under_');
      addTearDown(() => docs.deleteSync(recursive: true));

      String bundled() => _catalogJson(
            version: 6,
            parables: [_parable(storyId: 'story_bundled_001')],
          );

      final aInsideSection = Completer<void>();
      final releaseA = Completer<void>();

      // A's FIRST path resolution throws; every later one WOULD succeed.
      var resolutions = 0;
      final instanceA = CatalogService(
        client: MockClient((req) async => _jsonBytes(
            _catalogJson(version: 8, parables: [_parable(storyId: 'v8')]))),
        docsDirProvider: () async {
          resolutions++;
          if (resolutions == 1) {
            throw const FileSystemException('docs dir briefly unavailable');
          }
          return docs;
        },
        bundledLoader: () async => bundled(),
        baseUrlProvider: () => 'https://example.test',
        cacheCriticalSectionBarrier: () async {
          if (!aInsideSection.isCompleted) aInsideSection.complete();
          await releaseA.future;
        },
      );

      final instanceB = CatalogService(
        client: MockClient((req) async => _jsonBytes(
            _catalogJson(version: 9, parables: [_parable(storyId: 'v9')]))),
        docsDirProvider: () async => docs,
        bundledLoader: () async => bundled(),
        baseUrlProvider: () => 'https://example.test',
      );

      final aFuture = instanceA.refreshFromRemote();

      // A must fail closed WITHOUT ever entering the critical section.
      // Under the defective design it would instead park at the barrier
      // holding a fallback lock, and this race would resolve to v8.
      await Future.any([aInsideSection.future, aFuture]);
      expect(aInsideSection.isCompleted, isFalse,
          reason: 'a failed path resolution must end the operation, never '
              'proceed under a fallback lock');

      final aResult = await aFuture;
      expect(aResult.outcome, CatalogRefreshOutcome.cacheStateUnknown,
          reason: 'unresolvable cache path is fail-closed UNKNOWN');
      expect(await _cacheFile(docs).exists(), isFalse,
          reason: 'A must not have written anything');

      // B then installs v9 normally.
      final bResult = await instanceB.refreshFromRemote();
      expect(bResult.outcome, CatalogRefreshOutcome.accepted);
      expect(bResult.newVersion, 9);

      // Release is a no-op under the fixed design; under the defective one
      // it is what let A's v8 land on top of B's v9.
      if (!releaseA.isCompleted) releaseA.complete();
      await pumpEventLoop();

      final cached = jsonDecode(await _cacheFile(docs).readAsString())
          as Map<String, dynamic>;
      expect(cached['version'], 9,
          reason: 'v9 must never be replaced by the older v8');

      // A resolved the path EXACTLY ONCE for that whole operation. The
      // defective design resolved again inside the section, which is what
      // let it reach the real path under a fallback lock.
      expect(resolutions, 1,
          reason: 'the cache path must be resolved exactly once per '
              'operation, never retried inside the critical section');

      // The path was only briefly unavailable: a NEW operation resolves
      // it successfully, proving the guard is about the
      // single-resolution rule rather than a permanently broken path.
      final recheck = await instanceA.refreshFromRemote();
      expect(resolutions, greaterThan(1));
      expect(recheck.outcome, CatalogRefreshOutcome.rejectedVersion,
          reason: 'once resolvable again, the normal floor gate rejects v8 '
              'against the cached v9');
      final finalCache = jsonDecode(await _cacheFile(docs).readAsString())
          as Map<String, dynamic>;
      expect(finalCache['version'], 9);
    });


    test('cache writes use unique temp names and leave no residue',
        () async {
      final ctx = _buildService(
        handler: (req) async => http.Response(
          _catalogJson(version: 2, parables: [_parable()]),
          200,
        ),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      await ctx.service.refreshFromRemote();

      final cacheDir = _cacheFile(ctx.docs).parent;
      final leftovers = cacheDir
          .listSync()
          .map((e) => e.path.split('/').last)
          .where((name) => name.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty,
          reason: 'no temp file may survive a successful write');
      // A fixed ".tmp" sibling would let two writers collide; the name is
      // uniquified per write.
      expect(await File('${_cacheFile(ctx.docs).path}.tmp').exists(), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Active catalog contract. Every case below is REJECTED — none is
  // silently normalized into a different meaning.
  // ───────────────────────────────────────────────────────────────────────
  group('CatalogService — active catalog contract', () {
    Future<CatalogRefreshResult> refreshWith(
        List<Map<String, dynamic>> parables) async {
      final ctx = _buildService(
        handler: (req) async =>
            _jsonBytes(_catalogJson(version: 9, parables: parables)),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));
      return ctx.service.refreshFromRemote();
    }

    test(
        'non-ASCII text survives a refresh served WITHOUT a charset '
        '(no latin-1 mojibake)', () async {
      // The publisher serves `application/json`; package:http would decode
      // that as latin-1, silently corrupting the em-dashes carried by 361
      // corpus entries and persisting the damage to the cache. The bytes
      // are authoritative (RFC 8259), never the header.
      const title = 'Everything was taken in a single afternoon — the '
          'animals, the servants, the children';
      final body = _catalogJson(
        version: 9,
        parables: [
          {..._parable(), 'title': title, 'reflectionQuestion': 'Café — naïve?'}
        ],
      );
      final ctx = _buildService(
        handler: (req) async => _jsonBytes(body),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.accepted);
      final cached = await _cacheFile(ctx.docs).readAsString();
      expect(cached, body,
          reason: 'the cache must hold the exact bytes that were served');
      final decoded = jsonDecode(cached) as Map<String, dynamic>;
      expect((decoded['parables'] as List).first['title'], title);
      expect(cached, contains('—'));
      expect(cached, isNot(contains('â')),
          reason: 'â€” is the latin-1 mojibake signature of an em-dash');
    });

    test('lowercase "kjv" languageStyle is REJECTED, never up-cased',
        () async {
      // Parable.fromJson maps any languageStyle that is not literally
      // 'KJV' to 'WEB'. Accepting "kjv" would silently serve a KJV story
      // with WEB diction — a different translation than the catalog
      // declares.
      final result = await refreshWith([_parable(languageStyle: 'kjv')]);
      expect(result.outcome, CatalogRefreshOutcome.rejectedTranslation);
      expect(
        _events('catalog_refresh_rejected')
            .where((e) => e['reason'] == 'non_canonical_language_style'),
        isNotEmpty,
      );
    });

    test('non-canonical translationId casing is REJECTED', () async {
      for (final value in ['web', 'Kjv', ' WEB', 'WEB ']) {
        AppLogger.instance.clearBreadcrumbs();
        final result = await refreshWith([_parable(translationId: value)]);
        expect(result.outcome, CatalogRefreshOutcome.rejectedTranslation,
            reason: '$value must not be normalized into WEB/KJV');
      }
    });

    test('canonical values are accepted unchanged', () async {
      final result = await refreshWith([
        _parable(storyId: 'story_web', translationId: 'WEB',
            languageStyle: 'WEB'),
        _parable(storyId: 'story_kjv', translationId: 'KJV',
            languageStyle: 'KJV'),
      ]);
      expect(result.outcome, CatalogRefreshOutcome.accepted);
      expect(result.entryCount, 2);
    });

    test('storytellingMode outside the active set is REJECTED', () async {
      for (final mode in ['creative', 'Traditional', 'micro', '']) {
        AppLogger.instance.clearBreadcrumbs();
        final result =
            await refreshWith([{..._parable(), 'storytellingMode': mode}]);
        expect(result.outcome, CatalogRefreshOutcome.rejectedSchema,
            reason: 'storytellingMode "$mode" is not an active catalog mode');
      }
    });

    // The shared identity-blank contract. These EXACT strings are also
    // asserted by the Python half in
    // scripts/tests/test_upload_r2_catalog_publisher.py, and a parity test
    // there fails if either side stops exercising them — because
    // Dart's String.trim() and Python's str.strip() disagree on two of
    // them, so neither language default may be used.
    const blankIdentityStrings = <String>[
      '',
      ' ',
      '   ',
      '\t',
      '\n',
      '\r\n',
      '\u{000B}',
      '\u{000C}',
      '\u{001C}', // Python-blank, NOT Dart-trim-blank
      '\u{001D}',
      '\u{001E}',
      '\u{001F}',
      '\u{0085}',
      '\u{00A0}',
      '\u{1680}',
      '\u{2000}',
      '\u{2009}',
      '\u{200B}',
      '\u{200C}',
      '\u{200D}',
      '\u{2028}',
      '\u{2029}',
      '\u{202F}',
      '\u{205F}',
      '\u{2060}',
      '\u{3000}',
      '\u{180E}',
      '\u{FEFF}', // Dart-trim-blank, NOT Python-strip-blank
      '\u{FEFF}\u{FEFF}',
      ' \t\u{FEFF} ',
      '\u{001C}\u{2060}',
    ];

    test('blank identity fields are REJECTED', () async {
      for (final field in ['storyId', 'title', 'mood', 'storytellingMode']) {
        for (final blank in blankIdentityStrings) {
          AppLogger.instance.clearBreadcrumbs();
          final result =
              await refreshWith([{..._parable(), field: blank}]);
          expect(result.outcome, CatalogRefreshOutcome.rejectedSchema,
              reason: 'blank $field (${blank.runes.toList()}) '
                  'must be rejected');
        }
      }
    });

    test('the blank contract does not defer to language defaults', () {
      // Dart's trim() removes U+FEFF but NOT U+001C; Python's strip() does
      // the opposite. Relying on either default would let a catalog whose
      // title is a lone U+FEFF pass one validator and fail the other.
      expect('\u{FEFF}'.trim(), isEmpty,
          reason: 'premise: Dart trim() DOES strip U+FEFF');
      expect('\u{001C}'.trim(), isNotEmpty,
          reason: 'premise: Dart trim() does NOT strip U+001C');

      // Both are blank under the shared contract regardless.
      expect(CatalogService.isBlankIdentity('\u{FEFF}'), isTrue);
      expect(CatalogService.isBlankIdentity('\u{001C}'), isTrue);
    });

    test('identity-blank classification matches the shared contract', () {
      for (final value in blankIdentityStrings) {
        expect(CatalogService.isBlankIdentity(value), isTrue,
            reason: '${value.runes.toList()} must be blank');
      }
      for (final value in [
        'a',
        ' a ',
        '\u{FEFF}a',
        'a\u{001C}',
        '0',
        '-',
        '。',
      ]) {
        expect(CatalogService.isBlankIdentity(value), isFalse,
            reason: '${value.runes.toList()} must NOT be blank');
      }
    });

    test('duplicate story ids are REJECTED', () async {
      final result = await refreshWith([
        _parable(storyId: 'story_dupe'),
        _parable(storyId: 'story_dupe'),
      ]);
      expect(result.outcome, CatalogRefreshOutcome.rejectedSchema);
      expect(
        _events('catalog_refresh_rejected')
            .where((e) => e['reason'] == 'duplicate_story_id'),
        isNotEmpty,
      );
    });

    test('unsupported storyLength is REJECTED', () async {
      for (final value in ['medium', 'SHORT', 'micro']) {
        AppLogger.instance.clearBreadcrumbs();
        final result =
            await refreshWith([{..._parable(), 'storyLength': value}]);
        expect(result.outcome, CatalogRefreshOutcome.rejectedSchema,
            reason: 'storyLength "$value" is not a supported bucket');
      }
    });

    test('missing or blank textFilePath is REJECTED', () async {
      final missing = Map<String, dynamic>.from(_parable())
        ..remove('textFilePath');
      expect((await refreshWith([missing])).outcome,
          CatalogRefreshOutcome.rejectedSchema);
      expect(
          (await refreshWith([{..._parable(), 'textFilePath': ''}])).outcome,
          CatalogRefreshOutcome.rejectedSchema);
    });

    test('asset paths that could escape the asset root are REJECTED',
        () async {
      const unsafe = [
        '/etc/passwd', // absolute
        '../../etc/passwd', // parent traversal
        'traditional/../../secrets.txt', // traversal mid-path
        'traditional/./story.txt', // non-normalized
        'traditional//story.txt', // empty segment
        r'traditional\9999\story.txt', // windows separator
        'traditional/9999/story .txt', // whitespace
        ' traditional/9999/story.txt', // leading whitespace
        'traditional/9999/story.txt\n', // trailing control char
        'traditional/9999/../../../story.txt',
        '~/story.txt',
        'C:/story.txt',
      ];
      for (final path in unsafe) {
        for (final field in [
          'textFilePath',
          'audioFilePath',
          'scriptureTextFilePath',
          'reflectionAudioPath',
        ]) {
          AppLogger.instance.clearBreadcrumbs();
          final result = await refreshWith([{..._parable(), field: path}]);
          expect(result.outcome, CatalogRefreshOutcome.rejectedSchema,
              reason: '$field=${jsonEncode(path)} must be rejected');
        }
      }
    });

    test('empty optional media path is allowed (not-yet-rendered lane entry)',
        () async {
      final result = await refreshWith([
        {
          ..._parable(),
          'audioFilePath': '',
          'reflectionAudioPath': '',
        }
      ]);
      expect(result.outcome, CatalogRefreshOutcome.accepted,
          reason: 'the real corpus carries empty audio paths for lane '
              'entries whose media is not rendered yet');
    });

    // ── UTF-8 BOM policy: REJECT, identically on both sides ────────────
    //
    // Left to the runtimes' defaults these disagree: Dart's utf8.decode
    // and File.readAsString silently DISCARD a leading BOM, while
    // Python's decode keeps U+FEFF and json.loads then fails. So a
    // BOM-prefixed catalog would be accepted by the app and rejected by
    // the publisher — two validators disagreeing about the same bytes.
    // Both now reject it explicitly, at the BYTE level (a string check
    // would be useless in Dart: the BOM is already gone by then).

    test('Dart really does discard a BOM — the reason the check is needed',
        () {
      final bytes = <int>[...CatalogService.utf8Bom, ...utf8.encode('{"a":1}')];
      expect(utf8.decode(bytes).runes.first, 0x7B,
          reason: 'premise: utf8.decode silently drops the BOM, so a '
              'post-decode string check could never see it');
      expect(CatalogService.startsWithUtf8Bom(bytes), isTrue);
      expect(CatalogService.startsWithUtf8Bom(utf8.encode('{"a":1}')), isFalse);
    });

    test('a remote catalog with a UTF-8 BOM is REJECTED', () async {
      final body = _catalogJson(version: 9, parables: [_parable()]);
      final ctx = _buildService(
        handler: (req) async => http.Response.bytes(
          <int>[...CatalogService.utf8Bom, ...utf8.encode(body)],
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.rejectedSchema);
      expect(
        _events('catalog_refresh_rejected')
            .where((e) => e['reason'] == 'utf8_bom'),
        isNotEmpty,
      );
      expect(await _cacheFile(ctx.docs).exists(), isFalse,
          reason: 'a BOM-prefixed catalog must never be cached');
    });

    test('a cached catalog with a UTF-8 BOM is INVALID (and reclaimed)',
        () async {
      final ctx = _buildService(
        handler: (req) async => _unreachable(req),
        bundledJson: _catalogJson(
          version: 6,
          parables: [_parable(storyId: 'story_bundled_001')],
        ),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      // A v9 cache that would otherwise WIN over bundled v6 — but it
      // carries a BOM, so it is positively invalid rather than served.
      final cache = _cacheFile(ctx.docs);
      await cache.parent.create(recursive: true);
      await cache.writeAsBytes(<int>[
        ...CatalogService.utf8Bom,
        ...utf8.encode(
            _catalogJson(version: 9, parables: [_parable(storyId: 'v9')])),
      ]);

      final loaded = await ctx.service.loadCatalog();

      expect(loaded.source, CatalogSource.bundled);
      expect(loaded.version, 6);
      expect(
        _events('catalog_cache_invalid').where((e) => e['reason'] == 'utf8_bom'),
        isNotEmpty,
      );
      expect(await cache.exists(), isFalse,
          reason: 'a BOM is positively established invalidity, so the cache '
              'is reclaimed rather than preserved as UNKNOWN');
    });

    test('the shipped bundled manifest carries no BOM', () async {
      // The Dart runtime cannot police this lane: rootBundle.loadString
      // has already discarded any BOM before CatalogService sees it. The
      // asset is therefore guarded here and by the Python validator in CI.
      final bytes =
          await File('assets/stories/manifest.json').readAsBytes();
      expect(CatalogService.startsWithUtf8Bom(bytes), isFalse);
    });

    test('the real bundled manifest satisfies the contract', () async {
      // Guards against the contract drifting away from the shipped corpus.
      final bundled =
          await File('assets/stories/manifest.json').readAsString();
      final service = CatalogService(
        client: MockClient((req) async => _unreachable(req)),
        docsDirProvider: () async =>
            Directory.systemTemp.createTempSync('bp_catalog_real_'),
        bundledLoader: () async => bundled,
        baseUrlProvider: () => null,
      );
      final loaded = await service.loadCatalog();
      expect(loaded.source, CatalogSource.bundled);
      expect(loaded.parables, isNotEmpty);
    });
  });
}

/// Removes read permission so the cache becomes INDETERMINATE rather than
/// invalid. Returns false when the platform/user can still read it (e.g.
/// running as root), so the caller can skip instead of asserting a
/// premise that does not hold.
Future<bool> _makeUnreadable(File file) async {
  final result = await Process.run('chmod', ['000', file.path]);
  if (result.exitCode != 0) return false;
  try {
    await file.readAsString();
    return false; // still readable — premise does not hold
  } catch (_) {
    return true;
  }
}

void _restoreReadable(File file) {
  try {
    Process.runSync('chmod', ['644', file.path]);
  } catch (_) {
    // Best effort — the temp dir is removed by the test teardown anyway.
  }
}
