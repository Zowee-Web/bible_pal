import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/app_logger.dart';
import '../core/bible_translation_registry.dart';
import '../models/parable.dart';

/// Source of the catalog returned by [CatalogService.loadCatalog].
enum CatalogSource { cache, bundled, remote }

/// Outcome of a single [CatalogService.refreshFromRemote] attempt.
enum CatalogRefreshOutcome {
  accepted,
  rejectedSchema,
  rejectedTranslation,
  rejectedEntryCount,
  rejectedOversize,
  rejectedVersion,
  networkFailure,
  notFound,
  missingBaseUrl,
}

/// Result of [CatalogService.loadCatalog].
class CatalogLoadResult {
  final CatalogSource source;
  final List<Parable> parables;
  final int? version;

  const CatalogLoadResult({
    required this.source,
    required this.parables,
    this.version,
  });
}

/// Result of [CatalogService.refreshFromRemote].
class CatalogRefreshResult {
  final CatalogRefreshOutcome outcome;
  final int? newVersion;
  final int? entryCount;

  const CatalogRefreshResult({
    required this.outcome,
    this.newVersion,
    this.entryCount,
  });

  bool get accepted => outcome == CatalogRefreshOutcome.accepted;
}

/// Fetches, validates, caches, and parses the Bible PAL remote catalog
/// published at `${AUDIO_BASE_URL}/catalog/v1/manifest.json`.
///
/// Phase 2 / Slice 1: this service exists but is NOT yet wired into app
/// startup. Slice 2 will call [loadCatalog] from `ParableService`. Adding
/// this file does not change runtime behavior.
class CatalogService {
  static const String catalogObjectKey = 'catalog/v1/manifest.json';
  static const int defaultMaxBodyBytes = 5 * 1024 * 1024;
  static const int defaultMaxEntries = 5000;
  static const Duration defaultFetchTimeout = Duration(seconds: 5);
  static const String _bundledManifestAsset = 'assets/stories/manifest.json';

  final http.Client _client;
  final Future<Directory> Function() _docsDirProvider;
  final Future<String> Function() _bundledLoader;
  final String? Function() _baseUrlProvider;
  final int maxBodyBytes;
  final int maxEntries;
  final Duration fetchTimeout;

  CatalogService({
    http.Client? client,
    Future<Directory> Function()? docsDirProvider,
    Future<String> Function()? bundledLoader,
    String? Function()? baseUrlProvider,
    this.maxBodyBytes = defaultMaxBodyBytes,
    this.maxEntries = defaultMaxEntries,
    this.fetchTimeout = defaultFetchTimeout,
  })  : _client = client ?? http.Client(),
        _docsDirProvider =
            docsDirProvider ?? getApplicationDocumentsDirectory,
        _bundledLoader = bundledLoader ??
            (() => rootBundle.loadString(_bundledManifestAsset)),
        _baseUrlProvider =
            baseUrlProvider ?? (() => dotenv.maybeGet('AUDIO_BASE_URL'));

  /// Resolves the catalog the app should use right now: cache if a valid
  /// cached copy exists, otherwise the bundled manifest. Does NOT trigger
  /// a remote fetch — callers schedule [refreshFromRemote] separately.
  Future<CatalogLoadResult> loadCatalog() async {
    final cacheFile = await _cacheFile();
    if (await cacheFile.exists()) {
      try {
        final content = await cacheFile.readAsString();
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        final validation = _validateDecoded(decoded);
        if (validation.isValid) {
          return CatalogLoadResult(
            source: CatalogSource.cache,
            parables: validation.parables!,
            version: validation.version,
          );
        }
        logEvent(
          'catalog_cache_invalid',
          {'reason': validation.reason ?? 'unknown'},
          level: LogLevel.warn,
        );
      } catch (e) {
        logEvent(
          'catalog_cache_read_failed',
          {'error_type': e.runtimeType.toString()},
          level: LogLevel.warn,
        );
      }
    }

    final bundledContent = await _bundledLoader();
    final bundledDecoded = jsonDecode(bundledContent) as Map<String, dynamic>;
    final parablesRaw =
        bundledDecoded['parables'] as List<dynamic>? ?? const [];
    final parables = parablesRaw
        .map((e) => Parable.fromJson(e as Map<String, dynamic>))
        .toList();
    return CatalogLoadResult(
      source: CatalogSource.bundled,
      parables: parables,
      version: bundledDecoded['version'] as int?,
    );
  }

