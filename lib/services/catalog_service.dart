import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

  /// External catalog replacement is latched off for this service instance
  /// because no trusted bundled baseline exists (bundled catalog version
  /// invalid, or bundled content itself unusable).
  disabledExternalReplacement,

  /// Remote catalog passed every validation/version gate but the cache
  /// write failed. The refresh is NOT accepted; the previous usable
  /// catalog/cache is preserved.
  persistenceFailure,

  /// The on-device cache could not be read well enough to establish the
  /// version floor (indeterminate I/O — NOT positively-established
  /// invalidity). The cache may hold a HIGHER valid generation than the
  /// remote candidate, so accepting the remote could silently downgrade
  /// the catalog. Fail closed: nothing is replaced and nothing is
  /// deleted.
  cacheStateUnknown,

  /// Unexpected internal error. Contained here so the fire-and-forget
  /// refresh path can never surface an uncaught asynchronous error.
  internalError,
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
/// Catalog Currency invariant (docs/INVARIANTS.md): one monotonic positive
/// integer catalog generation is shared by the bundled manifest, the cache,
/// the remote catalog, and the publisher. The bundled catalog is the trusted
/// baseline `B`; a cache is served only when its fully validated generation
/// `Vc > B`, and a remote catalog is accepted only when its fully validated
/// generation `Vr > max(B, Vc)`. Equality never updates. Entry count is
/// never a version signal.
class CatalogService {
  static const String catalogObjectKey = 'catalog/v1/manifest.json';
  static const int defaultMaxBodyBytes = 5 * 1024 * 1024;
  static const int defaultMaxEntries = 5000;

  /// Per-attempt fetch timeout. Note: `Future.timeout` does not cancel the
  /// underlying HTTP request — the socket may stay open until the response
  /// arrives or the OS gives up. Abortable requests are a documented
  /// follow-up, not part of this milestone.
  static const Duration defaultFetchTimeout = Duration(seconds: 60);
  static const String _bundledManifestAsset = 'assets/stories/manifest.json';

  // ── ACTIVE CATALOG CONTRACT ──────────────────────────────────────────
  // One explicit contract, enforced with equivalent semantics on both
  // sides: here and in scripts/validate_catalog_manifest.py (the
  // ALLOWED_TRANSLATIONS / ACTIVE_LANGUAGE_STYLES /
  // ACTIVE_STORYTELLING_MODES / ACTIVE_STORY_LENGTHS sets and
  // validate_parable_entry). A candidate catalog — bundled, cached or
  // remote — becomes TRUSTED only after satisfying all of it. Change one
  // side and you MUST change the other in the same commit.

  /// Creative was retired 2026-05-13; the active catalog is Traditional
  /// only. `Parable.storytellingMode` survives solely for backward
  /// parsing of legacy entries.
  static const Set<String> activeStorytellingModes = {'traditional'};

  /// Presentation diction the app can actually represent. Anything else
  /// is silently coerced to `WEB` by `Parable.fromJson`, so a
  /// non-canonical value must be rejected rather than normalized.
  static const Set<String> activeLanguageStyles = {'WEB', 'KJV'};

  /// `StoryLengthBucket` names (lib/core/story_length_bucket.dart).
  static const Set<String> activeStoryLengths = {'short', 'full', 'long'};

  /// Identity + serving anchors that must be present and non-blank.
  static const List<String> _requiredNonBlankFields = [
    'storyId',
    'title',
    'mood',
    'storytellingMode',
  ];

  /// Optional media paths. An EMPTY string is a deliberate "not rendered
  /// yet" marker for lane entries and stays allowed; any other value must
  /// be a safe relative path.
  static const List<String> _optionalPathFields = [
    'audioFilePath',
    'scriptureTextFilePath',
    'reflectionAudioPath',
  ];

  /// Safe relative asset path: POSIX-relative, ASCII, no leading/trailing
  /// or doubled separators, no backslashes, no whitespace or control
  /// characters. With the explicit `.`/`..` segment check this makes
  /// escaping the asset root impossible.
  static final RegExp _safePathPattern =
      RegExp(r'^[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*$');

  /// Snapshot of the compliance allowlist. Exact-match only — the value
  /// is never trimmed or upper-cased before comparison.
  static final Set<String> _canonicalTranslationIds =
      BibleTranslationRegistry.allowedIds;

  /// EXPLICIT identity-blank contract, shared verbatim with
  /// `IDENTITY_BLANK_CODE_POINTS` in the publisher validator.
  ///
  /// Neither `String.trim()` (Dart) nor `str.strip()` (Python) may be used
  /// for this: they disagree. Dart's trim follows Unicode White_Space
  /// PLUS U+FEFF; Python's strip follows `str.isspace()`, which includes
  /// the C1 file/group/record/unit separators U+001C–U+001F but NOT
  /// U+FEFF. Relying on either default would let a catalog whose title is
  /// a lone U+FEFF pass the publisher and fail the app — or the reverse
  /// for U+001C. The set below is the explicit UNION of both, so the two
  /// validators reach the identical verdict on every input.
  static const Set<int> identityBlankCodePoints = {
    0x0009, // TAB
    0x000A, // LF
    0x000B, // VT
    0x000C, // FF
    0x000D, // CR
    0x001C, // FILE SEPARATOR      (Python-only blank)
    0x001D, // GROUP SEPARATOR     (Python-only blank)
    0x001E, // RECORD SEPARATOR    (Python-only blank)
    0x001F, // UNIT SEPARATOR      (Python-only blank)
    0x0020, // SPACE
    0x0085, // NEL
    0x00A0, // NBSP
    0x1680, // OGHAM SPACE MARK
    0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005,
    0x2006, 0x2007, 0x2008, 0x2009, 0x200A,
    0x200B, // ZERO WIDTH SPACE
    0x200C, // ZERO WIDTH NON-JOINER
    0x200D, // ZERO WIDTH JOINER
    0x2028, // LINE SEPARATOR
    0x2029, // PARAGRAPH SEPARATOR
    0x202F, // NARROW NBSP
    0x205F, // MEDIUM MATHEMATICAL SPACE
    0x2060, // WORD JOINER
    0x3000, // IDEOGRAPHIC SPACE
    0x180E, // MONGOLIAN VOWEL SEPARATOR
    0xFEFF, // ZERO WIDTH NO-BREAK SPACE / BOM  (Dart-only blank)
  };

