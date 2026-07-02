import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../features/journey/journey.dart';
import '../models/parable.dart';
import '../models/user_preferences.dart';
import '../core/app_logger.dart';
import '../core/story_length_bucket.dart';
import '../core/mood_similarity.dart';
import '../core/mood_expansion_engine.dart';
import '../core/seasonal_calendar.dart';
import 'catalog_service.dart';
import 'storage_service.dart';
import 'relatability_matcher.dart';

/// Why the last audio resolution attempt failed (Android only).
/// Read via [ParableService.lastAudioError] after [getAudioFile] returns null.
enum AudioResolveError {
  none,
  offlineNotCached,
  downloadFailed,
  remoteNotFound,
}

/// Slice 4: which audio asset the three-tier resolver is loading.
/// Threaded into the `audio_source` telemetry event so consumers can
/// distinguish story playback from reflection playback.
enum AudioKind { story, reflection }

/// Parable Service - handles parable selection, generation, and management
/// Based on SPEC.md Features #4, #6, #14, #15
class ParableService {
  /// Soft cache budget for the managed Android audio cache (SPEC Feature 27,
  /// Smart Offline Library v1). The eviction routine works toward this target
  /// but may exceed it when favorited audio alone is larger.
  static const int kAudioCacheBudgetBytes = 600 * 1024 * 1024;

  /// How recently a story must have been played to count as "seen" by the
  /// MoodExpansionEngine. Stories outside this window stay in the play log
  /// (for LRP ordering) but are eligible as Tier 1 unseen picks again.
  static const Duration _unseenWindow = Duration(days: 30);

  /// High-intensity moods that trigger the MICRO serving bias for Short
  /// length: when the user is anxious, hurting, or weary, prefer a shorter
  /// emotionally-focused scripture extract first. See `feedback_micro_stories.md`
  /// in agent memory and the "Micro serving bias" section.
  static const Set<String> _microBiasMoods = {
    'anxious',
    'hurting',
    'weary',
  };

  /// Probability that an eligible MICRO-biased pick chooses a MICRO story
  /// (vs. falling through to normal exact-mood Short serving). Tuned so users
  /// see comforting MICROs primarily, but also receive regular Shorts often
  /// enough to avoid lock-in.
  static const double _microBiasProbability = 0.70;

  /// Pluggable [0, 1) sampler for the MICRO bias dice roll. Defaults to
  /// [math.Random.nextDouble]; tests override with a deterministic stub via
  /// [setMicroBiasRandomForTesting].
  static double Function() _microBiasRandom = _defaultRandom;
  static final math.Random _sharedRandom = math.Random();
  static double _defaultRandom() => _sharedRandom.nextDouble();

  /// Test-only seam to make the 70/30 dice deterministic. Returns the prior
  /// sampler so tests can restore it in tearDown.
  @visibleForTesting
  static double Function() setMicroBiasRandomForTesting(
      double Function() sampler) {
    final previous = _microBiasRandom;
    _microBiasRandom = sampler;
    return previous;
  }

  /// Reset the bias RNG to the default. Use in tearDown after overriding.
  @visibleForTesting
  static void resetMicroBiasRandomForTesting() {
    _microBiasRandom = _defaultRandom;
  }

  /// Mutable budget used by the eviction routine. Defaults to the public
  /// constant; tests override via [setAudioCacheBudgetForTesting] to avoid
  /// allocating real 600 MB fixtures.
  static int _audioCacheBudgetBytes = kAudioCacheBudgetBytes;

  final StorageService _storage;
  final String? _externalStoragePath;
  bool _useAssets = false;
  final bool testMode;
  final RelatabilityMatcher _matcher = RelatabilityMatcher();

  /// Phase 2 / Slice 2: remote catalog client. Always present; the
  /// constructor accepts an injected instance for tests and falls back
  /// to a default `CatalogService()` otherwise. Skipped entirely when
  /// [testMode] is true so unit tests don't hit real network or assume
  /// a docs-dir cache.
  final CatalogService _catalog;

  /// Phase 2 / Slice 2: hard memoization of the per-launch manifest load.
  /// First [_loadManifest] call resolves the catalog cascade once and
  /// emits a single [manifest_source] log; all subsequent callers receive
  /// the same Future. Tests reset via [resetManifestCacheForTesting].
  Future<List<Parable>>? _manifestLoadFuture;

  /// Smart Offline Library v1: cache-relative path of the most recent file
  /// returned by [getAudioFile]. Excluded from eviction so the currently-
  /// playing track is never deleted underneath just_audio.
  ///
  /// CONSTRAINT: this field exists for ONE purpose — protect the in-use
  /// audio file from eviction. It must NOT grow into a playback-state
  /// system (no Set, no preload list, no public getters, no AudioService
  /// coordination). See plan: "Constraint: _currentAudioRelativePath Stays
  /// Minimal".
  String? _currentAudioRelativePath;

  /// Why the last [getAudioFile] call returned null (Android only).
  AudioResolveError _lastAudioError = AudioResolveError.none;
  AudioResolveError get lastAudioError => _lastAudioError;

  /// Reentrancy guard for [_evictIfOverBudget].
  bool _evictionInProgress = false;

  ParableService(this._storage,
      [this._externalStoragePath, this.testMode = false, CatalogService? catalog])
      : _catalog = catalog ?? CatalogService();

  /// Test-only seam: clear the memoized manifest load so a subsequent
  /// [_loadManifest] call re-runs the catalog cascade and re-emits the
  /// [manifest_source] log. Production code MUST NOT call this — the
  /// manifest is intentionally pinned for the lifetime of the launch.
  @visibleForTesting
  void resetManifestCacheForTesting() {
    _manifestLoadFuture = null;
    _useAssets = false;
  }

  /// Get the parable library directory
  Future<Directory> _getParableLibraryDir() async {
    // Check for external storage first (T9 drive, per SPEC.md Feature #15)
    if (_externalStoragePath != null) {
      final externalDir = Directory(_externalStoragePath);
      if (await externalDir.exists()) {
        return externalDir;
      }
    }

    // Fall back to app documents directory
    final appDir = await getApplicationDocumentsDirectory();
    final parableDir = Directory('${appDir.path}/parables');
    if (!await parableDir.exists()) {
      await parableDir.create(recursive: true);
    }
    return parableDir;
  }

  /// Load manifest of available parables. Hard-memoized for the lifetime
  /// of this [ParableService] instance: the first call resolves the
  /// catalog cascade (Phase 2 / Slice 2) and the result is reused for
  /// every subsequent caller. Tests reset via
  /// [resetManifestCacheForTesting].
  Future<List<Parable>> _loadManifest() {
    return _manifestLoadFuture ??= _resolveManifest();
  }