  /// Fetches the remote catalog, validates it, and on success writes it
  /// atomically to the cache. Returns a structured result so callers can
  /// log outcomes without re-running validation.
  Future<CatalogRefreshResult> refreshFromRemote() async {
    final baseUrl = _baseUrlProvider();
    if (baseUrl == null || baseUrl.isEmpty) {
      return const CatalogRefreshResult(
        outcome: CatalogRefreshOutcome.missingBaseUrl,
      );
    }

    final url = Uri.parse('$baseUrl/$catalogObjectKey');

    final firstAttempt = await _fetchOnce(url);
    _FetchOutcome attempt = firstAttempt;
    if (attempt.isTransientFailure) {
      attempt = await _fetchOnce(url);
    }

    if (attempt.notFound) {
      logEvent(
        'catalog_refresh_failed',
        {'outcome': 'not_found'},
        level: LogLevel.warn,
      );
      return const CatalogRefreshResult(
        outcome: CatalogRefreshOutcome.notFound,
      );
    }

    if (attempt.body == null) {
      logEvent(
        'catalog_refresh_failed',
        {'outcome': 'network_failure'},
        level: LogLevel.warn,
      );
      return const CatalogRefreshResult(
        outcome: CatalogRefreshOutcome.networkFailure,
      );
    }

    final bodyBytes = attempt.bodyByteLength!;
    if (bodyBytes > maxBodyBytes) {
      logEvent(
        'catalog_refresh_rejected',
        {'reason': 'oversize', 'bytes': bodyBytes},
        level: LogLevel.warn,
      );
      return const CatalogRefreshResult(
        outcome: CatalogRefreshOutcome.rejectedOversize,
      );
    }

    Map<String, dynamic> decoded;
    try {
      final raw = jsonDecode(attempt.body!);
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('catalog root is not an object');
      }
      decoded = raw;
    } catch (e) {
      logEvent(
        'catalog_refresh_rejected',
        {'reason': 'parse_error', 'error_type': e.runtimeType.toString()},
        level: LogLevel.warn,
      );
      return const CatalogRefreshResult(
        outcome: CatalogRefreshOutcome.rejectedSchema,
      );
    }

    final validation = _validateDecoded(decoded);
    if (!validation.isValid) {
      logEvent(
        'catalog_refresh_rejected',
        {'reason': validation.reason ?? 'unknown'},
        level: LogLevel.warn,
      );
      switch (validation.failure!) {
        case _ValidationFailure.schema:
          return const CatalogRefreshResult(
            outcome: CatalogRefreshOutcome.rejectedSchema,
          );
        case _ValidationFailure.translation:
          return const CatalogRefreshResult(
            outcome: CatalogRefreshOutcome.rejectedTranslation,
          );
        case _ValidationFailure.entryCount:
          return const CatalogRefreshResult(
            outcome: CatalogRefreshOutcome.rejectedEntryCount,
          );
      }
    }

    final remoteVersion = validation.version;
    if (remoteVersion == null) {
      logEvent(
        'catalog_refresh_rejected',
        {'reason': 'missing_version'},
        level: LogLevel.warn,
      );
      return const CatalogRefreshResult(
        outcome: CatalogRefreshOutcome.rejectedSchema,
      );
    }

    final cachedVersion = await _readCachedVersion();
    if (cachedVersion != null && remoteVersion <= cachedVersion) {
      logEvent(
        'catalog_refresh_rejected',
        {
          'reason': 'version_not_higher',
          'remote_version': remoteVersion,
          'cached_version': cachedVersion,
        },
        level: LogLevel.warn,
      );
      return CatalogRefreshResult(
        outcome: CatalogRefreshOutcome.rejectedVersion,
        newVersion: remoteVersion,
      );
    }

    await _persistAtomically(attempt.body!);