  /// True when `value` carries no identity content: empty, or composed
  /// entirely of code points in [identityBlankCodePoints].
  static bool isBlankIdentity(String value) {
    if (value.isEmpty) return true;
    for (final codePoint in value.runes) {
      if (!identityBlankCodePoints.contains(codePoint)) return false;
    }
    return true;
  }

  /// Mirrors `is_safe_relative_asset_path` in the publisher validator.
  ///
  /// No trim/strip comparison here either: the character class below
  /// already excludes every whitespace, control and zero-width code
  /// point, so leading/trailing blanks are rejected by the same rule in
  /// both languages with no locale- or runtime-dependent behaviour.
  static bool _isSafeRelativeAssetPath(String value) {
    if (value.isEmpty) return false;
    if (!_safePathPattern.hasMatch(value)) return false;
    for (final segment in value.split('/')) {
      if (segment == '.' || segment == '..') return false;
    }
    return true;
  }

  final http.Client _client;
  final Future<Directory> Function() _docsDirProvider;
  final Future<String> Function() _bundledLoader;
  final String? Function() _baseUrlProvider;
  final int maxBodyBytes;
  final int maxEntries;
  final Duration fetchTimeout;

  /// TEST-ONLY seam. Awaited inside the cache critical section, after the
  /// cache has been classified and the version floor established but
  /// BEFORE any mutation (delete or write). Null in production.
  ///
  /// It exists so serialization can be tested deterministically: a test
  /// parks one instance mid-section on a [Completer] and observes that a
  /// second instance cannot enter, instead of sleeping and hoping for an
  /// interleaving.
  @visibleForTesting
  final Future<void> Function()? cacheCriticalSectionBarrier;

  /// Latched ON when this instance discovers that no trusted bundled
  /// baseline exists (bundled content valid but version invalid, or bundled
  /// content itself unusable). While latched, neither the cache-over-bundle
  /// path nor remote refresh may replace the served catalog. Lifetime:
  /// this CatalogService instance (one app session in production).
  bool _externalReplacementDisabled = false;

  /// Memoized bundled baseline. The bundled asset cannot change within a
  /// session, so it is parsed and validated at most once per instance.
  _BundledBaseline? _baseline;

  /// In-flight refresh deduplication: concurrent same-instance calls share
  /// one refresh so an older response can never overwrite a newer one.
  Future<CatalogRefreshResult>? _inFlightRefresh;

  /// Tails of the cache critical-section chains, keyed by the RESOLVED
  /// cache file path and shared across every [CatalogService] in this
  /// isolate. Every read/write/delete runs through [_withCacheLock], so a
  /// decision taken from a cache snapshot cannot be invalidated by a
  /// concurrent mutation between observing the state and acting on it —
  /// including a mutation from a *different* CatalogService instance
  /// pointed at the same documents directory (public construction,
  /// multiple ProviderContainers/scopes, DI, tests).
  ///
  /// SCOPE, precisely: this serializes within ONE Dart isolate. It does
  /// NOT coordinate across isolates or OS processes, and no OS-level file
  /// lock is used. That is sound for the current architecture — the cache
  /// lives in the app's own sandbox and only the main isolate touches it
  /// — but it is an assumption, not a guarantee. If catalog cache access
  /// ever moves to a background isolate or a second process, this must
  /// become an OS-level lock; see docs/INVARIANTS.md.
  static final Map<String, Future<void>> _cacheLocksByPath = {};

  /// UTF-8 BOM. Catalog JSON must NOT carry one.
  ///
  /// This is an explicit shared policy, not an accident of either
  /// runtime: `utf8.decode` (and `File.readAsString`) SILENTLY DISCARD a
  /// leading BOM, while Python's `bytes.decode("utf-8")` keeps U+FEFF and
  /// `json.loads` then fails. Left alone, a BOM-prefixed catalog would be
  /// accepted by the app and rejected by the publisher — the two
  /// validators disagreeing on the same bytes. JSON does not need a BOM
  /// (RFC 8259) and the publisher owns the bytes it uploads, so both
  /// sides reject it and the wire format stays canonical.
  ///
  /// Only a LEADING BOM is rejected. U+FEFF appearing inside legitimate
  /// story text is untouched.
  static const List<int> utf8Bom = [0xEF, 0xBB, 0xBF];

  /// True when `bytes` begins with a UTF-8 BOM.
  static bool startsWithUtf8Bom(List<int> bytes) =>
      bytes.length >= 3 &&
      bytes[0] == utf8Bom[0] &&
      bytes[1] == utf8Bom[1] &&
      bytes[2] == utf8Bom[2];

  /// Makes each cache write use a distinct temp filename.
  int _tmpWriteCounter = 0;