  /// Single-shot manifest resolution. In production, goes through
  /// [CatalogService.loadCatalog] (cache → bundled) and kicks off a
  /// background remote refresh. In [testMode], preserves the original
  /// bundled-only path verbatim so existing logic/filter tests don't
  /// need to mock the catalog client.
  Future<List<Parable>> _resolveManifest() async {
    try {
      List<Parable> parables = [];
      int totalEntries = 0;
      int skippedEntries = 0;

      // Slice 2: production cascade — CatalogService.loadCatalog()
      // returns cache when a valid cached copy exists, otherwise reads
      // bundled assets via rootBundle. On exception (e.g., bundled
      // manifest missing), fall through to the legacy docs-dir path.
      if (!testMode) {
        try {
          final result = await _catalog.loadCatalog();
          _useAssets = true;
          final src = result.source == CatalogSource.cache
              ? 'cache'
              : 'bundled';
          debugPrint(
              '📚 Loading ${result.parables.length} parables (source=$src)');
          logEvent('story_pool_loaded', {
            'total_count': result.parables.length,
            'valid_count': result.parables.length,
            'skipped_count': 0,
            'source': src == 'cache' ? 'catalog_cache' : 'bundled_assets',
          });
          logEvent('manifest_source', {
            'source': src,
            'entry_count': result.parables.length,
            if (result.version != null) 'version': result.version,
          });
          // Fire-and-forget background refresh. CatalogService handles
          // its own retry, validation, and telemetry. Errors are
          // swallowed so a refresh failure cannot crash the app.
          unawaited(_catalog.refreshFromRemote());
          return result.parables;
        } catch (e) {
          debugPrint(
              'Catalog cascade failed, falling back to legacy manifest load: $e');
        }
      }

      // First try loading from bundled assets (for testing)
      try {
        final jsonContent =
            await rootBundle.loadString('assets/stories/manifest.json');
        final manifestData = jsonDecode(jsonContent) as Map<String, dynamic>;
        final parablesList = manifestData['parables'] as List<dynamic>? ?? [];
        totalEntries = parablesList.length;
        debugPrint(
            '📚 Loading ${parablesList.length} parables from bundled assets');
        _useAssets = true; // Flag to use assets for audio/text files too

        // Validate each entry
        for (var json in parablesList) {
          final parable = Parable.fromJson(json as Map<String, dynamic>);

          // In test mode, skip audio validation to allow testing filtering logic
          if (testMode) {
            parables.add(parable);
            continue;
          }

          // Bundled assets declared in pubspec.yaml are guaranteed to exist;
          // skip heavy rootBundle.load() validation that loads entire MP3s into
          // memory and can cause out-of-memory crashes on device.
          parables.add(parable);
        }

        debugPrint(
            '✅ Manifest validation: $totalEntries total, ${parables.length} valid, $skippedEntries skipped');

        // Log story pool loaded event
        logEvent('story_pool_loaded', {
          'total_count': totalEntries,
          'valid_count': parables.length,
          'skipped_count': skippedEntries,
          'source': 'bundled_assets',
        });

        return parables;
      } catch (assetError) {
        debugPrint(
            'No bundled assets found, checking documents directory: $assetError');
      }

      // Fall back to documents directory
      final dir = await _getParableLibraryDir();
      final manifestFile = File('${dir.path}/manifest.json');

      if (!await manifestFile.exists()) {
        debugPrint('Parable manifest not found in documents directory');
        return [];
      }

      final jsonContent = await manifestFile.readAsString();
      final manifestData = jsonDecode(jsonContent) as Map<String, dynamic>;
      final parablesList = manifestData['parables'] as List<dynamic>? ?? [];
      totalEntries = parablesList.length;

      // Validate each entry in documents directory
      for (var json in parablesList) {
        final parable = Parable.fromJson(json as Map<String, dynamic>);

        // In test mode, skip audio validation
        if (testMode) {
          parables.add(parable);
          continue;
        }

        // Check if audio file exists
        if (parable.audioFilePath != null) {
          final audioFile = File('${dir.path}/${parable.audioFilePath}');
          if (await audioFile.exists()) {
            parables.add(parable);
          } else {
            debugPrint('⚠️ Skipping ${parable.storyId}: audio file missing');

            // Log audio asset missing
            logEvent(
                'audio_asset_missing',
                {
                  'story_id': parable.storyId,
                  'expected_path': '${dir.path}/${parable.audioFilePath}',
                },
                level: LogLevel.warn);

            skippedEntries++;
          }
        } else {
          // Text-only story
          parables.add(parable);
        }
      }

      debugPrint(
          '✅ Manifest validation: $totalEntries total, ${parables.length} valid, $skippedEntries skipped');

      // Log story pool loaded event
      logEvent('story_pool_loaded', {
        'total_count': totalEntries,
        'valid_count': parables.length,
        'skipped_count': skippedEntries,
        'source': 'documents_directory',
      });

      return parables;
    } catch (e) {
      debugPrint('❌ Error loading parable manifest: $e');
      logError('manifest_load_failed', 'ParableService._loadManifest',
          errorMessage: e.toString());
      return [];
    }
  }

  /// Return every Traditional parable in the loaded manifest.
  ///
  /// Minimal read-only surface introduced for PALs Paths (Phase 2, SPEC
  /// Feature 50). This method MUST NOT invoke mood expansion, non-repeat
  /// logic, or any other serving filter — it is a pure snapshot of
  /// `storytellingMode == "traditional"` entries, used by [PathService]
  /// and [SearchService] to build their own deterministic filters.
  ///
  /// Creative stories are filtered out at this layer so downstream
  /// consumers cannot accidentally serve them via a path or search
  /// (Story Mode Non-Blur Invariant #6).
  Future<List<Parable>> getAllTraditionalParables() async {
    final all = await _loadManifest();
    return all.where((p) => p.storytellingMode == 'traditional').toList();
  }

  /// Canonical variant resolution: find a sibling of [current] that matches
  /// [storyLength] and [languageStyle], preserving bibleStoryKey,
  /// storytellingMode, and kidFriendly.
  ///
  /// Used by LengthPickerScreen (path mode), ParablePlayerScreen (in-player
  /// switching), and any future consumer that needs deterministic variant
  /// lookup. Does NOT invoke mood expansion or non-repeat logic.
  ///
  /// Returns null when no matching variant exists.
  Future<Parable?> resolveVariant({
    required Parable current,
    required String storyLength,
    required String languageStyle,
  }) async {
    final all = await _loadManifest();
    for (final p in all) {
      if (p.bibleStoryKey == current.bibleStoryKey &&
          p.storytellingMode == current.storytellingMode &&
          p.kidFriendly == current.kidFriendly &&
          p.languageStyle == languageStyle &&
          p.storyLength == storyLength) {
        return p;
      }
    }
    return null;
  }

  /// Return the set of (storyLength, languageStyle) pairs available as
  /// siblings of [current]. The caller uses this to enable/disable chips
  /// in the player-screen variant controls.
  ///
  /// A variant is considered available only when its manifest entry has a
  /// non-empty `audioFilePath` AND that path is present in
  /// [bundledAudioPaths] (the set of asset-bundled audio paths). R2-served
  /// variants are deliberately excluded here — chip availability reflects
  /// only what is playable from the bundle.
  ///
  /// Returns a map: { 'short': {'WEB', 'KJV'}, 'full': {'WEB'}, ... }
  Future<Map<String, Set<String>>> getAvailableVariants(
    Parable current,
    Set<String> bundledAudioPaths,
  ) async {
    if (!current.hasBibleStoryKey) return {};
    final all = await _loadManifest();
    final result = <String, Set<String>>{};
    for (final p in all) {
      if (p.bibleStoryKey == current.bibleStoryKey &&
          p.storytellingMode == current.storytellingMode &&
          p.kidFriendly == current.kidFriendly &&
          p.storyLength != null &&
          p.audioFilePath != null &&
          p.audioFilePath!.isNotEmpty &&
          bundledAudioPaths.contains(p.audioFilePath!)) {
        result.putIfAbsent(p.storyLength!, () => {}).add(p.languageStyle);
      }
    }
    return result;
  }

