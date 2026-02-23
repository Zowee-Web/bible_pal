import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/audio_service.dart';
import 'package:bible_pal/services/mood_service.dart';
import 'package:bible_pal/services/daily_bread_service.dart';
import 'package:bible_pal/services/content_filter_service.dart';
import 'package:bible_pal/services/share_service.dart';
import 'package:bible_pal/services/pal_audio_service.dart';

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
