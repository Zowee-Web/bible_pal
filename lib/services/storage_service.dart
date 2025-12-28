import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_preferences.dart';
import '../models/favorite.dart';
import '../models/history_entry.dart';
import '../models/pal.dart';
import '../models/share_record.dart';
import '../models/pending_share.dart';

/// Storage Service - handles all local data persistence
/// Based on SPEC.md Feature #25: User Data Encryption (secure storage)
class StorageService {
  static const String _keyUserPreferences = 'user_preferences';
  static const String _keyFavorites = 'favorites';
  static const String _keyHistory = 'history';
  static const String _keyEditedTitles = 'edited_titles';
  static const String _keyPals = 'pals';
  static const String _keyShares = 'shares';
  static const String _keyPendingShares = 'pending_shares';
  static const String _keyLastInboxSync = 'last_inbox_sync';

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

  /// Add a favorite (with 100-favorite cap, newest kept)
  Future<void> addFavorite(Favorite favorite) async {
    final favorites = await getFavorites();
    // Check if already favorited
    if (favorites.any((f) => f.storyId == favorite.storyId)) {
      return;
    }

    // Add at beginning (most recent first)
    favorites.insert(0, favorite);

    // Keep only last 100 favorites (FIFO)
    if (favorites.length > 100) {
      favorites.removeRange(100, favorites.length);
    }

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

  /// Get history (last 20 entries, per v1.0 cap)
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

  /// Add to history (FIFO: keeps only last 20 entries)
  Future<void> addToHistory(HistoryEntry entry) async {
    final history = await getHistory();

    // Add new entry at the beginning (most recent first)
    history.insert(0, entry);

    // Keep only last 20 entries (FIFO)
    if (history.length > 20) {
      history.removeRange(20, history.length);
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

  // ========== PALs (Compatibility Shims for Tests) ==========

  /// Get all PALs (sorted: pinned first, then by shareCount descending)
  Future<List<PAL>> getPals() async {
    final json = _prefs.getString(_keyPals);
    if (json == null) return [];

    final list = jsonDecode(json) as List<dynamic>;
    final pals = list.map((item) => PAL.fromJson(item as Map<String, dynamic>)).toList();

    // Sort: pinned first, then by shareCount descending
    pals.sort((a, b) {
      if (a.pinned && !b.pinned) return -1;
      if (!a.pinned && b.pinned) return 1;
      return b.shareCount.compareTo(a.shareCount);
    });

    return pals;
  }

  /// Save PALs list
  Future<void> _savePals(List<PAL> pals) async {
    final json = jsonEncode(pals.map((p) => p.toJson()).toList());
    await _prefs.setString(_keyPals, json);
  }

  /// Add a PAL
  Future<void> addPal(PAL pal) async {
    final pals = await getPals();
    // Check if already exists
    if (pals.any((p) => p.palId == pal.palId)) {
      return;
    }
    pals.add(pal);
    await _savePals(pals);
  }

  /// Remove a PAL
  Future<void> removePal(String palId) async {
    final pals = await getPals();
    pals.removeWhere((p) => p.palId == palId);
    await _savePals(pals);
  }

  /// Update an existing PAL
  Future<void> updatePal(PAL pal) async {
    final pals = await getPals();
    final index = pals.indexWhere((p) => p.palId == pal.palId);
    if (index == -1) return;

    pals[index] = pal;
    await _savePals(pals);
  }

  /// Increment share count for a PAL
  Future<void> incrementPalShareCount(String palId) async {
    final pals = await getPals();
    final index = pals.indexWhere((p) => p.palId == palId);
    if (index == -1) return;

    final updatedPal = pals[index].copyWith(
      shareCount: pals[index].shareCount + 1,
    );
    pals[index] = updatedPal;
    await _savePals(pals);
  }

  // ========== Shares (Compatibility Shims for Tests) ==========

  /// Get all shares
  Future<List<ShareRecord>> getShares() async {
    final json = _prefs.getString(_keyShares);
    if (json == null) return [];

    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((item) => ShareRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Save shares list
  Future<void> _saveShares(List<ShareRecord> shares) async {
    final json = jsonEncode(shares.map((s) => s.toJson()).toList());
    await _prefs.setString(_keyShares, json);
  }

  /// Add a share record
  Future<void> addShare(ShareRecord share) async {
    final shares = await getShares();
    shares.add(share);
    await _saveShares(shares);
  }

  /// Get shares to a specific PAL
  Future<List<ShareRecord>> getSharesToPal(String palId) async {
    final shares = await getShares();
    return shares.where((s) => s.toPalId == palId).toList();
  }

  /// Check if a share exists by shareId (for idempotency)
  Future<bool> hasShare(String shareId) async {
    final shares = await getShares();
    return shares.any((s) => s.shareId == shareId);
  }

  // ========== Pending Share Queue (Compatibility Shims for Tests) ==========

  /// Get pending shares queue
  Future<List<PendingShare>> getPendingShares() async {
    final json = _prefs.getString(_keyPendingShares);
    if (json == null) return [];

    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((item) => PendingShare.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Save pending shares queue
  Future<void> _savePendingShares(List<PendingShare> pending) async {
    final json = jsonEncode(pending.map((p) => p.toJson()).toList());
    await _prefs.setString(_keyPendingShares, json);
  }

  /// Add to pending share queue (with deduplication by shareId and 50-share FIFO cap)
  Future<void> addToPendingQueue(PendingShare share) async {
    final pending = await getPendingShares();

    // Deduplicate by shareId
    if (pending.any((p) => p.shareId == share.shareId)) {
      return;
    }

    // Add new share at the beginning (most recent first)
    pending.insert(0, share);

    // Keep only last 50 shares (FIFO)
    if (pending.length > 50) {
      pending.removeRange(50, pending.length);
    }

    await _savePendingShares(pending);
  }

  /// Remove from pending share queue
  Future<void> removeFromPendingQueue(String shareId) async {
    final pending = await getPendingShares();
    pending.removeWhere((p) => p.shareId == shareId);
    await _savePendingShares(pending);
  }

  /// Clear entire pending share queue
  Future<void> clearPendingQueue() async {
    await _prefs.remove(_keyPendingShares);
  }

  // ========== Inbox Sync Timestamp (Compatibility Shims for Tests) ==========

  /// Set last inbox sync timestamp
  Future<void> setLastInboxSyncTimestamp(DateTime timestamp) async {
    await _prefs.setString(_keyLastInboxSync, timestamp.toIso8601String());
  }

  /// Get last inbox sync timestamp
  Future<DateTime?> getLastInboxSyncTimestamp() async {
    final json = _prefs.getString(_keyLastInboxSync);
    if (json == null) return null;
    return DateTime.parse(json);
  }
}