  /// Get eligible parables based on user preferences and mood
  /// Per SPEC.md Feature #4: Parable Generation / Selection Engine
  /// Updated for Story Mode Contracts v2 (SPEC.md)
  Future<List<Parable>> getEligibleParables({
    required String mood,
    required StoryLengthBucket lengthBucket,
    required UserPreferences userPrefs,
  }) async {
    final allParables = await _loadManifest();

    // Language style filter (WEB or KJV) - Contracts v2: presentation diction
    // Stories are filtered by languageStyle to match user's preference
    final languageStyle = userPrefs.languageStyle;

    // Log filters being applied (analytics only, not verbose debug output)
    // NOTE: length_bucket is canonical - no minute-based fields in telemetry (INVARIANTS.md)
    logEvent('filters_applied', {
      'kid_mode': userPrefs.kidFriendlyOnly,
      'storytelling_mode': userPrefs.storytellingMode,
      'language_style': languageStyle,
      'mood': mood,
      'length_bucket': lengthBucket.name,
      'pool_size': allParables.length,
    });

    // Filter by criteria (no per-item logging - use debugVerbose for troubleshooting)
    final eligible = allParables.where((p) {
      // Match mood (always required)
      if (p.mood != mood) return false;

      // Match length bucket (uses compatibility mapping from minute-based metadata)
      if (p.lengthBucket != lengthBucket) return false;

      // Match language style (WEB or KJV) - Contracts v2
      // Use story's languageStyle field for filtering
      if (p.languageStyle != languageStyle) return false;

      // ADR-010: Traditional stories MUST have bibleSourceRef AND bibleStoryKey
      // Stories without these fields are EXCLUDED (not guessed)
      if (!p.hasBibleSourceRef) {
        logEvent(
            'story_excluded',
            {
              'story_id': p.storyId,
              'reason': 'traditional_missing_bible_source_ref',
            },
            level: LogLevel.warn);
        return false;
      }
      if (!p.hasBibleStoryKey) {
        logEvent(
            'story_excluded',
            {
              'story_id': p.storyId,
              'reason': 'traditional_missing_bible_story_key',
            },
            level: LogLevel.warn);
        return false;
      }

      // Match kid-friendly filter (CRITICAL FOR PROPER CONTENT SEGREGATION)
      // Kid mode ON: ONLY kid-friendly stories
      // Kid mode OFF: ONLY non-kid-friendly stories (adult content)
      if (userPrefs.kidFriendlyOnly) {
        if (!p.kidFriendly) return false;
      } else {
        if (p.kidFriendly) return false;
      }

      return true;
    }).toList();

    // CRITICAL SAFETY CHECK: Verify content segregation is working
    if (userPrefs.kidFriendlyOnly) {
      // Kid mode: ensure NO non-kid-friendly content leaked through
      final nonKidFriendlyCount = eligible.where((p) => !p.kidFriendly).length;
      if (nonKidFriendlyCount > 0) {
        debugPrint('🚨🚨🚨 CRITICAL KID SAFETY VIOLATION 🚨🚨🚨');
        debugPrint(
            'Found $nonKidFriendlyCount non-kid-friendly parables in filtered results!');
        debugPrint(
            'Kid mode is ON but non-kid-friendly content passed through!');
        debugPrint(
            'This is a CRITICAL BUG that exposes children to inappropriate content!');

        // Log kid mode guard failure
        logEvent(
            'kid_mode_guard_fail',
            {
              'violation_reason': 'non_kid_friendly_content_leaked',
              'leaked_count': nonKidFriendlyCount,
            },
            level: LogLevel.error);

        // In debug mode, throw assertion to catch this immediately
        assert(
          false,
          '🚨 KID SAFETY VIOLATION: Non-kid-friendly parables returned when kidFriendlyOnly=true',
        );

        // In production, filter them out as emergency safety measure
        return eligible.where((p) => p.kidFriendly).toList();
      }
      debugPrint(
          '✅ Kid safety check passed: All ${eligible.length} parables are kid-friendly');

      // Log successful kid mode guard
      logEvent('kid_mode_guard_pass', {
        'eligible_count': eligible.length,
      });
    } else {
      // Adult mode: ensure NO kid-friendly content leaked through
      final kidFriendlyCount = eligible.where((p) => p.kidFriendly).length;
      if (kidFriendlyCount > 0) {
        debugPrint(
            '🚨 ADULT MODE VIOLATION: Found $kidFriendlyCount kid-friendly parables!');
        debugPrint('Adult mode should ONLY return adult content!');

        // In debug mode, throw assertion
        assert(
          false,
          '🚨 ADULT MODE VIOLATION: Kid-friendly parables returned when kidFriendlyOnly=false',
        );

        // In production, filter them out
        return eligible.where((p) => !p.kidFriendly).toList();
      }
      debugPrint(
          '✅ Adult mode check passed: All ${eligible.length} parables are adult content');
    }

    return eligible;
  }

  /// Preview the best-matching bibleStoryKey for a mood and user text,
  /// ignoring story length. Used to retrieve a framing line before the
  /// length picker is shown.
  ///
  /// Filters by mood, storytelling mode, language style, and kid safety
  /// (same as [getEligibleParables] minus the length constraint).
  /// Deduplicates by bibleStoryKey, then ranks by relatability if
  /// [userText] is provided.
  Future<String?> previewBibleStoryKey({
    required String mood,
    required UserPreferences userPrefs,
    String? userText,
  }) async {
    final allParables = await _loadManifest();
    final languageStyle = userPrefs.languageStyle;

    final candidates = allParables.where((p) {
      if (p.mood != mood) return false;
      if (p.storytellingMode != userPrefs.storytellingMode) return false;
      if (p.languageStyle != languageStyle) return false;
      if (p.storytellingMode == 'traditional' && !p.hasBibleStoryKey) {
        return false;
      }
      if (userPrefs.kidFriendlyOnly) {
        if (!p.kidFriendly) return false;
      } else {
        if (p.kidFriendly) return false;
      }
      return true;
    }).toList();

    if (candidates.isEmpty) return null;

    // Deduplicate by bibleStoryKey (same key exists across lengths)
    final seen = <String>{};
    final unique = candidates
        .where((p) => p.bibleStoryKey != null && seen.add(p.bibleStoryKey!))
        .toList();

    if (unique.isEmpty) return null;

    // Rank by relatability if user text provided
    if (userText != null && userText.isNotEmpty && unique.length > 1) {
      final ranked = _matcher.rankByRelatability(userText, unique);
      return ranked.first.bibleStoryKey;
    }

    return unique.first.bibleStoryKey;
  }