  CatalogService({
    http.Client? client,
    Future<Directory> Function()? docsDirProvider,
    Future<String> Function()? bundledLoader,
    String? Function()? baseUrlProvider,
    this.maxBodyBytes = defaultMaxBodyBytes,
    this.maxEntries = defaultMaxEntries,
    this.fetchTimeout = defaultFetchTimeout,
    this.cacheCriticalSectionBarrier,
  })  : _client = client ?? http.Client(),
        _docsDirProvider =
            docsDirProvider ?? getApplicationDocumentsDirectory,
        _bundledLoader = bundledLoader ??
            (() => rootBundle.loadString(_bundledManifestAsset)),
        _baseUrlProvider =
            baseUrlProvider ?? (() => dotenv.maybeGet('AUDIO_BASE_URL'));

  /// Resolves the catalog the app should use right now.
  ///
  /// Policy (bundled-first):
  ///  1. The bundled catalog is loaded and fully materialized FIRST. Only
  ///     after it is proven usable is cache currency compared. The cache is
  ///     served only when its fully validated version `Vc > B` (strictly).
  ///     A stale/equal/invalid cache is deleted best-effort after the
  ///     bundled fallback is already established; deletion failure is
  ///     logged and never changes the selected catalog.
  ///  2. If bundled content is valid but its version is missing, of the
  ///     wrong type, or non-positive, the bundled catalog is served
  ///     fail-closed: external replacement is latched off for this
  ///     instance, the cache is preserved (relative currency is
  ///     unknowable), and `catalog_bundled_version_invalid` is emitted.
  ///  3. If the bundled asset itself cannot be read/parsed/validated, a
  ///     fully validated cache with a positive integer version may serve as
  ///     an emergency availability fallback (cache preserved, remote
  ///     disabled). With no usable cache, the error propagates so the
  ///     caller's existing fallback path operates.
  ///
  /// Does NOT trigger a remote fetch — callers schedule
  /// [refreshFromRemote] separately.
  Future<CatalogLoadResult> loadCatalog() async {
    final baseline = await _resolveBundledBaseline();

    if (!baseline.contentValid) {
      // Bundled content itself failed → no trusted watermark exists for
      // this session; remote advancement stays disabled.
      _externalReplacementDisabled = true;
      // Emergency availability fallback. The cache is never deleted on
      // this path — not even when invalid — because no trusted baseline
      // exists to judge it against.
      final cache = await _withCacheLock(
        _readCacheStateUnlocked,
        onPathUnresolved: _unresolvedCacheState,
      );
      if (cache.isValid) {
        logEvent(
          'catalog_bundled_content_invalid',
          {
            'reason': baseline.contentFailureReason ?? 'unknown',
            'fallback': 'cache_emergency',
            'cache_version': cache.version,
          },
          level: LogLevel.error,
        );
        return CatalogLoadResult(
          source: CatalogSource.cache,
          parables: cache.parables!,
          version: cache.version,
        );
      }
      logEvent(
        'catalog_bundled_content_invalid',
        {
          'reason': baseline.contentFailureReason ?? 'unknown',
          'fallback': 'none',
          'cache_state': cache.kind.name,
        },
        level: LogLevel.error,
      );
      throw StateError(
        'bundled catalog unusable (${baseline.contentFailureReason}) '
        'and no valid cache exists',
      );
    }

    if (baseline.version == null) {
      // Bundled content valid, version invalid → fail closed: serve the
      // bundled catalog, latch external replacement off, preserve any
      // cache (its currency relative to this bundle is unknowable).
      _externalReplacementDisabled = true;
      logEvent(
        'catalog_bundled_version_invalid',
        {'reason': baseline.versionFailureReason ?? 'unknown'},
        level: LogLevel.warn,
      );
      return CatalogLoadResult(
        source: CatalogSource.bundled,
        parables: baseline.parables!,
        version: null,
      );
    }

    final bundledVersion = baseline.version!;

    // Bundled catalog is proven usable — only now compare cache currency.
    // Classification and the delete that may follow from it happen in ONE
    // critical section, so the state a delete is based on cannot have
    // been replaced by a newer cache in between.
    final cache = await _withCacheLock(
      onPathUnresolved: _unresolvedCacheState,
      (cacheFile) async {
      final state = await _readCacheStateUnlocked(cacheFile);
      // Test-only: park here, still holding the lock, so a second
      // instance can be observed failing to enter.
      await cacheCriticalSectionBarrier?.call();
      switch (state.kind) {
        case _CacheStateKind.valid:
          if (state.version! > bundledVersion) return state;
          // Positively established as stale (Vc <= B).
          await _deleteCacheUnlocked(cacheFile,
              reason: 'stale_or_equal_version');
        case _CacheStateKind.invalid:
          // Positively established as unusable — safe to reclaim.
          await _deleteCacheUnlocked(cacheFile,
              reason: 'invalid_${state.reason}');
        case _CacheStateKind.absent:
          break;
        case _CacheStateKind.unknown:
          // NOT deletable: an unreadable cache may hold a higher valid
          // generation. Serve bundled for now and leave it in place so a
          // later session can still promote it.
          logEvent(
            'catalog_cache_state_unknown',
            {'reason': state.reason ?? 'unknown', 'action': 'preserved'},
            level: LogLevel.warn,
          );
      }
      return state;
    });

    if (cache.isValid && cache.version! > bundledVersion) {
      return CatalogLoadResult(
        source: CatalogSource.cache,
        parables: cache.parables!,
        version: cache.version,
      );
    }

    return CatalogLoadResult(
      source: CatalogSource.bundled,
      parables: baseline.parables!,
      version: bundledVersion,
    );
  }

