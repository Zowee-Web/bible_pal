import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/models/favorite.dart';
import 'package:bible_pal/models/history_entry.dart';
import 'package:bible_pal/models/daily_bread.dart';
import 'package:bible_pal/models/pal.dart';
import 'package:bible_pal/models/share_record.dart';
import 'package:bible_pal/core/story_length_bucket.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/mood_service.dart';
import 'package:bible_pal/services/daily_bread_service.dart';
import 'service_providers.dart';

/// App State using Riverpod AsyncNotifier
/// Manages global app state including preferences, favorites, history, and daily bread
class AppState {
  final UserPreferences userPreferences;
  final List<Favorite> favorites;
  final List<HistoryEntry> history;
  final DailyBread? dailyBread;
  final List<PAL> pals;
  final bool isLoading;

  const AppState({
    required this.userPreferences,
    required this.favorites,
    required this.history,
    this.dailyBread,
    required this.pals,
    this.isLoading = false,
  });

  AppState copyWith({
    UserPreferences? userPreferences,
    List<Favorite>? favorites,
    List<HistoryEntry>? history,
    DailyBread? dailyBread,
    List<PAL>? pals,
    bool? isLoading,
  }) {
    return AppState(
      userPreferences: userPreferences ?? this.userPreferences,
      favorites: favorites ?? this.favorites,
      history: history ?? this.history,
      dailyBread: dailyBread ?? this.dailyBread,
      pals: pals ?? this.pals,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// App State Notifier - manages app-wide state
class AppStateNotifier extends AsyncNotifier<AppState> {
  late StorageService _storage;
  late ParableService _parableService;
  late MoodService _moodService;
  late DailyBreadService _dailyBreadService;

  @override
  Future<AppState> build() async {
    // Wait for services to initialize
    _storage = await ref.watch(storageServiceProvider.future);
    _parableService = await ref.watch(parableServiceProvider.future);
    _moodService = ref.watch(moodServiceProvider);
    _dailyBreadService = ref.watch(dailyBreadServiceProvider);

    // Load initial state
    final userPreferences = await _storage.getUserPreferences();
    final favorites = await _storage.getFavorites();
    final history = await _storage.getHistory();
    final pals = await _storage.getPals();
    final dailyBread = await _dailyBreadService.getDailyVerse(userPreferences);

    return AppState(
      userPreferences: userPreferences,
      favorites: favorites,
      history: history,
      dailyBread: dailyBread,
      pals: pals,
    );
  }

  // Getter for MoodService (needed by some screens)
  MoodService get moodService => _moodService;

  // User Preferences Methods
  Future<void> updateUserPreferences(UserPreferences prefs) async {
    state = await AsyncValue.guard(() async {
      await _storage.saveUserPreferences(prefs);

      // Reload daily bread if translation changed
      final dailyBread = await _dailyBreadService.getDailyVerse(prefs);

      return state.requireValue.copyWith(
        userPreferences: prefs,
        dailyBread: dailyBread,
      );
    });
  }

  Future<void> completeOnboarding({
    required String faithTradition,
    required String bibleTranslation,
  }) async {
    final currentState = state.requireValue;
    final prefs = currentState.userPreferences.copyWith(
      faithTradition: faithTradition,
      bibleTranslation: bibleTranslation,
      hasCompletedOnboarding: true,
    );
    await updateUserPreferences(prefs);
  }

  Future<void> updateFaithTradition(String tradition) async {
    final prefs = state.requireValue.userPreferences.copyWith(
      faithTradition: tradition,
    );
    await updateUserPreferences(prefs);
  }

  Future<void> updateBibleTranslation(String translation) async {
    final prefs = state.requireValue.userPreferences.copyWith(
      bibleTranslation: translation,
    );
    await updateUserPreferences(prefs);
  }

  Future<void> updateStorytellingMode(String mode) async {
    final prefs = state.requireValue.userPreferences.copyWith(
      storytellingMode: mode,
    );
    await updateUserPreferences(prefs);
  }

  Future<void> updateStoryLanguage(String storyLanguage) async {
    final prefs = state.requireValue.userPreferences.copyWith(
      storyLanguage: storyLanguage,
    );
    await updateUserPreferences(prefs);
  }

  Future<void> updateKidFriendlyOnly(bool kidFriendlyOnly) async {
    final prefs = state.requireValue.userPreferences.copyWith(
      kidFriendlyOnly: kidFriendlyOnly,
    );
    await updateUserPreferences(prefs);
  }

  Future<void> updateShowEverydayReflections(bool showEverydayReflections) async {
    final prefs = state.requireValue.userPreferences.copyWith(
      showEverydayReflections: showEverydayReflections,
    );
    await updateUserPreferences(prefs);
  }

  // Voice Consent Methods (Phase 3)

  /// Update voice consent settings.
  /// Called when user responds to voice consent dialog or toggles in settings.
  Future<void> updateVoiceConsent({
    bool? storyNarrationEnabled,
    bool? palGreetingsEnabled,
  }) async {
    final prefs = state.requireValue.userPreferences.copyWith(
      storyNarrationEnabled: storyNarrationEnabled,
      palGreetingsEnabled: palGreetingsEnabled,
      voiceConsentVersion: currentVoiceConsentVersion,
    );
    await updateUserPreferences(prefs);
  }

  /// Update story narration consent only
  Future<void> updateStoryNarrationConsent(bool enabled) async {
    final prefs = state.requireValue.userPreferences.copyWith(
      storyNarrationEnabled: enabled,
      voiceConsentVersion: currentVoiceConsentVersion,
    );
    await updateUserPreferences(prefs);
  }

  /// Update PAL greetings consent only
  Future<void> updatePalGreetingsConsent(bool enabled) async {
    final prefs = state.requireValue.userPreferences.copyWith(
      palGreetingsEnabled: enabled,
      voiceConsentVersion: currentVoiceConsentVersion,
    );
    await updateUserPreferences(prefs);
  }

  // Favorites Methods
  Future<void> addFavorite(Parable parable) async {
    state = await AsyncValue.guard(() async {
      final favorite = Favorite.fromParable(parable);
      await _storage.addFavorite(favorite);
      final favorites = await _storage.getFavorites();
      return state.requireValue.copyWith(favorites: favorites);
    });
  }

  Future<void> removeFavorite(String storyId) async {
    state = await AsyncValue.guard(() async {
      await _storage.removeFavorite(storyId);
      final favorites = await _storage.getFavorites();
      return state.requireValue.copyWith(favorites: favorites);
    });
  }

  Future<bool> isFavorited(String storyId) async {
    return _storage.isFavorited(storyId);
  }

  Future<void> updateFavoriteTitle(String storyId, String newTitle) async {
    state = await AsyncValue.guard(() async {
      await _storage.saveEditedTitle(storyId, newTitle);

      final favorites = state.requireValue.favorites.map((f) {
        if (f.storyId == storyId) {
          return f.copyWith(title: newTitle);
        }
        return f;
      }).toList();

      await _storage.saveFavorites(favorites);

      return state.requireValue.copyWith(favorites: favorites);
    });
  }

  // History Methods
  Future<void> addToHistory(Parable parable) async {
    state = await AsyncValue.guard(() async {
      final entry = HistoryEntry.fromParable(parable);
      await _storage.addToHistory(entry);
      final history = await _storage.getHistory();
      return state.requireValue.copyWith(history: history);
    });
  }

  Future<void> clearHistory() async {
    state = await AsyncValue.guard(() async {
      await _storage.clearHistory();
      final history = await _storage.getHistory();
      return state.requireValue.copyWith(history: history);
    });
  }

  // Parable Selection
  Future<Parable?> selectParable({
    required String mood,
    required StoryLengthBucket lengthBucket,
    String? userText,
  }) async {
    return _parableService.selectParable(
      mood: mood,
      lengthBucket: lengthBucket,
      userPrefs: state.requireValue.userPreferences,
      userText: userText,
    );
  }

  Future<Parable?> getParableById(String storyId) async {
    return _parableService.getParableById(storyId);
  }

  // PAL Methods
  Future<void> addPal(PAL pal) async {
    state = await AsyncValue.guard(() async {
      await _storage.addPal(pal);
      final pals = await _storage.getPals();
      return state.requireValue.copyWith(pals: pals);
    });
  }

  Future<void> removePal(String palId) async {
    state = await AsyncValue.guard(() async {
      await _storage.removePal(palId);
      final pals = await _storage.getPals();
      return state.requireValue.copyWith(pals: pals);
    });
  }

  Future<void> updatePal(PAL pal) async {
    state = await AsyncValue.guard(() async {
      await _storage.updatePal(pal);
      final pals = await _storage.getPals();
      return state.requireValue.copyWith(pals: pals);
    });
  }

  Future<List<ShareRecord>> getSharesToPal(String palId) async {
    return _storage.getSharesToPal(palId);
  }

  Future<void> shareStoryWithPal(ShareRecord share) async {
    state = await AsyncValue.guard(() async {
      // Add share record
      await _storage.addShare(share);

      // Increment share count for the PAL
      await _storage.incrementPalShareCount(share.toPalId);

      // Reload PALs to reflect updated share counts
      final pals = await _storage.getPals();
      return state.requireValue.copyWith(pals: pals);
    });
  }

  // Utility
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final userPreferences = await _storage.getUserPreferences();
      final favorites = await _storage.getFavorites();
      final history = await _storage.getHistory();
      final pals = await _storage.getPals();
      final dailyBread =
          await _dailyBreadService.getDailyVerse(userPreferences);

      return AppState(
        userPreferences: userPreferences,
        favorites: favorites,
        history: history,
        dailyBread: dailyBread,
        pals: pals,
      );
    });
  }
}

/// App State Provider - main app state
final appStateProvider =
    AsyncNotifierProvider<AppStateNotifier, AppState>(AppStateNotifier.new);