  /// Select a parable using mood expansion (SPEC 15b) and non-repeat serving.
  /// Per SPEC.md Features #4 (Relatability), #14 (Non-Repeat), #15b (Mood Expansion).
  ///
  /// Selection algorithm:
  /// 1. Build eligible pools for exact + similar moods (length, mode, kid safety, language)
  /// 2. Apply 4-tier mood expansion via [MoodExpansionEngine] to pick winning tier
  /// 3. Within the winning tier, rank by relatability score (if userText provided)
  /// 4. Otherwise tie-break by seasonal/time-of-day boost, then LRP, then stable storyId
  Future<Parable?> selectParable({
    required String mood,
    required StoryLengthBucket lengthBucket,
    required UserPreferences userPrefs,
    String? userText,
    String? bibleStoryKey,
  }) async {
    // Build the full eligible pool across all moods that pass non-mood filters.
    // getEligibleParables already filters by length, mode, language, kid safety.
    final exactPool = await getEligibleParables(
      mood: mood,
      lengthBucket: lengthBucket,
      userPrefs: userPrefs,
    );

    // Also fetch pools for similar moods (kid mode adds the kid-only bridges so
    // a scared/sorry child can reach the triumphant stories — Furnace, Loving Father).
    final similarMoods =
        MoodSimilarity.getSimilar(mood, kidMode: userPrefs.kidFriendlyOnly);
    final similarPools = <Parable>[];
    for (final similarMood in similarMoods) {
      final pool = await getEligibleParables(
        mood: similarMood,
        lengthBucket: lengthBucket,
        userPrefs: userPrefs,
      );
      similarPools.addAll(pool);
    }

    // Combined pool for the engine (exact + similar, engine handles separation)
    var combinedPool = [...exactPool, ...similarPools];

    // Build the anti-repeat seen-set early so the MICRO bias check below can
    // honor it (a MICRO whose only candidate was recently played should not
    // hijack the selection). Same data drives the engine's anti-repeat below.
    final playHistory = await _storage.getPlayLog();
    final unseenWindow = DateTime.now().subtract(_unseenWindow);
    final recentStoryIds = <String>{
      for (final entry in playHistory.entries)
        if (entry.value.isAfter(unseenWindow)) entry.key,
    };

    // Diagnostics: capture true unseen counts BEFORE the MICRO bias narrows
    // the pool. Surfaces in the story_selected event so beta reports of
    // "same story repeating" can be triaged as a small-pool issue vs. a
    // selection bug without app-side instrumentation.
    final eligibleExactUnseenCount =
        exactPool.where((p) => !recentStoryIds.contains(p.storyId)).length;
    final eligibleSimilarUnseenCount =
        similarPools.where((p) => !recentStoryIds.contains(p.storyId)).length;

    // MICRO serving bias (70/30 weighted): for high-intensity moods
    // (anxious/hurting/weary) at Short length, weight selection toward MICRO
    // stories (shortScripture==true) without locking the user in.
    //
    //   • Eligibility gate: at least one UNSEEN EXACT-MOOD MICRO must exist.
    //     If not, the bias releases entirely and normal tiered serving runs
    //     so exact-mood non-MICRO Shorts surface before similar-mood content.
    //   • When eligible, roll a [0,1) dice:
    //       - dice <  _microBiasProbability → constrain pool to exact-mood
    //         unseen MICROs (the 70% path).
    //       - dice >= _microBiasProbability → exclude exact-mood unseen
    //         MICROs from the pool, letting the engine pick from the rest
    //         (the 30% path). The engine's Tier 1 then naturally favors
    //         exact-mood non-MICRO unseen Shorts.
    //   • Anti-repeat is preserved end-to-end via recentStoryIds.
    //   • Full and Long are unaffected — those buckets exclude MICRO before
    //     this block runs (lengthBucket gate + manifest length filter).
    // See `feedback_micro_stories.md` in agent memory.
    final microBiasApplied = lengthBucket == StoryLengthBucket.short &&
        _microBiasMoods.contains(mood);
    if (microBiasApplied) {
      final microPool =
          combinedPool.where((p) => p.shortScripture).toList(growable: false);
      final unseenExactMoodMicros = microPool
          .where((p) => p.mood == mood && !recentStoryIds.contains(p.storyId))
          .toList(growable: false);
      if (unseenExactMoodMicros.isNotEmpty) {
        final dice = _microBiasRandom();
        final tookMicroPath = dice < _microBiasProbability;
        debugPrint(
            '[ParableService] MICRO bias eligible for mood=$mood: '
            '${microPool.length} MICRO candidate(s), '
            '${unseenExactMoodMicros.length} unseen exact-mood, '
            'dice=${dice.toStringAsFixed(3)} → '
            '${tookMicroPath ? "micro_70" : "short_30"}');
        logEvent('micro_bias_applied', {
          'selected_mood': mood,
          'micro_pool_size': microPool.length,
          'unseen_exact_mood_micro_count': unseenExactMoodMicros.length,
          'combined_pool_size': combinedPool.length,
          'micro_bias_path': tookMicroPath ? 'micro_70' : 'short_30',
          'micro_bias_probability': _microBiasProbability,
        });
        if (tookMicroPath) {
          combinedPool = unseenExactMoodMicros;
        } else {
          // 30% path: exclude exact-mood unseen MICROs so the engine picks
          // from the remainder. Engine Tier 1 will surface exact-mood
          // unseen non-MICRO Short before any similar-mood content.
          final excluded = unseenExactMoodMicros
              .map((p) => p.storyId)
              .toSet();
          combinedPool = combinedPool
              .where((p) => !excluded.contains(p.storyId))
              .toList(growable: false);
        }
      } else if (microPool.isEmpty) {
        logEvent('micro_bias_no_match', {
          'selected_mood': mood,
          'reason': 'no_micros_in_pool',
          'combined_pool_size': combinedPool.length,
        });
      } else {
        // No unseen exact-mood MICRO available. Release the bias so normal
        // tiered serving resumes — exact-mood non-MICRO Shorts should
        // surface before similar-mood MICROs.
        logEvent('micro_bias_no_match', {
          'selected_mood': mood,
          'reason': 'no_unseen_exact_mood_micro',
          'micro_pool_size': microPool.length,
          'combined_pool_size': combinedPool.length,
        });
      }
    }

    // If a bibleStoryKey hint was provided (from previewBibleStoryKey), constrain
    // to variants of that story. Falls back to full pool if no variants match.
    if (bibleStoryKey != null) {
      final hinted = combinedPool
          .where((p) => p.bibleStoryKey == bibleStoryKey)
          .toList();
      if (hinted.isNotEmpty) {
        combinedPool = hinted;
        debugPrint(
            '[ParableService] Constrained to bibleStoryKey=$bibleStoryKey '
            '(${hinted.length} variant(s) for ${lengthBucket.name})');
      } else {
        debugPrint(
            '[ParableService] bibleStoryKey=$bibleStoryKey has no '
            '${lengthBucket.name} variant; falling back to full pool');
      }
    }

    if (combinedPool.isEmpty) {
      debugPrint('No eligible parables found for criteria (including expansion)');
      logEvent(
          'pool_exhausted',
          {
            'eligible_count': 0,
            'reason': 'no_matches_for_criteria',
            'expansion_attempted': true,
          },
          level: LogLevel.warn);
      return null;
    }

    // (Non-repeat rule note: playHistory + recentStoryIds were built earlier,
    // before the MICRO bias check, so the bias and the engine see the same
    // anti-repeat data. See SPEC.md Feature #11 anti-repeat note for the
    // 30-day "seen" window.)

    // Log pool sizes before/after expansion (SPEC 15b telemetry)
    logEvent('mood_expansion_pool', {
      'selected_mood': mood,
      'exact_pool_size': exactPool.length,
      'similar_pool_size': similarPools.length,
      'combined_pool_size': combinedPool.length,
    });

    // Use the 4-tier engine
    const engine = MoodExpansionEngine();
    final result = engine.select(
      selectedMood: mood,
      pool: combinedPool,
      playedStoryIds: recentStoryIds,
      playHistory: playHistory,
      kidMode: userPrefs.kidFriendlyOnly,
    );

    if (result == null) {
      debugPrint('MoodExpansionEngine returned null');
      return null;
    }

    // The engine picked a tier and sorted candidates by LRP.
    // Apply secondary ranking within the tier: relatability, then seasonal/time-of-day.
    var candidates = result.tierCandidates;
    String selectionMethod;

    if (userText != null && userText.isNotEmpty && candidates.length > 1) {
      final ranked = _matcher.rankByRelatability(
        userText,
        candidates,
        playHistory: playHistory,
      );
      if (ranked.isNotEmpty) {
        candidates = ranked;
        selectionMethod = 'relatability_ranking';
      } else {
        selectionMethod = 'lrp';
      }
    } else if (candidates.length > 1) {
      // Apply seasonal/time-of-day soft preferences as tie-breakers
      final hour = DateTime.now().hour;
      final currentTimeWindow = (hour >= 5 && hour < 12)
          ? 'morning'
          : (hour >= 17 || hour < 5)
              ? 'evening'
              : null;
      final currentSeason = SeasonalCalendar.getCurrentSeason();

      if (currentSeason != null || currentTimeWindow != null) {
        candidates = List<Parable>.from(candidates);
        candidates.sort((a, b) {
          if (currentSeason != null) {
            final aMatch = a.seasonTag == currentSeason ? 0 : 1;
            final bMatch = b.seasonTag == currentSeason ? 0 : 1;
            if (aMatch != bMatch) return aMatch.compareTo(bMatch);
          }
          if (currentTimeWindow != null) {
            final aMatch = a.timeOfDay == currentTimeWindow ? 0 : 1;
            final bMatch = b.timeOfDay == currentTimeWindow ? 0 : 1;
            if (aMatch != bMatch) return aMatch.compareTo(bMatch);
          }
          // Preserve LRP order for ties
          final aTime = playHistory[a.storyId];
          final bTime = playHistory[b.storyId];
          if (aTime == null && bTime != null) return -1;
          if (aTime != null && bTime == null) return 1;
          if (aTime != null && bTime != null) {
            final cmp = aTime.compareTo(bTime);
            if (cmp != 0) return cmp;
          }
          return a.storyId.compareTo(b.storyId);
        });
      }
      selectionMethod = 'deterministic_lrp';
    } else {
      selectionMethod = 'single_candidate';
    }

    final selected = candidates.first;
    final servedMood = selected.mood;

    // Human-readable tier reason for support triage. Tier number alone
    // doesn't tell a reader whether the story came from unseen or LRP
    // fallback; this field does.
    final selectionReason = switch (result.tier) {
      1 => 'tier_1_exact_unseen',
      2 => 'tier_2_similar_unseen',
      3 => 'tier_3_exact_seen_lrp',
      4 => 'tier_4_similar_seen_lrp',
      _ => 'tier_unknown',
    };

    // Log story selected with expansion metadata
    logEvent('story_selected', {
      'story_id': selected.storyId,
      'selected_mood': mood,
      'served_mood': servedMood,
      'expansion_tier': result.tier,
      'selection_reason': selectionReason,
      'eligible_exact_unseen_count': eligibleExactUnseenCount,
      'eligible_similar_unseen_count': eligibleSimilarUnseenCount,
      'seen_count': recentStoryIds.length,
      'mode':
          '${userPrefs.kidFriendlyOnly ? "kid" : "adult"}_${selected.storytellingMode}',
      'length_bucket': selected.lengthBucket.name,
      'matched_tags': selected.emotionalTags,
      'selection_method': selectionMethod,
    });

    return selected;
  }