  /// Fetches the remote catalog, validates it, and on success writes it
  /// atomically to the cache. Returns a structured result so callers can
  /// log outcomes without re-running validation. Never throws: the
  /// fire-and-forget call site must not observe an uncaught async error.
  Future<CatalogRefreshResult> refreshFromRemote() {
    return _inFlightRefresh ??= _refreshGuarded().whenComplete(() {
      _inFlightRefresh = null;
    });
  }

  Future<CatalogRefreshResult> _refreshGuarded() async {
    try {
      return await _refreshFromRemoteInner();
    } catch (e) {
      logEvent(
        'catalog_refresh_unexpected_error',
        {'error_type': e.runtimeType.toString()},
        level: LogLevel.error,
      );
      return const CatalogRefreshResult(
        outcome: CatalogRefreshOutcome.internalError,
      );
    }
  }

  Future<CatalogRefreshResult> _refreshFromRemoteInner() async {
    if (_externalReplacementDisabled) {
      logEvent(
        'catalog_refresh_skipped',
        {'reason': 'external_replacement_disabled'},
        level: LogLevel.warn,
      );
      return const CatalogRefreshResult(
        outcome: CatalogRefreshOutcome.disabledExternalReplacement,
      );
    }

    // Remote refresh may run only when a trusted bundled baseline exists.
    final baseline = await _resolveBundledBaseline();
    if (!baseline.trusted) {
      _externalReplacementDisabled = true;
      logEvent(
        'catalog_refresh_skipped',
        {
          'reason': baseline.contentValid
              ? 'bundled_version_invalid'
              : 'bundled_content_invalid',
        },
        level: LogLevel.warn,
      );
      return const CatalogRefreshResult(
        outcome: CatalogRefreshOutcome.disabledExternalReplacement,
      );
    }
    final bundledVersion = baseline.version!;

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

    if (attempt.bodyBytes == null) {
      logEvent(
        'catalog_refresh_failed',
        {'outcome': 'network_failure'},
        level: LogLevel.warn,
      );
      return const CatalogRefreshResult(
        outcome: CatalogRefreshOutcome.networkFailure,
      );
    }

    final bodyBytes = attempt.bodyBytes!;
    if (bodyBytes.length > maxBodyBytes) {
      logEvent(
        'catalog_refresh_rejected',
        {'reason': 'oversize', 'bytes': bodyBytes.length},
        level: LogLevel.warn,
      );
      return const CatalogRefreshResult(
        outcome: CatalogRefreshOutcome.rejectedOversize,
      );
    }

    if (startsWithUtf8Bom(bodyBytes)) {
      logEvent(
        'catalog_refresh_rejected',
        {'reason': 'utf8_bom'},
        level: LogLevel.warn,
      );
      return const CatalogRefreshResult(
        outcome: CatalogRefreshOutcome.rejectedSchema,
      );
    }

    // Decode the RAW BYTES as UTF-8 — never `response.body`.
    //
    // package:http derives the decoding charset from the response's
    // Content-Type and falls back to LATIN-1 when none is given. The
    // publisher serves `application/json` with no charset parameter, and
    // 361 corpus entries carry non-ASCII text (em-dashes in
    // reflectionQuestion, …), so `response.body` would silently mojibake
    // every one of them and persist the damage to the cache. JSON is
    // UTF-8 by RFC 8259, so the bytes are authoritative and the header is
    // not. A body that is not valid UTF-8 is a malformed catalog, handled
    // by the same rejection path as unparseable JSON.
    final String bodyText;
    Map<String, dynamic> decoded;
    try {
      bodyText = utf8.decode(bodyBytes);
      final raw = jsonDecode(bodyText);
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

    final versionState = _classifyVersion(decoded['version']);
    final remoteVersion = versionState.value;
    if (remoteVersion == null) {
      logEvent(
        'catalog_refresh_rejected',
        {'reason': 'version_${versionState.failureReason}'},
        level: LogLevel.warn,
      );
      return const CatalogRefreshResult(
        outcome: CatalogRefreshOutcome.rejectedSchema,
      );
    }

    // Currency floor AND the replacement happen inside ONE cache critical
    // section. Re-establishing the floor immediately before the write is
    // what makes the decision sound: the network fetch above took
    // arbitrary time, during which the cache may have advanced past the
    // remote candidate or become unreadable.
    //
    // The floor is the trusted bundled generation, raised by the
    // generation of a FULLY validated cache when one exists. A cache
    // positively established as invalid (whatever version integer it
    // claims) contributes nothing, so it can never poison the watermark;
    // a cache whose state is UNKNOWN blocks the replacement entirely,
    // because it may hold a higher generation than the candidate.
    final decision = await _withCacheLock(
      onPathUnresolved: (e) =>
          _PersistDecision.cacheUnknown('docs_dir_${e.runtimeType}'),
      (cacheFile) async {
      final cacheState = await _readCacheStateUnlocked(cacheFile);
      if (cacheState.isUnknown) {
        return _PersistDecision.cacheUnknown(cacheState.reason);
      }
      final cachedVersion = cacheState.isValid ? cacheState.version : null;
      final floor = (cachedVersion != null && cachedVersion > bundledVersion)
          ? cachedVersion
          : bundledVersion;
      if (remoteVersion <= floor) {
        return _PersistDecision.versionNotHigher(cachedVersion);
      }
      // Test-only: park here, still holding the lock, with the floor
      // already computed — the exact window a downgrade would exploit.
      await cacheCriticalSectionBarrier?.call();
      try {
        await _persistUnlocked(cacheFile, bodyText);
      } catch (e) {
        return _PersistDecision.persistFailed(e.runtimeType.toString());
      }
      return _PersistDecision.accepted(cachedVersion);
    });

    switch (decision.kind) {
      case _PersistDecisionKind.cacheUnknown:
        // Fail closed: the cache floor cannot be established, so the
        // remote may be older than what is already on disk.
        logEvent(
          'catalog_refresh_rejected',
          {
            'reason': 'cache_state_unknown',
            'remote_version': remoteVersion,
            'bundled_version': bundledVersion,
            'cache_reason': decision.reason ?? 'unknown',
          },
          level: LogLevel.warn,
        );
        return CatalogRefreshResult(
          outcome: CatalogRefreshOutcome.cacheStateUnknown,
          newVersion: remoteVersion,
        );
      case _PersistDecisionKind.versionNotHigher:
        // Strict `>` only. An equal-version remote — even with different
        // bytes — is a version collision, never an update.
        logEvent(
          'catalog_refresh_rejected',
          {
            'reason': 'version_not_higher',
            'remote_version': remoteVersion,
            'bundled_version': bundledVersion,
            if (decision.cachedVersion != null)
              'cached_version': decision.cachedVersion,
          },
          level: LogLevel.warn,
        );
        return CatalogRefreshResult(
          outcome: CatalogRefreshOutcome.rejectedVersion,
          newVersion: remoteVersion,
        );
      case _PersistDecisionKind.persistFailed:
        // Validation/version gates passed but the cache write failed:
        // this is NOT an accepted refresh. The previous cache (if any) is
        // left as-is — the atomic tmp+rename write never clobbers it
        // partially.
        logEvent(
          'catalog_refresh_persist_failed',
          {'error_type': decision.reason ?? 'unknown'},
          level: LogLevel.error,
        );
        return CatalogRefreshResult(
          outcome: CatalogRefreshOutcome.persistenceFailure,
          newVersion: remoteVersion,
        );
      case _PersistDecisionKind.accepted:
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
  }

  /// The FULLY VALIDATED bundled catalog, or `null` when the bundled asset
  /// fails the active catalog contract.
  ///
  /// Exists for the journey rescue paths in `ParableService`, which need
  /// to consult bundled entries that a served (cached) catalog may not
  /// contain. Those paths previously re-read
  /// `assets/stories/manifest.json` with `rootBundle` + `jsonDecode` +
  /// bare `Parable.fromJson`, which skipped every gate this service
  /// applies — the translation allowlist included — and so could
  /// resurrect a catalog that was rejected one layer up. Rescue is a
  /// *selection* concern; it never gets its own weaker validation.
  ///
  /// Returns content-valid entries even when the bundled *version* is
  /// unusable: a bad generation disables external replacement, but it
  /// does not make already-validated bundled content unsafe to serve.
  Future<List<Parable>?> validatedBundledCatalog() async {
    final baseline = await _resolveBundledBaseline();
    return baseline.contentValid ? baseline.parables : null;
  }

  // ── Bundled baseline ───────────────────────────────────────────────────

  Future<_BundledBaseline> _resolveBundledBaseline() async {
    final existing = _baseline;
    if (existing != null) return existing;
    final computed = await _computeBundledBaseline();
    return _baseline ??= computed;
  }

  Future<_BundledBaseline> _computeBundledBaseline() async {
    Map<String, dynamic> decoded;
    try {
      final content = await _bundledLoader();
      final raw = jsonDecode(content);
      if (raw is! Map<String, dynamic>) {
        return const _BundledBaseline.contentInvalid('root_not_object');
      }
      decoded = raw;
    } catch (e) {
      return _BundledBaseline.contentInvalid(
        'read_or_parse_failed_${e.runtimeType}',
      );
    }
    final validation = _validateDecoded(decoded);
    if (!validation.isValid) {
      return _BundledBaseline.contentInvalid(validation.reason ?? 'unknown');
    }
    final versionState = _classifyVersion(decoded['version']);
    if (versionState.value == null) {
      return _BundledBaseline.versionInvalid(
        validation.parables!,
        versionState.failureReason!,
      );
    }
    return _BundledBaseline.trusted(validation.parables!, versionState.value!);
  }

  // ── Cache handling ─────────────────────────────────────────────────────

  Future<File> _cacheFile() async {
    final dir = await _docsDirProvider();
    return File('${dir.path}/catalog_cache/manifest.json');
  }

  /// Serializes every cache read, write and delete that targets the same
  /// cache PATH, across all [CatalogService] instances in this isolate, so
  /// a stale snapshot can never delete or overwrite newer cache state. The
  /// lock is NOT reentrant: only the `*Unlocked` helpers may be called
  /// from inside a critical section.
  ///
  /// Two instances pointed at different documents directories do not
  /// contend; two pointed at the same one always do. See
  /// [_cacheLocksByPath] for the isolate/process scope caveat.
  /// Resolves the cache [File] EXACTLY ONCE, derives the lock key from
  /// that same resolved file, and hands the file to [action]. Nothing
  /// inside the critical section may resolve the path again.
  ///
  /// This single-resolution rule is load-bearing, not tidiness. Resolving
  /// the key separately from the file the work uses allowed a first
  /// failed resolution to pick a fallback key while a later, successful
  /// resolution inside the section operated on the REAL path — so two
  /// instances could mutate the same cache under different locks, and a
  /// v8 write could land on top of a v9 one. There is therefore no
  /// fallback key: if the path cannot be resolved, the operation does not
  /// run at all and [onPathUnresolved] supplies a fail-closed result.
  Future<T> _withCacheLock<T>(
    Future<T> Function(File cacheFile) action, {
    required T Function(Object error) onPathUnresolved,
  }) async {
    final File cacheFile;
    try {
      cacheFile = await _cacheFile();
    } catch (e) {
      // Fail closed. Never retry resolution under another lock.
      return onPathUnresolved(e);
    }
    final key = cacheFile.path;
    // Registration below is synchronous — no await between reading the
    // current tail and installing the new one — so within an isolate the
    // read-modify-write of the map cannot interleave.
    final previous = _cacheLocksByPath[key] ?? Future<void>.value();
    final completer = Completer<void>();
    _cacheLocksByPath[key] = completer.future;
    try {
      await previous;
      return await action(cacheFile);
    } finally {
      completer.complete();
      // Drop the entry only when nobody queued behind us, so the map does
      // not grow without bound across sessions.
      if (identical(_cacheLocksByPath[key], completer.future)) {
        _cacheLocksByPath.remove(key);
      }
    }
  }

  /// Logs and returns the fail-closed state used when the cache path
  /// itself cannot be resolved.
  _CacheState _unresolvedCacheState(Object error) {
    final state = _CacheState.unknown('docs_dir_${error.runtimeType}');
    logEvent(
      'catalog_cache_read_indeterminate',
      {'reason': state.reason ?? 'unknown'},
      level: LogLevel.warn,
    );
    return state;
  }

  /// Classifies the on-device cache into exactly one of four states.
  ///
  /// The distinction that matters is INVALID vs UNKNOWN:
  ///   * INVALID is positively established — the bytes were read and the
  ///     content is unusable (oversized, unparseable, contract failure,
  ///     bad version). Such a cache may be deleted.
  ///   * UNKNOWN is indeterminate — an I/O error prevented us from
  ///     learning anything about the content. The cache may still hold a
  ///     HIGHER valid generation, so it must never be deleted and must
  ///     never be treated as "no floor".
  ///
  /// Never throws.
  Future<_CacheState> _readCacheStateUnlocked(File cacheFile) async {
    final state = await _classifyCacheUnlocked(cacheFile);
    switch (state.kind) {
      case _CacheStateKind.invalid:
        logEvent(
          'catalog_cache_invalid',
          {
            'reason': state.reason ?? 'unknown',
            if (state.detailBytes != null) 'bytes': state.detailBytes,
          },
          level: LogLevel.warn,
        );
      case _CacheStateKind.unknown:
        logEvent(
          'catalog_cache_read_indeterminate',
          {'reason': state.reason ?? 'unknown'},
          level: LogLevel.warn,
        );
      case _CacheStateKind.absent:
      case _CacheStateKind.valid:
        break;
    }
    return state;
  }

  Future<_CacheState> _classifyCacheUnlocked(File cacheFile) async {
    try {
      if (!await cacheFile.exists()) return const _CacheState.absent();
    } catch (e) {
      return _CacheState.unknown('exists_${e.runtimeType}');
    }
    // Size cap FIRST — the same [maxBodyBytes] gate applied to a remote
    // body. An oversized cache is positively invalid without being read
    // or parsed, so it can neither be served nor contribute a version
    // watermark.
    int lengthBytes;
    try {
      lengthBytes = await cacheFile.length();
    } catch (e) {
      return _CacheState.unknown('length_${e.runtimeType}');
    }
    if (lengthBytes > maxBodyBytes) {
      return _CacheState.invalid('oversized', detailBytes: lengthBytes);
    }
    // Read BYTES, not a String: `readAsString` decodes UTF-8 and
    // silently DISCARDS a leading BOM, which would make the cache lane
    // accept a byte sequence the publisher rejects. The bytes let the
    // identical BOM rule apply here and on the remote lane.
    Uint8List bytes;
    try {
      bytes = await cacheFile.readAsBytes();
    } catch (e) {
      // FileSystemException and anything else I/O shaped: indeterminate.
      return _CacheState.unknown('read_${e.runtimeType}');
    }
    if (startsWithUtf8Bom(bytes)) {
      return const _CacheState.invalid('utf8_bom');
    }
    String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      // Bytes were read but are not valid UTF-8 — positively malformed.
      return const _CacheState.invalid('not_utf8');
    }
    Object? raw;
    try {
      raw = jsonDecode(content);
    } catch (e) {
      return const _CacheState.invalid('parse_error');
    }
    if (raw is! Map<String, dynamic>) {
      return const _CacheState.invalid('root_not_object');
    }
    final validation = _validateDecoded(raw);
    if (!validation.isValid) {
      return _CacheState.invalid(validation.reason ?? 'unknown');
    }
    final versionState = _classifyVersion(raw['version']);
    if (versionState.value == null) {
      return _CacheState.invalid('version_${versionState.failureReason}');
    }
    return _CacheState.valid(validation.parables!, versionState.value!);
  }

  /// Deletes the cache. Callers MUST have positively established that the
  /// cache is invalid or stale first — an UNKNOWN cache is never deleted.
  Future<void> _deleteCacheUnlocked(File cacheFile,
      {required String reason}) async {
    try {
      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }
      logEvent('catalog_cache_deleted', {'reason': reason});
    } catch (e) {
      logEvent(
        'catalog_cache_delete_failed',
        {'reason': reason, 'error_type': e.runtimeType.toString()},
        level: LogLevel.warn,
      );
    }
  }

