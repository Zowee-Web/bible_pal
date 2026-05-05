import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_preferences.dart';
import '../models/favorite.dart';
import '../models/history_entry.dart';
import '../models/pal.dart';
import '../models/share_record.dart';
import '../models/pending_share.dart';
import '../models/journal_entry.dart';
import '../features/onboarding/first_launch_screen.dart' show kFirstLaunchCompleteKey, kPalIntroShownKey;

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
  static const String _keyJournal = 'journal_entries';
  // PALs Paths (Feature 50) — completion + badge persistence. See
  // SPEC 50.11 / INVARIANTS Data Capacity Invariants for caps.
  static const String _keyCompletedStories = 'completed_stories';
  static const String _keyAwardedBadges = 'awarded_badges';
  static const int _completedStoriesCap = 1000;
  static const int _awardedBadgesCap = 200;

  // Selection-time play log (storyId → lastPlayedAt). Decoupled from the
  // user-facing 20-entry History; consumed by ParableService /
  // MoodExpansionEngine to drive non-repeat serving across the full library.
  // See SPEC.md Feature #11 (note on decoupling).
  static const String _keyPlayLog = 'play_log';
  static const int _playLogCap = 1000;

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
  /// Note: Returns pure read - cap enforcement happens on write and during migration
  Future<List<HistoryEntry>> getHistory() async {
    final json = _prefs.getString(_keyHistory);
    if (json == null) return [];

    final list = jsonDecode(json) as List<dynamic>;
    final history = list
        .map((item) => HistoryEntry.fromJson(item as Map<String, dynamic>))
        .toList();

    // Return only first 20 entries (pure read, no write side-effect)
    return history.take(20).toList();
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

  // ========== Reflection Journal ==========

  /// Get all journal entries (most recent first)
  Future<List<JournalEntry>> getJournalEntries() async {
    final json = _prefs.getString(_keyJournal);
    if (json == null) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => JournalEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Delete a journal entry by ID
  Future<void> deleteJournalEntry(String id) async {
    final entries = await getJournalEntries();
    entries.removeWhere((e) => e.id == id);
    final json = jsonEncode(entries.map((e) => e.toJson()).toList());
    await _prefs.setString(_keyJournal, json);
  }

  /// Add a journal entry (keeps last 100)
  Future<void> addJournalEntry(JournalEntry entry) async {
    final entries = await getJournalEntries();
    entries.insert(0, entry);
    if (entries.length > 100) {
      entries.removeRange(100, entries.length);
    }
    final json = jsonEncode(entries.map((e) => e.toJson()).toList());
    await _prefs.setString(_keyJournal, json);
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

  // ========== Completed Stories (PALs Paths, Feature 50.11) ==========

  /// Return the set of completed story IDs as a list (insertion order).
  /// Empty if nothing has been completed yet. Capped at 1000 entries.
  Future<List<String>> getCompletedStories() async {
    final json = _prefs.getString(_keyCompletedStories);
    if (json == null) return <String>[];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => e as String).toList();
  }

  /// Mark a story as completed. Write-once idempotent — calling twice for
  /// the same `storyId` is a no-op. FIFO eviction when the 1000-entry cap
  /// is exceeded (oldest entry dropped). See SPEC Feature 50.4 + 50.11.
  Future<void> addCompletedStory(String storyId) async {
    final list = await getCompletedStories();
    if (list.contains(storyId)) return; // Idempotent.
    list.add(storyId);
    if (list.length > _completedStoriesCap) {
      list.removeRange(0, list.length - _completedStoriesCap);
    }
    await _prefs.setString(_keyCompletedStories, jsonEncode(list));
  }

  /// True if the given story has been completed (≥ 90% story-body playback).
  Future<bool> isStoryCompleted(String storyId) async {
    final list = await getCompletedStories();
    return list.contains(storyId);
  }

  // ========== Play Log (selection-time anti-repeat) ==========
  // Distinct from the 20-entry History. The play log persists
  // storyId → lastPlayedAt for every playback, capped at 1000 entries
  // (FIFO oldest-timestamp). Consumed by ParableService to feed
  // MoodExpansionEngine's "seen" set and LRP ordering across the full
  // library, not just the last 20 plays.

  /// Read the full play log as a `storyId → lastPlayedAt` map.
  /// Returns an empty map if nothing has been recorded yet.
  Future<Map<String, DateTime>> getPlayLog() async {
    final json = _prefs.getString(_keyPlayLog);
    if (json == null) return <String, DateTime>{};
    final raw = jsonDecode(json) as Map<String, dynamic>;
    final out = <String, DateTime>{};
    raw.forEach((storyId, value) {
      final ts = DateTime.tryParse(value as String);
      if (ts != null) out[storyId] = ts;
    });
    return out;
  }

  /// Record a story playback. Updates the lastPlayedAt for [storyId]
  /// and evicts the oldest entries if the 1000-entry cap is exceeded.
  Future<void> recordPlayed(String storyId, {DateTime? at}) async {
    final log = await getPlayLog();
    log[storyId] = at ?? DateTime.now();

    if (log.length > _playLogCap) {
      // Evict oldest by timestamp until at cap.
      final entries = log.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final excess = log.length - _playLogCap;
      for (var i = 0; i < excess; i++) {
        log.remove(entries[i].key);
      }
    }

    final encoded = log.map((k, v) => MapEntry(k, v.toIso8601String()));
    await _prefs.setString(_keyPlayLog, jsonEncode(encoded));
  }

  /// Clear the play log (for testing / reset flows).
  Future<void> clearPlayLog() async {
    await _prefs.remove(_keyPlayLog);
  }

  // ========== Awarded Badges (PALs Paths, Feature 50.11) ==========

  /// Return the set of awarded badge IDs as a list (insertion order).
  /// Empty until Phase 4 (badges are reserved in v1 but not yet awarded).
  Future<List<String>> getAwardedBadges() async {
    final json = _prefs.getString(_keyAwardedBadges);
    if (json == null) return <String>[];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => e as String).toList();
  }

  /// Award a badge. Write-once idempotent. FIFO eviction at 200-entry cap.
  Future<void> addAwardedBadge(String badgeId) async {
    final list = await getAwardedBadges();
    if (list.contains(badgeId)) return; // Idempotent.
    list.add(badgeId);
    if (list.length > _awardedBadgesCap) {
      list.removeRange(0, list.length - _awardedBadgesCap);
    }
    await _prefs.setString(_keyAwardedBadges, jsonEncode(list));
  }

  // ========== Data Migration & Invariant Healing ==========

  /// Validate and heal data invariants (called during app initialization).
  /// Enforces caps on History (20), Favorites (100), Pending Shares (50),
  /// Completed Stories (1000, Feature 50.11), and Awarded Badges (200,
  /// Feature 50.11). Returns a report of what was healed for
  /// debugging/logging.
  Future<Map<String, int>> validateAndHealInvariants() async {
    final report = <String, int>{};

    // Heal History cap (20 entries)
    final historyJson = _prefs.getString(_keyHistory);
    if (historyJson != null) {
      final list = jsonDecode(historyJson) as List<dynamic>;
      if (list.length > 20) {
        final trimmed = list.take(20).toList();
        await _prefs.setString(_keyHistory, jsonEncode(trimmed));
        report['history_trimmed'] = list.length - 20;
      }
    }

    // Heal Favorites cap (100 entries)
    final favoritesJson = _prefs.getString(_keyFavorites);
    if (favoritesJson != null) {
      final list = jsonDecode(favoritesJson) as List<dynamic>;
      if (list.length > 100) {
        final trimmed = list.take(100).toList();
        await _prefs.setString(_keyFavorites, jsonEncode(trimmed));
        report['favorites_trimmed'] = list.length - 100;
      }
    }

    // Heal Pending Shares cap (50 entries)
    final pendingJson = _prefs.getString(_keyPendingShares);
    if (pendingJson != null) {
      final list = jsonDecode(pendingJson) as List<dynamic>;
      if (list.length > 50) {
        final trimmed = list.take(50).toList();
        await _prefs.setString(_keyPendingShares, jsonEncode(trimmed));
        report['pending_shares_trimmed'] = list.length - 50;
      }
    }

    // Heal Completed Stories cap (1000 entries, FIFO oldest-first)
    final completedJson = _prefs.getString(_keyCompletedStories);
    if (completedJson != null) {
      final list = jsonDecode(completedJson) as List<dynamic>;
      if (list.length > _completedStoriesCap) {
        final excess = list.length - _completedStoriesCap;
        final trimmed = list.skip(excess).toList();
        await _prefs.setString(_keyCompletedStories, jsonEncode(trimmed));
        report['completed_stories_trimmed'] = excess;
      }
    }

    // Heal Awarded Badges cap (200 entries, FIFO oldest-first)
    final badgesJson = _prefs.getString(_keyAwardedBadges);
    if (badgesJson != null) {
      final list = jsonDecode(badgesJson) as List<dynamic>;
      if (list.length > _awardedBadgesCap) {
        final excess = list.length - _awardedBadgesCap;
        final trimmed = list.skip(excess).toList();
        await _prefs.setString(_keyAwardedBadges, jsonEncode(trimmed));
        report['awarded_badges_trimmed'] = excess;
      }
    }

    // Heal Play Log cap (1000 entries, oldest-timestamp-first)
    final playLogJson = _prefs.getString(_keyPlayLog);
    if (playLogJson != null) {
      final raw = jsonDecode(playLogJson) as Map<String, dynamic>;
      if (raw.length > _playLogCap) {
        final entries = raw.entries.toList()
          ..sort((a, b) => (a.value as String).compareTo(b.value as String));
        final excess = raw.length - _playLogCap;
        final keep = Map<String, dynamic>.fromEntries(entries.skip(excess));
        await _prefs.setString(_keyPlayLog, jsonEncode(keep));
        report['play_log_trimmed'] = excess;
      }
    }

    return report;
  }

  // ========== Utility ==========

  /// Clear all data (for testing or reset)
  Future<void> clearAll() async {
    await _prefs.clear();
  }

  // ========== Developer Tools ==========

  /// [DEBUG ONLY] Reset first-launch state for dev testing.
  ///
  /// Clears:
  /// - kFirstLaunchCompleteKey (SharedPreferences flag)
  /// - hasCompletedOnboarding, userName, voice consent fields (UserPreferences)
  ///
  /// Preserves:
  /// - bibleTranslation, languageStyle, storytellingMode, kidFriendlyOnly, etc.
  /// - Favorites, history, and all other storage
  ///
  /// This method will throw in release builds.
  Future<void> resetFirstLaunchDevOnly() async {
    // Hard-fail if not in debug mode
    if (!kDebugMode) {
      throw StateError(
        'resetFirstLaunchDevOnly() must only be called in debug builds',
      );
    }

    // 1. Clear the first-launch SharedPreferences key
    await _prefs.remove(kFirstLaunchCompleteKey);

    // 2. Load current preferences and reset onboarding-related fields
    final currentPrefs = await getUserPreferences();
    final clearedPrefs = UserPreferences(
      userName: '', // Clear user name
      bibleTranslation: currentPrefs.bibleTranslation, // Preserve
      languageStyle: currentPrefs.languageStyle, // Preserve
      storytellingMode: currentPrefs.storytellingMode, // Preserve
      contentFilteringEnabled: currentPrefs.contentFilteringEnabled, // Preserve
      kidFriendlyOnly: currentPrefs.kidFriendlyOnly, // Preserve
      showEverydayReflections: currentPrefs.showEverydayReflections, // Preserve
      hasCompletedOnboarding: false, // Clear onboarding flag
      storyNarrationEnabled: null, // Clear voice consent
      palGreetingsEnabled: null, // Clear voice consent
      voiceConsentVersion: null, // Clear voice consent version
    );
    await saveUserPreferences(clearedPrefs);
  }

  /// Reset first-launch state (USER-FACING, release-safe).
  ///
  /// Called from Settings when user explicitly chooses to restart onboarding.
  /// Unlike resetFirstLaunchDevOnly(), this method is safe to call in release builds.
  ///
  /// Clears:
  /// - kFirstLaunchCompleteKey (SharedPreferences flag)
  /// - kPalIntroShownKey (PAL intro overlay flag)
  /// - hasCompletedOnboarding, userName, voice consent fields (UserPreferences)
  ///
  /// Preserves:
  /// - bibleTranslation, languageStyle, storytellingMode, kidFriendlyOnly, etc.
  /// - Favorites, history, and all other storage
  Future<void> resetFirstLaunchUserFacing() async {
    // 1. Clear the first-launch SharedPreferences keys
    await _prefs.remove(kFirstLaunchCompleteKey);
    await _prefs.remove(kPalIntroShownKey);

    // 2. Load current preferences and reset onboarding-related fields
    final currentPrefs = await getUserPreferences();
    final clearedPrefs = UserPreferences(
      userName: '', // Clear user name
      bibleTranslation: currentPrefs.bibleTranslation, // Preserve
      languageStyle: currentPrefs.languageStyle, // Preserve
      storytellingMode: currentPrefs.storytellingMode, // Preserve
      contentFilteringEnabled: currentPrefs.contentFilteringEnabled, // Preserve
      kidFriendlyOnly: currentPrefs.kidFriendlyOnly, // Preserve
      showEverydayReflections: currentPrefs.showEverydayReflections, // Preserve
      hasCompletedOnboarding: false, // Clear onboarding flag
      storyNarrationEnabled: null, // Clear voice consent (tri-state: null = not asked)
      palGreetingsEnabled: null, // Clear voice consent (tri-state: null = not asked)
      voiceConsentVersion: null, // Clear voice consent version
    );
    await saveUserPreferences(clearedPrefs);
  }

  // ========== PALs (Compatibility Shims for Tests) ==========

  /// Get all PALs (sorted: pinned first, then by shareCount descending)
  Future<List<PAL>> getPals() async {
    final json = _prefs.getString(_keyPals);
    if (json == null) return [];

    final list = jsonDecode(json) as List<dynamic>;
    final pals =
        list.map((item) => PAL.fromJson(item as Map<String, dynamic>)).toList();

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