  /// Get parable by ID
  Future<Parable?> getParableById(String storyId) async {
    final allParables = await _loadManifest();
    try {
      return allParables.firstWhere((p) => p.storyId == storyId);
    } catch (e) {
      return null;
    }
  }

  /// Resolves the parable that corresponds to a [JourneyStory] under
  /// the user's current length-bucket + language-style preferences.
  ///
  /// Journey Doctrine Slice 2 Phase 9 — used by the accept-path of
  /// the continuation cascade. Returns null when no manifest entry
  /// matches the (lane, anchor/storyNumber, length, style) tuple; the
  /// integration site treats null as silence-floor (falls through to
  /// the normal mood-flow rather than synthesizing a wrong story).
  ///
  /// Adult lane matches on storyId prefix `story_<storyNumber>_` and
  /// prefers the user's languageStyle (with same-length any-style
  /// fallback).
  /// Kid lane matches on storyId prefix `kidstory_kid_<anchorId>_`
  /// (mirrors JourneyEngine._kidAnchorPattern) and filters kidFriendly.
  Future<Parable?> getParableByJourneyStory(
    JourneyStory story, {
    required StoryLengthBucket lengthBucket,
    required UserPreferences userPrefs,
  }) async {
    final all = await _loadManifest();

    if (story.storyNumber != null) {
      // Adult lane. Compare buckets through Parable.lengthBucket
      // (handles null / legacy minute-based entries via the getter
      // in parable.dart, and normalizes casing via
      // StoryLengthBucket.fromJson) instead of doing a raw string
      // compare on p.storyLength — the raw compare silently drops
      // otherwise-valid candidates when the on-device catalog
      // cache has drifted, which was the root cause of Adam's
      // 2026-07-01 wedge (PR #63's same-length-any-style fallback
      // dropped for the same reason).
      //
      // Match cascade (most specific → most permissive):
      //   1) exact bucket + preferred style
      //   2) same bucket, any style (compliance-safe — both WEB and
      //      KJV are on the BibleTranslationRegistry allowlist)
      //   3) same style, any bucket (silence-floor last resort;
      //      still honest because the journey member is the user's
      //      only next-anchor for this journey)
      //   4) any match on storyNumber (final desperation before
      //      falling through to the journey-accept fallback nav)
      //
      // Kid-lane siblings filtered out so a kidFriendly variant
      // can't hijack the adult candidate set.
      final numberPrefix = 'story_${story.storyNumber}_';
      final preferredStyle = userPrefs.languageStyle;
      Parable? preferred;
      Parable? sameLengthAnyStyle;
      Parable? sameStyleAnyLength;
      Parable? anyMatch;
      for (final p in all) {
        if (!p.storyId.startsWith(numberPrefix)) continue;
        if (p.kidFriendly) continue;
        anyMatch ??= p;
        final sameLength = p.lengthBucket == lengthBucket;
        final sameStyle = p.languageStyle == preferredStyle;
        if (sameLength && sameStyle) {
          preferred = p;
          break;
        }
        if (sameLength) sameLengthAnyStyle ??= p;
        if (sameStyle) sameStyleAnyLength ??= p;
      }
      // Diagnostic breadcrumb — counts what the served (cache-tier)
      // manifest actually had for this storyNumber. Lets us
      // distinguish "manifest served zero 1114 rows" (stale cache
      // theory) from "manifest served many but none matched"
      // (a filter bug) on Adam's next tap.
      int prefixMatches = 0;
      int adultMatches = 0;
      final styles = <String>{};
      final buckets = <String>{};
      for (final p in all) {
        if (!p.storyId.startsWith(numberPrefix)) continue;
        prefixMatches++;
        if (p.kidFriendly) continue;
        adultMatches++;
        styles.add(p.languageStyle);
        buckets.add(p.lengthBucket.name);
      }
      logEvent('journey_lookup_candidates', {
        'story_number': story.storyNumber,
        'manifest_size': all.length,
        'prefix_matches': prefixMatches,
        'adult_matches': adultMatches,
        'styles_seen': styles.toList(),
        'buckets_seen': buckets.toList(),
        'requested_style': preferredStyle,
        'requested_bucket': lengthBucket.name,
        'exact_hit': preferred != null,
        'same_len_hit': sameLengthAnyStyle != null,
        'same_style_hit': sameStyleAnyLength != null,
        'any_hit': anyMatch != null,
      });

      final cascaded = preferred ??
          sameLengthAnyStyle ??
          sameStyleAnyLength ??
          anyMatch;
      if (cascaded != null) return cascaded;

      // Stale-cache escape hatch (2026-07-01): if the served
      // manifest has zero entries for this storyNumber, re-read
      // the BUNDLED manifest directly and pick the best variant.
      // Adam wedge: storyNumber 1114 (Daniel 6) was added AFTER
      // his device cached an older R2 catalog. CatalogService
      // returns cache-OR-bundled, never merged — so bundled 1114
      // was never consulted. Compliance-safe: only resolves
      // storyNumbers already curated into the shipped app.
      // ALWAYS emit an "attempted" breadcrumb so a support-bundle
      // capture confirms this code even ran. Silent zero-match
      // returns were opaque in Adam's 2026-07-01 retest.
      logEvent('journey_bundled_rescue_attempted', {
        'story_number': story.storyNumber,
        'requested_style': preferredStyle,
        'requested_bucket': lengthBucket.name,
      });
      int bundledPrefixMatches = 0;
      int bundledAdultMatches = 0;
      try {
        final bundledJson =
            await rootBundle.loadString('assets/stories/manifest.json');
        final bundledData =
            jsonDecode(bundledJson) as Map<String, dynamic>;
        final rawList =
            bundledData['parables'] as List<dynamic>? ?? const [];
        Parable? bPreferred;
        Parable? bSameLen;
        Parable? bSameStyle;
        Parable? bAny;
        for (final raw in rawList) {
          final map = raw as Map<String, dynamic>;
          final sid = map['storyId'] as String? ?? '';
          if (!sid.startsWith(numberPrefix)) continue;
          bundledPrefixMatches++;
          final Parable p;
          try {
            p = Parable.fromJson(map);
          } catch (_) {
            continue;
          }
          if (p.kidFriendly) continue;
          bundledAdultMatches++;
          bAny ??= p;
          final sameLength = p.lengthBucket == lengthBucket;
          final sameStyle = p.languageStyle == preferredStyle;
          if (sameLength && sameStyle) {
            bPreferred = p;
            break;
          }
          if (sameLength) bSameLen ??= p;
          if (sameStyle) bSameStyle ??= p;
        }
        final resolved =
            bPreferred ?? bSameLen ?? bSameStyle ?? bAny;
        if (resolved != null) {
          logEvent('journey_bundled_rescue', {
            'story_number': story.storyNumber,
            'resolved_story_id': resolved.storyId,
            'preferred_style': preferredStyle,
            'requested_bucket': lengthBucket.name,
            'bundled_prefix_matches': bundledPrefixMatches,
            'bundled_adult_matches': bundledAdultMatches,
          });
          return resolved;
        }
        // Rescue ran but found no viable match. Log so we can see
        // if it's zero-prefix (asset load or storyId mismatch) or
        // zero-adult (all bundled entries were kidFriendly, unlikely).
        logEvent('journey_bundled_rescue_empty', {
          'story_number': story.storyNumber,
          'bundled_prefix_matches': bundledPrefixMatches,
          'bundled_adult_matches': bundledAdultMatches,
        });
      } catch (e) {
        logEvent(
          'journey_bundled_rescue_failed',
          {
            'story_number': story.storyNumber,
            'error_type': e.runtimeType.toString(),
            'error_message': e.toString(),
          },
          level: LogLevel.warn,
        );
      }
      return null;
    }

    if (story.anchorId != null) {
      // Kid lane. Manifest storyIds are `kidstory_kid_<anchor>_<length>`
      // (matches JourneyEngine._kidAnchorPattern). Previous code used
      // `kid_<anchor>_` prefix which NEVER matched — kid-lane accept
      // has been broken since Slice 2 Phase 9 first shipped. Adam
      // 2026-07-01: cascade dispatches on kid_david_arc (kid mode),
      // parable lookup returned null → sn=null on-screen diagnostic.
      //
      // Same tier cascade as adult lane: preferred bucket → same-length
      // any-style (kid stories only ship WEB today, but keep the shape
      // so it's ready if KJV kid ever ships) → any variant.
      final anchorPrefix = 'kidstory_kid_${story.anchorId}_';
      final preferredStyle = userPrefs.languageStyle;
      Parable? preferred;
      Parable? sameLengthAnyStyle;
      Parable? sameStyleAnyLength;
      Parable? anyMatch;
      for (final p in all) {
        if (!p.storyId.startsWith(anchorPrefix)) continue;
        if (!p.kidFriendly) continue; // kid-lane only
        anyMatch ??= p;
        final sameLength = p.lengthBucket == lengthBucket;
        final sameStyle = p.languageStyle == preferredStyle;
        if (sameLength && sameStyle) {
          preferred = p;
          break;
        }
        if (sameLength) sameLengthAnyStyle ??= p;
        if (sameStyle) sameStyleAnyLength ??= p;
      }
      final cascaded = preferred ??
          sameLengthAnyStyle ??
          sameStyleAnyLength ??
          anyMatch;
      if (cascaded != null) return cascaded;

      // Kid bundled-manifest rescue — same shape as adult. If the
      // served (cached) manifest doesn't contain the kid entries
      // (they're newer than Adam's cached R2 catalog), fall back
      // to the bundled asset directly.
      logEvent('journey_kid_bundled_rescue_attempted', {
        'anchor_id': story.anchorId,
        'requested_style': preferredStyle,
        'requested_bucket': lengthBucket.name,
      });
      int bundledPrefixMatches = 0;
      int bundledKidMatches = 0;
      try {
        final bundledJson =
            await rootBundle.loadString('assets/stories/manifest.json');
        final bundledData =
            jsonDecode(bundledJson) as Map<String, dynamic>;
        final rawList =
            bundledData['parables'] as List<dynamic>? ?? const [];
        Parable? bPreferred;
        Parable? bSameLen;
        Parable? bSameStyle;
        Parable? bAny;
        for (final raw in rawList) {
          final map = raw as Map<String, dynamic>;
          final sid = map['storyId'] as String? ?? '';
          if (!sid.startsWith(anchorPrefix)) continue;
          bundledPrefixMatches++;
          final Parable p;
          try {
            p = Parable.fromJson(map);
          } catch (_) {
            continue;
          }
          if (!p.kidFriendly) continue;
          bundledKidMatches++;
          bAny ??= p;
          final sameLength = p.lengthBucket == lengthBucket;
          final sameStyle = p.languageStyle == preferredStyle;
          if (sameLength && sameStyle) {
            bPreferred = p;
            break;
          }
          if (sameLength) bSameLen ??= p;
          if (sameStyle) bSameStyle ??= p;
        }
        final resolved =
            bPreferred ?? bSameLen ?? bSameStyle ?? bAny;
        if (resolved != null) {
          logEvent('journey_kid_bundled_rescue', {
            'anchor_id': story.anchorId,
            'resolved_story_id': resolved.storyId,
            'bundled_prefix_matches': bundledPrefixMatches,
            'bundled_kid_matches': bundledKidMatches,
          });
          return resolved;
        }
        logEvent('journey_kid_bundled_rescue_empty', {
          'anchor_id': story.anchorId,
          'bundled_prefix_matches': bundledPrefixMatches,
          'bundled_kid_matches': bundledKidMatches,
        });
      } catch (e) {
        logEvent(
          'journey_kid_bundled_rescue_failed',
          {
            'anchor_id': story.anchorId,
            'error_type': e.runtimeType.toString(),
            'error_message': e.toString(),
          },
          level: LogLevel.warn,
        );
      }
      return null;
    }

    return null;
  }