  Future<void> _persistUnlocked(File cacheFile, String body) async {
    await cacheFile.parent.create(recursive: true);
    // Unique per-write temp name: a fixed `.tmp` sibling would let two
    // writers (this process and any other holder of the same sandbox)
    // interleave and rename a half-written body over the cache.
    final tmp = File(
      '${cacheFile.path}.$pid.${DateTime.now().microsecondsSinceEpoch}'
      '.${_tmpWriteCounter++}.tmp',
    );
    try {
      await tmp.writeAsString(body, flush: true);
      await tmp.rename(cacheFile.path);
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {
        // A leftover uniquely-named temp file is inert.
      }
    }
  }

  // ── Fetch + validation ─────────────────────────────────────────────────

  Future<_FetchOutcome> _fetchOnce(Uri url) async {
    try {
      final response = await _client.get(url).timeout(fetchTimeout);
      if (response.statusCode == 404) {
        return _FetchOutcome.notFound();
      }
      if (response.statusCode != 200) {
        return _FetchOutcome.transient();
      }
      return _FetchOutcome.success(bodyBytes: response.bodyBytes);
    } catch (_) {
      return _FetchOutcome.transient();
    }
  }

  /// Classifies a raw `version` value. Only a positive `int` yields a
  /// usable generation. In Dart, `bool` is not `int` and a JSON `6.0`
  /// decodes as `double`, so both classify as `wrong_type`.
  _VersionState _classifyVersion(Object? raw) {
    if (raw == null) return const _VersionState.invalid('missing');
    if (raw is! int) return const _VersionState.invalid('wrong_type');
    if (raw <= 0) return const _VersionState.invalid('non_positive');
    return _VersionState.valid(raw);
  }