    logEvent('catalog_refresh_accepted', {
      'new_version': remoteVersion,
      'entry_count': validation.parables!.length,
    });
    return CatalogRefreshResult(
      outcome: CatalogRefreshOutcome.accepted,
      newVersion: remoteVersion,
      entryCount: validation.parables!.length,
    );
  }

  Future<File> _cacheFile() async {
    final dir = await _docsDirProvider();
    return File('${dir.path}/catalog_cache/manifest.json');
  }

  Future<int?> _readCachedVersion() async {
    final cacheFile = await _cacheFile();
    if (!await cacheFile.exists()) return null;
    try {
      final content = await cacheFile.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return null;
      return decoded['version'] as int?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistAtomically(String body) async {
    final cacheFile = await _cacheFile();
    await cacheFile.parent.create(recursive: true);
    final tmp = File('${cacheFile.path}.tmp');
    if (await tmp.exists()) {
      await tmp.delete();
    }
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(cacheFile.path);
  }

  Future<_FetchOutcome> _fetchOnce(Uri url) async {
    try {
      final response = await _client.get(url).timeout(fetchTimeout);
      if (response.statusCode == 404) {
        return _FetchOutcome.notFound();
      }
      if (response.statusCode != 200) {
        return _FetchOutcome.transient();
      }
      return _FetchOutcome.success(
        body: response.body,
        bodyByteLength: response.bodyBytes.length,
      );
    } catch (_) {
      return _FetchOutcome.transient();
    }
  }

  _ValidationResult _validateDecoded(Map<String, dynamic> decoded) {
    final parablesRaw = decoded['parables'];
    if (parablesRaw is! List) {
      return _ValidationResult.invalid(
        _ValidationFailure.schema,
        'missing_parables_list',
      );
    }
    if (parablesRaw.length > maxEntries) {
      return _ValidationResult.invalid(
        _ValidationFailure.entryCount,
        'too_many_entries',
      );
    }
    final parables = <Parable>[];
    for (final entry in parablesRaw) {
      if (entry is! Map<String, dynamic>) {
        return _ValidationResult.invalid(
          _ValidationFailure.schema,
          'entry_not_map',
        );
      }
      final translationId = entry['translationId'];
      if (translationId is String &&
          !BibleTranslationRegistry.isAllowed(
            translationId.trim().toUpperCase(),
          )) {
        return _ValidationResult.invalid(
          _ValidationFailure.translation,
          'banned_translation_id',
        );
      }
      final languageStyle = entry['languageStyle'];
      if (languageStyle is String &&
          !BibleTranslationRegistry.isAllowed(
            languageStyle.trim().toUpperCase(),
          )) {
        return _ValidationResult.invalid(
          _ValidationFailure.translation,
          'banned_language_style',
        );
      }
      try {
        parables.add(Parable.fromJson(entry));
      } catch (e) {
        return _ValidationResult.invalid(
          _ValidationFailure.schema,
          'parse_error_${e.runtimeType}',
        );
      }
    }
    final version = decoded['version'];
    return _ValidationResult.valid(
      parables: parables,
      version: version is int ? version : null,
    );
  }
}

enum _ValidationFailure { schema, translation, entryCount }

class _ValidationResult {
  final bool isValid;
  final List<Parable>? parables;
  final int? version;
  final _ValidationFailure? failure;
  final String? reason;

  const _ValidationResult._({
    required this.isValid,
    this.parables,
    this.version,
    this.failure,
    this.reason,
  });

  factory _ValidationResult.valid({
    required List<Parable> parables,
    required int? version,
  }) =>
      _ValidationResult._(
        isValid: true,
        parables: parables,
        version: version,
      );

  factory _ValidationResult.invalid(
    _ValidationFailure failure,
    String reason,
  ) =>
      _ValidationResult._(
        isValid: false,
        failure: failure,
        reason: reason,
      );
}

class _FetchOutcome {
  final String? body;
  final int? bodyByteLength;
  final bool notFound;
  final bool isTransientFailure;

  const _FetchOutcome._({
    this.body,
    this.bodyByteLength,
    this.notFound = false,
    this.isTransientFailure = false,
  });

  factory _FetchOutcome.success({
    required String body,
    required int bodyByteLength,
  }) =>
      _FetchOutcome._(body: body, bodyByteLength: bodyByteLength);

  factory _FetchOutcome.notFound() => const _FetchOutcome._(notFound: true);

  factory _FetchOutcome.transient() =>
      const _FetchOutcome._(isTransientFailure: true);
}
