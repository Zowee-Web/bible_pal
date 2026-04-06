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
import 'package:bible_pal/core/story_length_bucket.dart';

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