  /// Content validation shared by bundled, cache, and remote catalogs:
  /// `parables` must be a non-empty list of parseable entries within the
  /// entry cap, and every translation id must pass the allowlist. Version
  /// handling is separate ([_classifyVersion]) because bundled and
  /// external catalogs fail differently on a bad version.
  _ValidationResult _validateDecoded(Map<String, dynamic> decoded) {
    final parablesRaw = decoded['parables'];
    if (parablesRaw is! List) {
      return _ValidationResult.invalid(
        _ValidationFailure.schema,
        'missing_parables_list',
      );
    }
    if (parablesRaw.isEmpty) {
      return _ValidationResult.invalid(
        _ValidationFailure.schema,
        'empty_parables',
      );
    }
    if (parablesRaw.length > maxEntries) {
      return _ValidationResult.invalid(
        _ValidationFailure.entryCount,
        'too_many_entries',
      );
    }
    final parables = <Parable>[];
    final seenStoryIds = <String>{};
    for (final entry in parablesRaw) {
      if (entry is! Map<String, dynamic>) {
        return _ValidationResult.invalid(
          _ValidationFailure.schema,
          'entry_not_map',
        );
      }
      final contractFailure = _validateEntryContract(entry, seenStoryIds);
      if (contractFailure != null) return contractFailure;
      try {
        parables.add(Parable.fromJson(entry));
      } catch (e) {
        return _ValidationResult.invalid(
          _ValidationFailure.schema,
          'parse_error_${e.runtimeType}',
        );
      }
    }
    return _ValidationResult.valid(parables: parables);
  }

