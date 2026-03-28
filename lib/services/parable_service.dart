import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/parable.dart';
import '../models/user_preferences.dart';
import '../core/app_logger.dart';
import '../core/story_length_bucket.dart';
import '../core/seasonal_calendar.dart';
import 'storage_service.dart';
import 'relatability_matcher.dart';

/// Parable Service - handles parable selection, generation, and management
/// Based on SPEC.md Features #4, #6, #14, #15
class ParableService {
  final StorageService _storage;
  final String? _externalStoragePath;
  bool _useAssets = false;
  final bool testMode;
  final RelatabilityMatcher _matcher = RelatabilityMatcher();

  ParableService(this._storage,
      [this._externalStoragePath, this.testMode = false]);

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

  /// Load manifest of available parables
  /// Validates that referenced audio files exist and skips broken entries
  Future<List<Parable>> _loadManifest() async {
    try {
      List<Parable> parables = [];
      int totalEntries = 0;
      int skippedEntries = 0;

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

      // Match storytelling mode (ALWAYS enforced - user expects this to work!)
      if (p.storytellingMode != userPrefs.storytellingMode) return false;

      // Match language style (WEB or KJV) - Contracts v2
      // Use story's languageStyle field for filtering
      if (p.languageStyle != languageStyle) return false;

      // CONTRACTS V2 + ADR-010: Traditional stories MUST have bibleSourceRef AND bibleStoryKey
      // Stories without these fields are EXCLUDED (not guessed)
      if (p.storytellingMode == 'traditional') {
        if (!p.hasBibleSourceRef) {
          // Log exclusion for missing bibleSourceRef
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
          // Log exclusion for missing bibleStoryKey (ADR-010)
          logEvent(
              'story_excluded',
              {
                'story_id': p.storyId,
                'reason': 'traditional_missing_bible_story_key',
              },
              level: LogLevel.warn);
          return false;
        }
      }

      // CONTRACTS V2: Creative stories MUST NOT have bibleSourceRef
      // Stories with bibleSourceRef are EXCLUDED (data error)
      if (p.storytellingMode == 'creative') {
        if (p.hasBibleSourceRef) {
          // Log exclusion for unexpected bibleSourceRef
          logEvent(
              'story_excluded',
              {
                'story_id': p.storyId,
                'reason': 'creative_has_bible_source_ref',
              },
              level: LogLevel.warn);
          return false;
        }
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

  /// Select a parable using non-repeat serving rule and relatability matching.
  /// Per SPEC.md Feature #14: Non-Repeat Story Serving Rule
  ///
  /// Selection algorithm:
  /// 1. Filter by eligibility (mode, lengthBucket, kid mode)
  /// 2. Exclude recently played (no-repeat invariant) if unplayed exist
  /// 3. Rank by relatability score (if userText provided)
  /// 4. Tie-break: least-recently-played, then stable storyId
  Future<Parable?> selectParable({
    required String mood,
    required StoryLengthBucket lengthBucket,
    required UserPreferences userPrefs,
    String? userText,
  }) async {
    final eligibleParables = await getEligibleParables(
      mood: mood,
      lengthBucket: lengthBucket,
      userPrefs: userPrefs,
    );

    if (eligibleParables.isEmpty) {
      debugPrint('No eligible parables found for criteria');

      // Log pool exhausted (no matches)
      logEvent(
          'pool_exhausted',
          {
            'eligible_count': 0,
            'reason': 'no_matches_for_criteria',
          },
          level: LogLevel.warn);

      return null;
    }

    // Get history to implement non-repeat rule
    final history = await _storage.getHistory();
    final recentStoryIds = history.map((h) => h.storyId).toSet();

    // Build play history map for tie-breaking (storyId -> last played time)
    final playHistory = <String, DateTime>{};
    for (final entry in history) {
      // Keep only the most recent play time for each story
      if (!playHistory.containsKey(entry.storyId)) {
        playHistory[entry.storyId] = entry.timestamp;
      }
    }

    // Find parables not recently played
    final unplayedParables = eligibleParables
        .where((p) => !recentStoryIds.contains(p.storyId))
        .toList();

    // Determine candidate pool: prefer unplayed, fall back to all eligible
    List<Parable> candidates;
    if (unplayedParables.isEmpty) {
      debugPrint('All eligible parables played, using full pool with LRU');

      // Log pool exhausted with LRP strategy
      logEvent('pool_exhausted', {
        'eligible_count': eligibleParables.length,
        'strategy': 'LRP',
        'reason': 'all_stories_played',
      });

      candidates = eligibleParables;
    } else {
      candidates = unplayedParables;
    }

    // Apply relatability ranking if userText provided
    if (userText != null && userText.isNotEmpty) {
      final ranked = _matcher.rankByRelatability(
        userText,
        candidates,
        playHistory: playHistory,
      );
      if (ranked.isNotEmpty) {
        debugPrint(
            'Relatability ranking applied, top match: ${ranked.first.storyId}');

        final selected = ranked.first;
        // Log story selected with relatability ranking
        // NOTE: length_bucket is canonical - no minute-based fields in telemetry (INVARIANTS.md)
        logEvent('story_selected', {
          'story_id': selected.storyId,
          'mode':
              '${userPrefs.kidFriendlyOnly ? "kid" : "adult"}_${selected.storytellingMode}',
          'length_bucket': selected.lengthBucket.name,
          'matched_tags': selected.emotionalTags,
          'selection_method': 'relatability_ranking',
          'repeat_allowed': unplayedParables.isEmpty,
        });

        return selected;
      }
    }

    // Fallback: deterministic selection with time-of-day and seasonal soft preferences.
    // Stories tagged for the current time window or season are preferred.
    final hour = DateTime.now().hour;
    final currentTimeWindow = (hour >= 5 && hour < 12)
        ? 'morning'
        : (hour >= 17 || hour < 5)
            ? 'evening'
            : null; // afternoon: no preference
    final currentSeason = SeasonalCalendar.getCurrentSeason();

    candidates.sort((a, b) {
      // Seasonal boost: matching stories come first
      if (currentSeason != null) {
        final aMatch = a.seasonTag == currentSeason ? 0 : 1;
        final bMatch = b.seasonTag == currentSeason ? 0 : 1;
        if (aMatch != bMatch) return aMatch.compareTo(bMatch);
      }

      // Time-of-day boost: matching stories come first
      if (currentTimeWindow != null) {
        final aMatch = a.timeOfDay == currentTimeWindow ? 0 : 1;
        final bMatch = b.timeOfDay == currentTimeWindow ? 0 : 1;
        if (aMatch != bMatch) return aMatch.compareTo(bMatch);
      }

      final aTime = playHistory[a.storyId];
      final bTime = playHistory[b.storyId];

      // Never played comes first
      if (aTime == null && bTime != null) return -1;
      if (aTime != null && bTime == null) return 1;
      if (aTime != null && bTime != null) {
        final timeCompare = aTime.compareTo(bTime);
        if (timeCompare != 0) return timeCompare;
      }

      // Stable tie-break by storyId
      return a.storyId.compareTo(b.storyId);
    });

    final selected = candidates.first;
    // Log story selected via deterministic fallback
    // NOTE: length_bucket is canonical - no minute-based fields in telemetry (INVARIANTS.md)
    logEvent('story_selected', {
      'story_id': selected.storyId,
      'mode':
          '${userPrefs.kidFriendlyOnly ? "kid" : "adult"}_${selected.storytellingMode}',
      'length_bucket': selected.lengthBucket.name,
      'matched_tags': selected.emotionalTags,
      'selection_method': 'deterministic_lrp',
      'repeat_allowed': unplayedParables.isEmpty,
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

  /// Get audio file for a parable
  Future<File?> getAudioFile(Parable parable) async {
    if (parable.audioFilePath == null) return null;

    // If using bundled assets, return a special file path that audio player can handle
    if (_useAssets) {
      // For bundled assets, we need to copy to temp directory for just_audio to play
      try {
        final audioData =
            await rootBundle.load('assets/stories/${parable.audioFilePath}');
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/${parable.audioFilePath}');
        await tempFile.parent.create(recursive: true);
        await tempFile.writeAsBytes(audioData.buffer.asUint8List());
        debugPrint('Copied audio from assets to temp: ${tempFile.path}');
        return tempFile;
      } catch (e) {
        debugPrint('Error loading audio from assets: $e');
        return null;
      }
    }

    final dir = await _getParableLibraryDir();
    final audioFile = File('${dir.path}/${parable.audioFilePath}');

    if (await audioFile.exists()) {
      return audioFile;
    }

    return null;
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
}