  /// Get audio file for a parable.
  ///
  /// Platform-specific delivery (SPEC Feature 27, Cloud Foundation v1):
  /// - iOS / Android: cache → bundled asset → R2 download (three-tier resolver).
  /// - Other platforms (desktop/test): asset-mode when [_useAssets],
  ///   else legacy docs-dir fallback.
  ///
  /// [onProgress] is invoked during R2 download with values in [0.0, 1.0].
  Future<File?> getAudioFile(
    Parable parable, {
    void Function(double progress)? onProgress,
  }) async {
    if (parable.audioFilePath == null) return null;

    if (Platform.isAndroid || Platform.isIOS) {
      return _getAudioFileAndroid(parable, onProgress: onProgress);
    }

    // Other platforms (desktop/test): preserve legacy behavior.
    if (_useAssets) {
      return _getAudioFileFromAssets(parable);
    }
    final dir = await _getParableLibraryDir();
    final audioFile = File('${dir.path}/${parable.audioFilePath}');
    if (await audioFile.exists()) return audioFile;
    return null;
  }

  /// Slice 4: resolve a parable's reflection audio file with the same
  /// platform semantics as [getAudioFile]:
  /// - iOS / Android: cache → bundled asset → R2 download (via [_resolveByPath]).
  /// - Other platforms (desktop/test): asset-mode when [_useAssets], else
  ///   the legacy docs-dir fallback.
  ///
  /// Returns null when the parable has no `reflectionAudioPath` declared
  /// or when the platform-specific cascade fails to produce a file —
  /// callers surface the "Connect to play" state in the UI.
  Future<File?> getReflectionAudioFile(Parable parable) async {
    if (parable.reflectionAudioPath == null) return null;

    if (Platform.isAndroid || Platform.isIOS) {
      return _resolveByPath(
        parable.reflectionAudioPath!,
        storyId: parable.storyId,
        lengthBucket: parable.lengthBucket.name,
        kind: AudioKind.reflection,
      );
    }

    // Other platforms (desktop/test): preserve story-audio parity.
    if (_useAssets) {
      return _getAudioFromAssetsByPath(parable.reflectionAudioPath!);
    }
    final dir = await _getParableLibraryDir();
    final reflectionFile = File('${dir.path}/${parable.reflectionAudioPath}');
    if (await reflectionFile.exists()) return reflectionFile;
    return null;
  }

  /// Desktop / asset-mode helper: copy bundled asset to temp dir for just_audio.
  /// Used by the desktop/test branch of [getAudioFile] when [_useAssets] is set.
  @visibleForTesting
  Future<File?> getAudioFileFromAssetsForTesting(Parable parable) =>
      _getAudioFileFromAssets(parable);

  Future<File?> _getAudioFileFromAssets(Parable parable) {
    if (parable.audioFilePath == null) return Future.value(null);
    return _getAudioFromAssetsByPath(parable.audioFilePath!);
  }

  /// Shared assets→temp helper for the desktop/test branch of
  /// [getAudioFile] and [getReflectionAudioFile].
  Future<File?> _getAudioFromAssetsByPath(String relativePath) async {
    try {
      final audioData =
          await rootBundle.load('assets/stories/$relativePath');
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$relativePath');
      await tempFile.parent.create(recursive: true);
      await tempFile.writeAsBytes(audioData.buffer.asUint8List());
      debugPrint('Copied audio from assets to temp: ${tempFile.path}');
      return tempFile;
    } catch (e) {
      debugPrint('Error loading audio from assets: $e');
      return null;
    }
  }

  /// Test-only entry point for the three-tier resolution path.
  /// In production this is reached via [getAudioFile] on Android and iOS.
  /// Method name retained for test-history continuity.
  @visibleForTesting
  Future<File?> getAudioFileAndroidForTesting(
    Parable parable, {
    void Function(double progress)? onProgress,
  }) =>
      _getAudioFileAndroid(parable, onProgress: onProgress);

  /// Test-only entry point for reflection three-tier resolution. Mirrors
  /// [getAudioFileAndroidForTesting]; bypasses the platform check in
  /// [getReflectionAudioFile] so the cascade is exercised in `flutter test`
  /// (where Platform reports the host).
  @visibleForTesting
  Future<File?> getReflectionAudioFileAndroidForTesting(Parable parable) {
    if (parable.reflectionAudioPath == null) return Future.value(null);
    return _resolveByPath(
      parable.reflectionAudioPath!,
      storyId: parable.storyId,
      lengthBucket: parable.lengthBucket.name,
      kind: AudioKind.reflection,
    );
  }