  /// The active catalog contract for a single entry. Returns `null` when
  /// the entry is acceptable, otherwise the rejection.
  _ValidationResult? _validateEntryContract(
    Map<String, dynamic> entry,
    Set<String> seenStoryIds,
  ) {
    // Identity + serving anchors must be present AND carry real content.
    for (final key in _requiredNonBlankFields) {
      final value = entry[key];
      if (value is! String) {
        return _ValidationResult.invalid(
          _ValidationFailure.schema,
          'missing_$key',
        );
      }
      if (isBlankIdentity(value)) {
        return _ValidationResult.invalid(
          _ValidationFailure.schema,
          'blank_$key',
        );
      }
    }

    // Story identity must be unique: duplicates make selection,
    // favorites, history and resume ambiguous and let one entry silently
    // shadow another.
    if (!seenStoryIds.add(entry['storyId'] as String)) {
      return _ValidationResult.invalid(
        _ValidationFailure.schema,
        'duplicate_story_id',
      );
    }

    if (!activeStorytellingModes.contains(entry['storytellingMode'])) {
      return _ValidationResult.invalid(
        _ValidationFailure.schema,
        'unsupported_storytelling_mode',
      );
    }

    // EXACT canonical match — nothing is trimmed or upper-cased. A value
    // such as 'kjv' is NOT normalized to 'KJV': `Parable.fromJson` maps
    // any languageStyle that is not literally 'KJV' to 'WEB', so
    // accepting it would silently serve a KJV story with WEB diction.
    final translationId = entry['translationId'];
    if (translationId != null) {
      if (translationId is! String) {
        return _ValidationResult.invalid(
          _ValidationFailure.schema,
          'wrong_type_translation_id',
        );
      }
      if (!_canonicalTranslationIds.contains(translationId)) {
        return _ValidationResult.invalid(
          _ValidationFailure.translation,
          'non_canonical_translation_id',
        );
      }
    }
    final languageStyle = entry['languageStyle'];
    if (languageStyle != null) {
      if (languageStyle is! String) {
        return _ValidationResult.invalid(
          _ValidationFailure.schema,
          'wrong_type_language_style',
        );
      }
      if (!activeLanguageStyles.contains(languageStyle)) {
        return _ValidationResult.invalid(
          _ValidationFailure.translation,
          'non_canonical_language_style',
        );
      }
    }

    final storyLength = entry['storyLength'];
    if (storyLength != null &&
        (storyLength is! String ||
            !activeStoryLengths.contains(storyLength))) {
      return _ValidationResult.invalid(
        _ValidationFailure.schema,
        'unsupported_story_length',
      );
    }

    // textFilePath is the one path without which a story cannot be served
    // at all.
    final textFilePath = entry['textFilePath'];
    if (textFilePath is! String ||
        !_isSafeRelativeAssetPath(textFilePath)) {
      return _ValidationResult.invalid(
        _ValidationFailure.schema,
        'unsafe_or_missing_text_file_path',
      );
    }

    for (final key in _optionalPathFields) {
      final value = entry[key];
      if (value == null) continue;
      if (value is! String) {
        return _ValidationResult.invalid(
          _ValidationFailure.schema,
          'wrong_type_$key',
        );
      }
      if (value.isEmpty) continue;
      if (!_isSafeRelativeAssetPath(value)) {
        return _ValidationResult.invalid(
          _ValidationFailure.schema,
          'unsafe_path_$key',
        );
      }
    }

    return null;
  }
}

