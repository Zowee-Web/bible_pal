import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/ambient_audio_service.dart';
import 'package:bible_pal/services/audio_service.dart';
import 'package:bible_pal/services/mood_service.dart';
import 'package:bible_pal/services/daily_bread_service.dart';
import 'package:bible_pal/services/content_filter_service.dart';
import 'package:bible_pal/services/share_service.dart';
import 'package:bible_pal/services/pal_audio_service.dart';
import 'package:bible_pal/services/pal_tts_client.dart';
import 'package:bible_pal/services/name_audio_service.dart';
import 'package:bible_pal/services/completed_stories_store.dart';
import 'package:bible_pal/services/path_service.dart';
import 'package:bible_pal/services/search_service.dart';
import 'package:bible_pal/core/character_registry.dart';
import 'package:bible_pal/core/story_length_bucket.dart';
import 'package:bible_pal/providers/app_state_notifier.dart';

/// Service Providers for Riverpod
/// These providers manage the lifecycle of singleton services

// StorageService provider - async initialization required
// keepAlive prevents disposal and ensures stable singleton instance
final storageServiceProvider = FutureProvider<StorageService>((ref) async {
  ref.keepAlive();
  final storage = await StorageService.create();

  // Validate and heal data invariants (caps on History/Favorites/Pending Shares)
  await storage.validateAndHealInvariants();

  return storage;
});

// ParableService provider - async-safe, depends on StorageService
// Returns ParableService after StorageService is initialized
final parableServiceProvider = FutureProvider<ParableService>((ref) async {
  final storageService = await ref.watch(storageServiceProvider.future);
  return ParableService(storageService);
});

// AudioService provider - singleton
final audioServiceProvider = Provider<AudioService>((ref) {
  return AudioService();
});

// AmbientAudioService provider - background sound during story playback
final ambientAudioServiceProvider = Provider<AmbientAudioService>((ref) {
  final service = AmbientAudioService();
  ref.onDispose(() => service.dispose());
  return service;
});

// MoodService provider - singleton
final moodServiceProvider = Provider<MoodService>((ref) {
  return MoodService();
});

// DailyBreadService provider - singleton
final dailyBreadServiceProvider = Provider<DailyBreadService>((ref) {
  return DailyBreadService();
});

// ContentFilterService provider - singleton
final contentFilterServiceProvider = Provider<ContentFilterService>((ref) {
  return ContentFilterService();
});

// ShareService provider - singleton
final shareServiceProvider = Provider<ShareService>((ref) {
  return ShareService();
});

// PalAudioService provider - offline PAL conversation audio
final palAudioServiceProvider = Provider<PalAudioService>((ref) {
  final service = PalAudioService();
  ref.onDispose(() => service.dispose());
  return service;
});

// PalTtsClient provider - proxy HTTP client for name audio TTS
final palTtsClientProvider = Provider<PalTtsClient>((ref) {
  final apiKey = dotenv.maybeGet('ELEVENLABS_API_KEY');
  final client = PalTtsClient(elevenLabsApiKey: apiKey);
  ref.onDispose(() => client.dispose());
  return client;
});

// NameAudioService provider - generates + caches personalized name clips
final nameAudioServiceProvider = Provider<NameAudioService>((ref) {
  final ttsClient = ref.read(palTtsClientProvider);
  return NameAudioService(ttsClient: ttsClient);
});

// Session-scoped story length bucket (not persisted, resets on app restart)
final sessionLengthBucketProvider = StateProvider<StoryLengthBucket>(
  (ref) => StoryLengthBucket.short,
);

// CompletedStoriesStore provider — PALs Paths completion persistence
// (SPEC Feature 50.4 + 50.11). Depends on StorageService for the
// underlying SharedPreferences access. Capacity is healed on startup
// by StorageService.validateAndHealInvariants().
final completedStoriesStoreProvider =
    FutureProvider<CompletedStoriesStore>((ref) async {
  final storage = await ref.watch(storageServiceProvider.future);
  return CompletedStoriesStore(storage);
});