  /// Test-only accessor for the Android cache directory.
  @visibleForTesting
  Future<Directory> getAudioCacheDirForTesting() => _getAudioCacheDir();

  /// Android helper: thin wrapper around [_resolveByPath] (Slice 3
  /// pure-refactor). The cascade itself lives in [_resolveByPath] so
  /// Slice 4 shares it with reflection audio via [getReflectionAudioFile].
  Future<File?> _getAudioFileAndroid(
    Parable parable, {
    void Function(double progress)? onProgress,
  }) {
    return _resolveByPath(
      parable.audioFilePath!,
      storyId: parable.storyId,
      lengthBucket: parable.lengthBucket.name,
      kind: AudioKind.story,
      onProgress: onProgress,
    );
  }

  /// Test-only entry point for direct three-tier resolution by path.
  /// Lets the parity test compare wrapper vs helper for the same
  /// inputs. Production callers go through [_getAudioFileAndroid] or
  /// [getReflectionAudioFile].
  @visibleForTesting
  Future<File?> resolveByPathForTesting(
    String relativePath, {
    required String storyId,
    required String lengthBucket,
    required AudioKind kind,
    void Function(double progress)? onProgress,
  }) =>
      _resolveByPath(
        relativePath,
        storyId: storyId,
        lengthBucket: lengthBucket,
        kind: kind,
        onProgress: onProgress,
      );

  /// Three-tier audio resolver (Android): cache → bundled asset → R2
  /// download. Identical to the Slice 3 implementation except each
  /// `audio_source` event now carries `kind: story | reflection` so
  /// consumers can distinguish which asset was loaded.
  Future<File?> _resolveByPath(
    String relativePath, {
    required String storyId,
    required String lengthBucket,
    required AudioKind kind,
    void Function(double progress)? onProgress,
  }) async {
    _lastAudioError = AudioResolveError.none;

    // Tier 1: local cache hit.
    final cacheDir = await _getAudioCacheDir();
    final cachedFile = File('${cacheDir.path}/$relativePath');
    if (await cachedFile.exists()) {
      // Smart Offline Library v1: touch mtime so the eviction routine ranks
      // this file as freshly accessed. Best-effort — silent failure is fine.
      try {
        await cachedFile.setLastModified(DateTime.now());
      } catch (_) {/* mtime touch is best-effort */}
      _currentAudioRelativePath = relativePath;
      logEvent('story_cache_hit', {'story_id': storyId});
      logEvent('audio_source',
          {'source': 'cache', 'story_id': storyId, 'kind': kind.name});
      return cachedFile;
    }

    // Tier 2: bundled asset (seed story). Copy to cache so subsequent plays
    // are simple file reads instead of rootBundle loads.
    try {
      final audioData = await rootBundle.load('assets/stories/$relativePath');
      await cachedFile.parent.create(recursive: true);
      await cachedFile.writeAsBytes(audioData.buffer.asUint8List());
      _currentAudioRelativePath = relativePath;
      logEvent('audio_source',
          {'source': 'asset', 'story_id': storyId, 'kind': kind.name});
      return cachedFile;
    } catch (_) {
      // Not bundled — fall through to R2 download.
    }

    // Tier 3: download from R2.
    final downloaded = await _downloadAudio(
      relativePath,
      storyId: storyId,
      lengthBucket: lengthBucket,
      onProgress: onProgress,
    );
    if (downloaded != null) {
      _currentAudioRelativePath = relativePath;
      logEvent('audio_source',
          {'source': 'r2', 'story_id': storyId, 'kind': kind.name});
    }
    return downloaded;
  }

  /// Returns (and lazily creates) the Android audio cache directory.
  Future<Directory> _getAudioCacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/audio_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// Smart Offline Library v1: silently ensure a parable's audio is cached
  /// when the user favorites it. Reuses the existing Android resolver, which
  /// performs the cache → bundled asset → R2 cascade and writes into
  /// `audio_cache/`.
  ///
  /// Slice 5: primes BOTH the story audio and the reflection audio (when
  /// the parable declares a reflection path). Each cache attempt is
  /// isolated in its own try/catch so a failure on one asset cannot
  /// affect the other. Favoriting must never fail because caching failed.
  ///
  /// - Android: idempotent. No-op if already cached. Downloads if needed.
  /// - iOS: no-op (audio is bundled).
  /// - Other platforms (test/desktop): no-op.
  Future<void> ensureCachedForFavorite(Parable parable) async {
    if (!Platform.isAndroid) return;

    // Story audio first (existing behavior).
    if (parable.audioFilePath != null) {
      try {
        await _getAudioFileAndroid(parable);
      } catch (_) {/* silent — favoriting must not fail on network */}
    }

    // Reflection audio second (Slice 5 addition). Same three-tier
    // cascade, same swallow-and-continue semantics.
    if (parable.reflectionAudioPath != null) {
      try {
        await _resolveByPath(
          parable.reflectionAudioPath!,
          storyId: parable.storyId,
          lengthBucket: parable.lengthBucket.name,
          kind: AudioKind.reflection,
        );
      } catch (_) {/* silent — favoriting must not fail on network */}
    }
  }

  /// Test-only entry point for Slice 5 favorite-caching. Mirrors
  /// [getAudioFileAndroidForTesting]; bypasses the [Platform.isAndroid]
  /// check in [ensureCachedForFavorite] so the cascade is exercised in
  /// `flutter test` (where Platform reports the host).
  @visibleForTesting
  Future<void> ensureCachedForFavoriteAndroidForTesting(
      Parable parable) async {
    if (parable.audioFilePath != null) {
      try {
        await _getAudioFileAndroid(parable);
      } catch (_) {/* silent */}
    }
    if (parable.reflectionAudioPath != null) {
      try {
        await _resolveByPath(
          parable.reflectionAudioPath!,
          storyId: parable.storyId,
          lengthBucket: parable.lengthBucket.name,
          kind: AudioKind.reflection,
        );
      } catch (_) {/* silent */}
    }
  }