// ── Internal value types ─────────────────────────────────────────────────

/// The bundled catalog after load + validation. Exactly one of three
/// states: trusted (content + version valid), versionInvalid (content
/// valid, version unusable), contentInvalid (asset unusable).
class _BundledBaseline {
  final List<Parable>? parables;
  final int? version;
  final String? versionFailureReason;
  final String? contentFailureReason;

  const _BundledBaseline.trusted(List<Parable> this.parables, int this.version)
      : versionFailureReason = null,
        contentFailureReason = null;

  const _BundledBaseline.versionInvalid(
    List<Parable> this.parables,
    String this.versionFailureReason,
  )   : version = null,
        contentFailureReason = null;

  const _BundledBaseline.contentInvalid(String this.contentFailureReason)
      : parables = null,
        version = null,
        versionFailureReason = null;

  bool get contentValid => parables != null;
  bool get trusted => contentValid && version != null;
}

/// Outcome of the single critical section that re-establishes the version
/// floor and (only if it still holds) replaces the cache.
enum _PersistDecisionKind {
  accepted,
  versionNotHigher,
  persistFailed,
  cacheUnknown,
}

class _PersistDecision {
  final _PersistDecisionKind kind;
  final int? cachedVersion;
  final String? reason;

  const _PersistDecision._(this.kind, {this.cachedVersion, this.reason});

  const _PersistDecision.accepted(int? cachedVersion)
      : this._(_PersistDecisionKind.accepted, cachedVersion: cachedVersion);

  const _PersistDecision.versionNotHigher(int? cachedVersion)
      : this._(
          _PersistDecisionKind.versionNotHigher,
          cachedVersion: cachedVersion,
        );

  const _PersistDecision.persistFailed(String reason)
      : this._(_PersistDecisionKind.persistFailed, reason: reason);

  const _PersistDecision.cacheUnknown(String? reason)
      : this._(_PersistDecisionKind.cacheUnknown, reason: reason);
}

/// How much is positively known about the on-device cache.
enum _CacheStateKind {
  /// The cache file does not exist. Nothing to serve, no floor to raise.
  absent,

  /// The bytes were read and are positively unusable. Safe to delete.
  invalid,

  /// Fully validated content with a positive integer generation.
  valid,

  /// Indeterminate — an I/O failure prevented classification. The cache
  /// may still hold a HIGHER valid generation, so it must be preserved
  /// and must block any replacement that depends on knowing the floor.
  unknown,
}

class _CacheState {
  final _CacheStateKind kind;
  final List<Parable>? parables;
  final int? version;
  final String? reason;

  /// Observed byte length, carried only for the oversized rejection so the
  /// telemetry can report what was measured.
  final int? detailBytes;

  const _CacheState.absent()
      : kind = _CacheStateKind.absent,
        parables = null,
        version = null,
        reason = null,
        detailBytes = null;

  const _CacheState.invalid(String this.reason, {this.detailBytes})
      : kind = _CacheStateKind.invalid,
        parables = null,
        version = null;

  const _CacheState.unknown(String this.reason)
      : kind = _CacheStateKind.unknown,
        parables = null,
        version = null,
        detailBytes = null;

  const _CacheState.valid(List<Parable> this.parables, int this.version)
      : kind = _CacheStateKind.valid,
        reason = null,
        detailBytes = null;

  bool get isValid => kind == _CacheStateKind.valid;
  bool get isUnknown => kind == _CacheStateKind.unknown;
}

class _VersionState {
  final int? value;
  final String? failureReason;

  const _VersionState.valid(int this.value) : failureReason = null;
  const _VersionState.invalid(String this.failureReason) : value = null;
}

enum _ValidationFailure { schema, translation, entryCount }

class _ValidationResult {
  final bool isValid;
  final List<Parable>? parables;
  final _ValidationFailure? failure;
  final String? reason;

  const _ValidationResult._({
    required this.isValid,
    this.parables,
    this.failure,
    this.reason,
  });

  factory _ValidationResult.valid({required List<Parable> parables}) =>
      _ValidationResult._(isValid: true, parables: parables);

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
  /// RAW response bytes. Deliberately not a decoded `String`: the
  /// decoding charset must be UTF-8 per RFC 8259, not whatever
  /// package:http infers from the Content-Type header (which defaults to
  /// latin-1 when no charset is given).
  final List<int>? bodyBytes;
  final bool notFound;
  final bool isTransientFailure;

  const _FetchOutcome._({
    this.bodyBytes,
    this.notFound = false,
    this.isTransientFailure = false,
  });

  factory _FetchOutcome.success({required List<int> bodyBytes}) =>
      _FetchOutcome._(bodyBytes: bodyBytes);

  factory _FetchOutcome.notFound() => const _FetchOutcome._(notFound: true);

  factory _FetchOutcome.transient() =>
      const _FetchOutcome._(isTransientFailure: true);
}
