import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/daily_bread.dart';
import '../models/user_preferences.dart';

/// Daily Bread Service - manages daily verse display
/// Based on SPEC.md Features #19, #20: Daily Bread Verse Display and Thematic Alignment
class DailyBreadService {
  /// Get daily bread verse for today
  /// This can be enhanced to fetch from a verse database or API
  Future<DailyBread> getDailyVerse(UserPreferences userPrefs) async {
    // For now, return a static verse
    // TODO: Implement verse database or API integration
    final now = DateTime.now();

    // This is a placeholder implementation
    // In production, this would select a verse based on:
    // 1. The current date
    // 2. The user's selected translation
    // 3. Optional thematic alignment with the day's parable
    return DailyBread(
      verse: 'In Your presence is fullness of joy',
      reference: 'Psalm 16:11',
      translation: userPrefs.bibleTranslation,
      date: DateTime(now.year, now.month, now.day),
      theme: null,
    );
  }

  /// Load daily verses from a local database file
  Future<List<DailyBread>> _loadVersesDatabase() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final versesFile = File('${appDir.path}/daily_verses.json');

      if (!await versesFile.exists()) {
        debugPrint('Daily verses database not found');
        return [];
      }

      final jsonContent = await versesFile.readAsString();
      final data = jsonDecode(jsonContent) as Map<String, dynamic>;
      final versesList = data['verses'] as List<dynamic>? ?? [];

      return versesList
          .map((json) => DailyBread.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading verses database: $e');
      return [];
    }
  }

  /// Get verse for a specific date
  Future<DailyBread?> getVerseForDate(
    DateTime date,
    UserPreferences userPrefs,
  ) async {
    final verses = await _loadVersesDatabase();

    if (verses.isEmpty) {
      return getDailyVerse(userPrefs);
    }

    // Find verse for the specific date
    try {
      return verses.firstWhere((v) =>
          v.date.year == date.year &&
          v.date.month == date.month &&
          v.date.day == date.day);
    } catch (e) {
      // If no verse for this date, return a default
      return getDailyVerse(userPrefs);
    }
  }

  /// Get verse aligned with a specific theme (for parable alignment)
  Future<DailyBread?> getVerseByTheme(
    String theme,
    UserPreferences userPrefs,
  ) async {
    final verses = await _loadVersesDatabase();

    if (verses.isEmpty) return null;

    // Find verse matching the theme
    try {
      return verses.firstWhere((v) => v.theme == theme);
    } catch (e) {
      return null;
    }
  }
}
