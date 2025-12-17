import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/audio_service.dart';
import 'package:bible_pal/services/mood_service.dart';
import 'package:bible_pal/services/daily_bread_service.dart';

/// Service Providers for Riverpod
/// These providers manage the lifecycle of singleton services

// StorageService provider - async initialization required
// keepAlive prevents disposal and ensures stable singleton instance
final storageServiceProvider = FutureProvider<StorageService>((ref) async {
  ref.keepAlive();
  return await StorageService.create();
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
