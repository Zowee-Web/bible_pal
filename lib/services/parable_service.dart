import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/parable.dart';
import '../models/user_preferences.dart';
import 'storage_service.dart';

/// Parable Service - handles parable selection, generation, and management
/// Based on SPEC.md Features #4, #6, #14, #15
class ParableService {
  final StorageService _storage;
  final String? _externalStoragePath;
  bool _useAssets = false;

  ParableService(this._storage, [this._externalStoragePath]);

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
        final jsonContent = await rootBundle.loadString('assets/stories/manifest.json');
        final manifestData = jsonDecode(jsonContent) as Map<String, dynamic>;
        final parablesList = manifestData['parables'] as List<dynamic>? ?? [];
        totalEntries = parablesList.length;
        debugPrint('📚 Loading ${parablesList.length} parables from bundled assets');
        _useAssets = true; // Flag to use assets for audio/text files too

        // Validate each entry
        for (var json in parablesList) {
          final parable = Parable.fromJson(json as Map<String, dynamic>);

          // Check if audio file exists (only if audioFilePath is not null)
          if (parable.audioFilePath != null) {
            try {
              await rootBundle.load('assets/stories/${parable.audioFilePath}');
              parables.add(parable);
            } catch (e) {
              debugPrint('⚠️ Skipping ${parable.storyId}: audio file missing (${parable.audioFilePath})');
              skippedEntries++;
            }
          } else {
            // Text-only story, include it
            parables.add(parable);
          }
        }

        debugPrint('✅ Manifest validation: $totalEntries total, ${parables.length} valid, $skippedEntries skipped');
        return parables;
      } catch (assetError) {
        debugPrint('No bundled assets found, checking documents directory: $assetError');
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

        // Check if audio file exists
        if (parable.audioFilePath != null) {
          final audioFile = File('${dir.path}/${parable.audioFilePath}');
          if (await audioFile.exists()) {
            parables.add(parable);
          } else {
            debugPrint('⚠️ Skipping ${parable.storyId}: audio file missing');
            skippedEntries++;
          }
        } else {
          // Text-only story
          parables.add(parable);
        }
      }

      debugPrint('✅ Manifest validation: $totalEntries total, ${parables.length} valid, $skippedEntries skipped');
      return parables;
    } catch (e) {
      debugPrint('❌ Error loading parable manifest: $e');
      return [];
    }
  }

  /// Get eligible parables based on user preferences and mood
  /// Per SPEC.md Feature #4: Parable Generation / Selection Engine
  Future<List<Parable>> getEligibleParables({
    required String mood,
    required int lengthMinutes,
    required UserPreferences userPrefs,
  }) async {
    final allParables = await _loadManifest();
    
    // For bundled test assets, be more lenient with filtering
    final isTestMode = _useAssets;
    final hasEmptyTradition = userPrefs.faithTradition.isEmpty;
    
    debugPrint('Filtering parables: mood=$mood, length=$lengthMinutes, tradition=${userPrefs.faithTradition}, mode=${userPrefs.storytellingMode} (testMode=$isTestMode)');

    // Filter by criteria
    final eligible = allParables.where((p) {
      debugPrint('  Checking ${p.storyId}: mood=${p.mood}, length=${p.length}, tradition=${p.faithTradition}, mode=${p.storytellingMode}');
      
      // Match mood (always required)
      if (p.mood != mood) {
        debugPrint('    ✗ Mood mismatch');
        return false;
      }

      // Match length (always required)
      if (p.length != lengthMinutes) {
        debugPrint('    ✗ Length mismatch');
        return false;
      }

      // Match faith tradition - skip if user hasn't set one yet (test mode)
      if (!hasEmptyTradition && p.faithTradition != userPrefs.faithTradition) {
        debugPrint('    ✗ Tradition mismatch');
        return false;
      } else if (hasEmptyTradition) {
        debugPrint('    ⊙ Tradition check skipped (user has not set tradition yet)');
      }

      // Match storytelling mode - be lenient in test mode
      if (p.storytellingMode != userPrefs.storytellingMode) {
        if (isTestMode) {
          debugPrint('    ⊙ Mode mismatch but allowed in test mode');
        } else {
          debugPrint('    ✗ Mode mismatch');
          return false;
        }
      }

      // Match kid-friendly filter
      if (userPrefs.kidFriendlyOnly && !p.kidFriendly) {
        debugPrint('    ✗ Not kid-friendly');
        return false;
      }

      debugPrint('    ✓ Match!');
      return true;
    }).toList();
    
    debugPrint('Found ${eligible.length} eligible parables');
    return eligible;
  }

  /// Select a parable using non-repeat serving rule
  /// Per SPEC.md Feature #14: Non-Repeat Story Serving Rule
  Future<Parable?> selectParable({
    required String mood,
    required int lengthMinutes,
    required UserPreferences userPrefs,
  }) async {
    final eligibleParables = await getEligibleParables(
      mood: mood,
      lengthMinutes: lengthMinutes,
      userPrefs: userPrefs,
    );

    if (eligibleParables.isEmpty) {
      debugPrint('No eligible parables found for criteria');
      return null;
    }

    // Get history to implement non-repeat rule
    final history = await _storage.getHistory();
    final recentStoryIds = history.map((h) => h.storyId).toSet();

    // Find parables not recently played
    final unplayedParables = eligibleParables
        .where((p) => !recentStoryIds.contains(p.storyId))
        .toList();

    // If all parables have been played, use least recently played
    if (unplayedParables.isEmpty) {
      debugPrint('All eligible parables played, using least recent');
      // Sort by last played (earliest first)
      final storyPlayOrder = <String, int>{};
      for (var i = 0; i < history.length; i++) {
        if (!storyPlayOrder.containsKey(history[i].storyId)) {
          storyPlayOrder[history[i].storyId] = i;
        }
      }

      eligibleParables.sort((a, b) {
        final aOrder = storyPlayOrder[a.storyId] ?? 999999;
        final bOrder = storyPlayOrder[b.storyId] ?? 999999;
        return bOrder.compareTo(aOrder); // Oldest first
      });

      return eligibleParables.first;
    }

    // Return a random unplayed parable
    unplayedParables.shuffle();
    return unplayedParables.first;
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
        final audioData = await rootBundle.load('assets/stories/${parable.audioFilePath}');
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/${parable.audioFilePath}');
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
        return await rootBundle.loadString('assets/stories/${parable.textFilePath}');
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
    int? lengthMinutes,
    String? faithTradition,
    String? storytellingMode,
  }) async {
    final allParables = await _loadManifest();

    return allParables.where((p) {
      if (mood != null && p.mood != mood) return false;
      if (lengthMinutes != null && p.length != lengthMinutes) return false;
      if (faithTradition != null && p.faithTradition != faithTradition) {
        return false;
      }
      if (storytellingMode != null && p.storytellingMode != storytellingMode) {
        return false;
      }
      return true;
    }).length;
  }
}
