import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_preferences.dart';
import '../models/favorite.dart';
import '../models/history_entry.dart';

/// Storage Service - handles all local data persistence
/// Based on SPEC.md Feature #25: User Data Encryption (secure storage)
class StorageService {
  static const String _keyUserPreferences = 'user_preferences';
  static const String _keyFavorites = 'favorites';
  static const String _keyHistory = 'history';
  static const String _keyEditedTitles = 'edited_titles';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  /// Initialize storage service
  static Future<StorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // ========== User Preferences ==========

  /// Get user preferences
  Future<UserPreferences> getUserPreferences() async {
    final json = _prefs.getString(_keyUserPreferences);
    if (json == null) {
      return UserPreferences.defaults();
    }
    return UserPreferences.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  /// Save user preferences
  Future<void> saveUserPreferences(UserPreferences prefs) async {
    await _prefs.setString(_keyUserPreferences, jsonEncode(prefs.toJson()));
  }

  // ========== Favorites ==========

  /// Get all favorites (unlimited, per SPEC.md Feature #9)
  Future<List<Favorite>> getFavorites() async {
    final json = _prefs.getString(_keyFavorites);
    if (json == null) return [];

    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((item) => Favorite.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Save favorites list
  Future<void> saveFavorites(List<Favorite> favorites) async {
    final json = jsonEncode(favorites.map((f) => f.toJson()).toList());
    await _prefs.setString(_keyFavorites, json);
  }

  /// Add a favorite
  Future<void> addFavorite(Favorite favorite) async {
    final favorites = await getFavorites();
    // Check if already favorited
    if (favorites.any((f) => f.storyId == favorite.storyId)) {
      return;
    }
    favorites.add(favorite);
    await saveFavorites(favorites);
  }

  /// Remove a favorite
  Future<void> removeFavorite(String storyId) async {
    final favorites = await getFavorites();
    favorites.removeWhere((f) => f.storyId == storyId);
    await saveFavorites(favorites);
  }

  /// Check if a story is favorited
  Future<bool> isFavorited(String storyId) async {
    final favorites = await getFavorites();
    return favorites.any((f) => f.storyId == storyId);
  }

  // ========== History ==========

  /// Get history (last 100 entries, per SPEC.md Feature #10)
  Future<List<HistoryEntry>> getHistory() async {
    final json = _prefs.getString(_keyHistory);
    if (json == null) return [];

    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((item) => HistoryEntry.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Save history list
  Future<void> saveHistory(List<HistoryEntry> history) async {
    final json = jsonEncode(history.map((h) => h.toJson()).toList());
    await _prefs.setString(_keyHistory, json);
  }

  /// Add to history (FIFO: keeps only last 100, per SPEC.md Feature #10)
  Future<void> addToHistory(HistoryEntry entry) async {
    final history = await getHistory();

    // Add new entry at the beginning (most recent first)
    history.insert(0, entry);

    // Keep only last 100 entries (FIFO)
    if (history.length > 100) {
      history.removeRange(100, history.length);
    }

    await saveHistory(history);
  }

  /// Clear all history
  Future<void> clearHistory() async {
    await _prefs.remove(_keyHistory);
  }

  // ========== Edited Titles ==========
  // Per SPEC.md Feature #8: user can edit AI-generated titles

  /// Get edited title for a story
  Future<String?> getEditedTitle(String storyId) async {
    final json = _prefs.getString(_keyEditedTitles);
    if (json == null) return null;

    final map = jsonDecode(json) as Map<String, dynamic>;
    return map[storyId] as String?;
  }

  /// Save edited title for a story
  Future<void> saveEditedTitle(String storyId, String newTitle) async {
    final json = _prefs.getString(_keyEditedTitles);
    final map = json != null
        ? jsonDecode(json) as Map<String, dynamic>
        : <String, dynamic>{};

    map[storyId] = newTitle;
    await _prefs.setString(_keyEditedTitles, jsonEncode(map));
  }

  /// Get all edited titles
  Future<Map<String, String>> getAllEditedTitles() async {
    final json = _prefs.getString(_keyEditedTitles);
    if (json == null) return {};

    final map = jsonDecode(json) as Map<String, dynamic>;
    return map.map((key, value) => MapEntry(key, value as String));
  }

  // ========== Utility ==========

  /// Clear all data (for testing or reset)
  Future<void> clearAll() async {
    await _prefs.clear();
  }
}