/// Reactive snapshot of all completed story IDs (Phase 3, SPEC Feature
/// 50.4 + 50.11). Watched by [pathServiceProvider] so that when a story
/// is marked completed in the player hook (via `ref.invalidate`), the
/// PathService rebuilds with the fresh set and UI widgets reading
/// completion state re-render automatically.
///
/// The invalidation pattern keeps PathService a pure function over its
/// constructor inputs — no direct dependency on CompletedStoriesStore.
final completedStoryIdsProvider = FutureProvider<Set<String>>((ref) async {
  final store = await ref.watch(completedStoriesStoreProvider.future);
  final list = await store.all();
  return Set<String>.unmodifiable(list);
});

/// Loads the curated Life of Jesus sequence from the bundled asset
/// (SPEC Feature 50.1b). Returns an empty list if the asset is missing
/// or malformed — PathService handles empty sequence gracefully.
Future<List<String>> _loadJesusLifeSequence() async {
  try {
    final jsonStr =
        await rootBundle.loadString('assets/stories/jesus_life_index.json');
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final sequence = data['sequence'] as List<dynamic>? ?? const [];
    return sequence.map((e) => e as String).toList();
  } catch (_) {
    return const <String>[];
  }
}

// PathService provider — PALs Paths navigation + progression (SPEC
// Feature 50). Phase 2 constructs PathService from a fresh read-only
// snapshot of Traditional parables + the curated jesus_life sequence
// + the current kid-mode flag. Phase 3 adds the completed-story-id
// snapshot so getResumePoint and getCompletionPercentage work.
// PathService is deterministic and stays decoupled from
// ParableService selection logic (it never calls `selectParable()`).
//
// The provider is FutureProvider because loading the manifest is async.
// It also preloads the CharacterRegistry so display labels resolve in
// the Characters path list. Watching completedStoryIdsProvider means
// any invalidation of the completion set rebuilds PathService with a
// fresh snapshot automatically.
final pathServiceProvider = FutureProvider<PathService>((ref) async {
  // Preload CharacterRegistry so getDisplayName() works synchronously.
  await CharacterRegistry.ensureLoaded();

  final parableService = await ref.watch(parableServiceProvider.future);
  final traditionalParables =
      await parableService.getAllTraditionalParables();
  final jesusLifeSequence = await _loadJesusLifeSequence();

  // Kid-mode flag reads from the current user preferences. Using
  // ref.watch on appStateProvider means PathService rebuilds
  // reactively when kid mode toggles — a kid-mode user who flips the
  // toggle mid-session sees an immediately-updated path snapshot.
  final appState = ref.watch(appStateProvider);
  final kidFriendlyOnly =
      appState.valueOrNull?.userPreferences.kidFriendlyOnly ?? false;

  // Phase 3: snapshot the completed story IDs so getResumePoint and
  // getCompletionPercentage work. The player hook invalidates
  // completedStoryIdsProvider after markCompleted, which causes this
  // provider to rebuild with the fresh set.
  final completedStoryIds =
      await ref.watch(completedStoryIdsProvider.future);

  return PathService(
    traditionalParables: traditionalParables,
    jesusLifeSequence: jesusLifeSequence,
    kidFriendlyOnly: kidFriendlyOnly,
    completedStoryIds: completedStoryIds,
  );
});

// SearchService provider — priority-ranked Traditional-only search
// (SPEC Feature 50.7). Same snapshot pattern as PathService:
// deterministic, decoupled, kid-mode filtered at construction time.
// The raw search query string is NEVER logged or persisted.
final searchServiceProvider = FutureProvider<SearchService>((ref) async {
  final parableService = await ref.watch(parableServiceProvider.future);
  final traditionalParables =
      await parableService.getAllTraditionalParables();

  final appState = ref.watch(appStateProvider);
  final kidFriendlyOnly =
      appState.valueOrNull?.userPreferences.kidFriendlyOnly ?? false;

  return SearchService(
    traditionalParables: traditionalParables,
    kidFriendlyOnly: kidFriendlyOnly,
  );
});