  /// Walks the audio cache directory and returns total bytes consumed.
  /// Cheap on a small cache (~300 files at 600 MB max).
  Future<int> _getAudioCacheTotalBytes() async {
    final cacheDir = await _getAudioCacheDir();
    if (!await cacheDir.exists()) return 0;
    var total = 0;
    await for (final entity
        in cacheDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {/* file vanished mid-walk */}
      }
    }
    return total;
  }

  /// Resolves the set of cache-relative audio paths that are currently
  /// favorited and MUST NOT be evicted. Reuses the existing manifest +
  /// favorites APIs — no new persistence.
  Future<Set<String>> _getProtectedAudioPaths() async {
    final favorites = await _storage.getFavorites();
    if (favorites.isEmpty) return const <String>{};
    final manifest = await _loadManifest();
    final byId = <String, Parable>{
      for (final p in manifest) p.storyId: p,
    };
    final protected = <String>{};
    for (final fav in favorites) {
      final p = byId[fav.storyId];
      if (p == null) continue;
      if (p.audioFilePath != null) {
        protected.add(p.audioFilePath!);
      }
      // Slice 5: reflection audio is also cached on favorite, so it
      // must be protected from eviction alongside the story audio.
      if (p.reflectionAudioPath != null) {
        protected.add(p.reflectionAudioPath!);
      }
    }
    return protected;
  }

  /// Cache management pass. Runs after every successful Android download.
  /// No-op if total cache size is within the soft budget.
  ///
  /// Eviction rules (SPEC Feature 27, INVARIANT: Favorited Audio Protection):
  /// - Favorited audio is NEVER deleted
  /// - The currently-playing audio file is NEVER deleted
  /// - Among evictable files, oldest mtime is removed first
  /// - If only favorites remain and they exceed the budget, the overrun is
  ///   honored (soft budget, not a hard cap)
  Future<void> _evictIfOverBudget() async {
    if (_evictionInProgress) return;
    _evictionInProgress = true;
    try {
      final totalBytes = await _getAudioCacheTotalBytes();
      if (totalBytes <= _audioCacheBudgetBytes) return;

      final protectedPaths = await _getProtectedAudioPaths();
      final cacheDir = await _getAudioCacheDir();
      final cacheRoot = cacheDir.path;

      // Build evictable candidates: (file, mtime, size).
      final candidates = <({File file, DateTime mtime, int size})>[];
      await for (final entity
          in cacheDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        // Cache-relative path, e.g. "creative/2000/audio_2000_story_short.mp3".
        final rel = entity.path.substring(cacheRoot.length + 1);
        if (protectedPaths.contains(rel)) continue; // favorite — skip
        if (rel == _currentAudioRelativePath) continue; // in use — skip
        try {
          final stat = await entity.stat();
          candidates
              .add((file: entity, mtime: stat.modified, size: stat.size));
        } catch (_) {/* skip vanished */}
      }

      // Oldest first.
      candidates.sort((a, b) => a.mtime.compareTo(b.mtime));

      var freedBytes = 0;
      var removedCount = 0;
      var currentTotal = totalBytes;
      for (final c in candidates) {
        if (currentTotal <= _audioCacheBudgetBytes) break;
        try {
          await c.file.delete();
          freedBytes += c.size;
          currentTotal -= c.size;
          removedCount += 1;
        } catch (_) {/* file vanished */}
      }

      logEvent('cache_eviction', {
        'bytes_before': totalBytes,
        'bytes_freed': freedBytes,
        'files_removed': removedCount,
        'favorites_protected': protectedPaths.length,
        'within_budget': currentTotal <= _audioCacheBudgetBytes,
      });
    } finally {
      _evictionInProgress = false;
    }
  }

  /// Test-only entry point for the eviction routine.
  @visibleForTesting
  Future<void> evictIfOverBudgetForTesting() => _evictIfOverBudget();

  /// Test-only accessor for the cache total-bytes helper.
  @visibleForTesting
  Future<int> getAudioCacheTotalBytesForTesting() => _getAudioCacheTotalBytes();

  /// Test-only accessor for the protected-audio-paths helper.
  @visibleForTesting
  Future<Set<String>> getProtectedAudioPathsForTesting() =>
      _getProtectedAudioPaths();

  /// Test-only setter to override the soft cache budget. Tests use this to
  /// avoid creating real 600 MB fixtures. Restore in tearDown.
  @visibleForTesting
  static void setAudioCacheBudgetForTesting(int bytes) {
    _audioCacheBudgetBytes = bytes;
  }

  /// Test-only reset of the cache budget back to the production default.
  @visibleForTesting
  static void resetAudioCacheBudgetForTesting() {
    _audioCacheBudgetBytes = kAudioCacheBudgetBytes;
  }

  /// Downloads an audio file from R2 to the local cache.
  ///
  /// - 30 second timeout
  /// - 1 retry for transient network failures (timeout, connection reset)
  /// - No retry for 404
  /// - Streams to a `.tmp` file, atomic rename on success
  /// - Deletes `.tmp` on any failure (partial files never count as cache hits)
  Future<File?> _downloadAudio(
    String relativePath, {
    required String storyId,
    required String lengthBucket,
    void Function(double progress)? onProgress,
  }) async {
    final baseUrl = dotenv.maybeGet('AUDIO_BASE_URL');
    if (baseUrl == null || baseUrl.isEmpty) {
      _lastAudioError = AudioResolveError.downloadFailed;
      logEvent(
        'story_download_failed',
        {'story_id': storyId, 'error_type': 'missing_base_url'},
        level: LogLevel.warn,
      );
      return null;
    }

    final url = Uri.parse('$baseUrl/$relativePath');
    final cacheDir = await _getAudioCacheDir();
    final targetFile = File('${cacheDir.path}/$relativePath');
    final tmpFile = File('${targetFile.path}.tmp');

    logEvent('story_download_started', {
      'story_id': storyId,
      'length_bucket': lengthBucket,
    });

    Future<File?> attempt() async {
      IOSink? sink;
      try {
        await tmpFile.parent.create(recursive: true);
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }

        final client = http.Client();
        try {
          final request = http.Request('GET', url);
          final response =
              await client.send(request).timeout(const Duration(seconds: 30));

          if (response.statusCode == 404) {
            throw _PermanentDownloadException('http_404');
          }
          if (response.statusCode != 200) {
            throw Exception('http_${response.statusCode}');
          }

          final totalBytes = response.contentLength ?? 0;
          var receivedBytes = 0;
          sink = tmpFile.openWrite();

          await for (final chunk in response.stream) {
            sink.add(chunk);
            receivedBytes += chunk.length;
            if (totalBytes > 0 && onProgress != null) {
              onProgress(receivedBytes / totalBytes);
            }
          }
          await sink.flush();
          await sink.close();
          sink = null;

          await tmpFile.rename(targetFile.path);
          logEvent('story_download_completed', {
            'story_id': storyId,
            'bytes': receivedBytes,
          });
          // Smart Offline Library v1: keep cache near the soft budget.
          // Fire-and-forget — eviction must never block playback.
          unawaited(_evictIfOverBudget());
          return targetFile;
        } finally {
          client.close();
        }
      } finally {
        try {
          await sink?.close();
        } catch (_) {/* ignore */}
        if (await tmpFile.exists()) {
          try {
            await tmpFile.delete();
          } catch (_) {/* ignore */}
        }
      }
    }

    try {
      return await attempt();
    } on _PermanentDownloadException catch (e) {
      _lastAudioError = AudioResolveError.remoteNotFound;
      logEvent(
        'story_download_failed',
        {'story_id': storyId, 'error_type': e.code},
        level: LogLevel.warn,
      );
      return null;
    } catch (e) {
      // Transient failure — one retry.
      try {
        final result = await attempt();
        if (result != null) return result;
      } catch (e2) {
        _lastAudioError = _isOfflineError(e2)
            ? AudioResolveError.offlineNotCached
            : AudioResolveError.downloadFailed;
        logEvent(
          'story_download_failed',
          {'story_id': storyId, 'error_type': e2.runtimeType.toString()},
          level: LogLevel.warn,
        );
        return null;
      }
      _lastAudioError = _isOfflineError(e)
          ? AudioResolveError.offlineNotCached
          : AudioResolveError.downloadFailed;
      logEvent(
        'story_download_failed',
        {'story_id': storyId, 'error_type': e.runtimeType.toString()},
        level: LogLevel.warn,
      );
      return null;
    }
  }

  /// Get text file for a parable
  Future<String?> getParableText(Parable parable) async {
    if (parable.textFilePath == null) return null;

    try {
      // If using bundled assets
      if (_useAssets) {
        return await rootBundle
            .loadString('assets/stories/${parable.textFilePath}');
      }

      final dir = await _getParableLibraryDir();
      final textFile = File('${dir.path}/${parable.textFilePath}');

      if (await textFile.exists()) {
        return await textFile.readAsString();
      }
    } catch (e) {
      debugPrint('Error reading parable text: $e');
    }

    return null;
  }

  /// Get scripture text file for a parable (lazy-loaded on demand)
  Future<String?> getScriptureText(Parable parable) async {
    if (parable.scriptureTextFilePath == null) return null;

    try {
      if (_useAssets) {
        return await rootBundle
            .loadString('assets/stories/${parable.scriptureTextFilePath}');
      }

      final dir = await _getParableLibraryDir();
      final textFile = File('${dir.path}/${parable.scriptureTextFilePath}');

      if (await textFile.exists()) {
        return await textFile.readAsString();
      }
    } catch (e) {
      debugPrint('Error reading scripture text: $e');
    }

    return null;
  }

  /// Get count of available parables by criteria
  Future<int> getAvailableCount({
    String? mood,
    StoryLengthBucket? lengthBucket,
    String? storytellingMode,
  }) async {
    final allParables = await _loadManifest();

    return allParables.where((p) {
      if (mood != null && p.mood != mood) return false;
      if (lengthBucket != null && p.lengthBucket != lengthBucket) return false;
      if (storytellingMode != null && p.storytellingMode != storytellingMode) {
        return false;
      }
      return true;
    }).length;
  }

  /// Returns true if [error] indicates no network connectivity.
  bool _isOfflineError(Object error) {
    return error is SocketException ||
        error.runtimeType.toString() == '_ClientSocketException';
  }
}

/// Marker exception for HTTP errors that must NOT be retried (e.g. 404).
class _PermanentDownloadException implements Exception {
  final String code;
  _PermanentDownloadException(this.code);
  @override
  String toString() => 'PermanentDownloadException($code)';
}
