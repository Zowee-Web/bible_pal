// Phase 2 / Slice 1 unit tests for CatalogService.
//
// Covers the six scenarios called out in the Slice 1 prompt:
// success, schema rejection, banned-translation rejection, oversized
// rejection, version-not-higher rejection, network failure.

import 'dart:convert';
import 'dart:io';

import 'package:bible_pal/core/bible_translation_registry.dart';
import 'package:bible_pal/services/catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Minimal valid parable map for catalog tests. Mirrors the shape required
/// by `Parable.fromJson` (storyId, title, mood, storytellingMode, kidFriendly).
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
  };
}

String _catalogJson({
  required int version,
  required List<Map<String, dynamic>> parables,
}) =>
    jsonEncode({'version': version, 'parables': parables});

/// Builds a fresh CatalogService backed by a temp docs dir and a
/// MockClient that returns the given handler's response.
({CatalogService service, Directory docs}) _buildService({
  required MockClientHandler handler,
  String? baseUrl = 'https://example.test',
  int maxBodyBytes = CatalogService.defaultMaxBodyBytes,
}) {
  final docs = Directory.systemTemp.createTempSync('bp_catalog_test_');
  final service = CatalogService(
    client: MockClient(handler),
    docsDirProvider: () async => docs,
    bundledLoader: () async => _catalogJson(version: 0, parables: const []),
    baseUrlProvider: () => baseUrl,
    maxBodyBytes: maxBodyBytes,
  );
  return (service: service, docs: docs);
}

File _cacheFile(Directory docs) =>
    File('${docs.path}/catalog_cache/manifest.json');

void main() {
  group('CatalogService.refreshFromRemote', () {
    test('success: accepts valid remote catalog and writes cache atomically',
        () async {
      final body = _catalogJson(version: 1, parables: [_parable()]);
      final ctx = _buildService(
        handler: (req) async => http.Response(body, 200),
      );
      addTearDown(() => ctx.docs.deleteSync(recursive: true));

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.accepted);
      expect(result.newVersion, 1);
      expect(result.entryCount, 1);

      final cached = _cacheFile(ctx.docs);
      expect(await cached.exists(), isTrue);
      expect(await cached.readAsString(), body);

      // Atomic-write contract: no stray .tmp left behind.
      final tmp = File('${cached.path}.tmp');
      expect(await tmp.exists(), isFalse);
    });

    test('schema rejection: missing "parables" list', () async {
      final body = jsonEncode({'version': 1, 'notparables': []});
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
        version: 1,
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
      final body = _catalogJson(version: 1, parables: [_parable()]);
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
      final cache = _cacheFile(ctx.docs);
      await cache.parent.create(recursive: true);
      await cache.writeAsString(body);

      final result = await ctx.service.refreshFromRemote();

      expect(result.outcome, CatalogRefreshOutcome.rejectedVersion);
      expect(result.newVersion, 5);
      // Cache untouched.
      expect(await cache.readAsString(), body);
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
}
