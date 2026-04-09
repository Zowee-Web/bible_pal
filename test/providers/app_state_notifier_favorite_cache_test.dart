// Smart Offline Library v1 — regression guard for the addFavorite hook.
// SPEC Feature 27 + INVARIANT: Favorited Audio Protection.
//
// This test exists ONLY to protect the wiring between
// AppStateNotifier.addFavorite() and ParableService.ensureCachedForFavorite().
// It does NOT exercise the cache directory, network, or eviction (those
// are covered by parable_service_offline_library_test.dart). The whole
// purpose is to fail loudly if a future refactor accidentally drops the
// fire-and-forget call.

import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/providers/app_state_notifier.dart';
import 'package:bible_pal/providers/service_providers.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal ParableService subclass that records ensureCachedForFavorite calls.
/// We DO NOT override anything else — the production constructor handles
/// all the rest. testMode=true bypasses on-disk audio validation.
class _RecordingParableService extends ParableService {
  _RecordingParableService(StorageService storage)
      : super(storage, null, true);

  int callCount = 0;
  Parable? lastEnsured;

  @override
  Future<void> ensureCachedForFavorite(Parable parable) async {
    callCount += 1;
    lastEnsured = parable;
  }
}

Parable _testParable() => const Parable(
      storyId: 'story_test_hook_001',
      title: 'Test Story',
      mood: 'joyful',
      storytellingMode: 'creative',
      kidFriendly: false,
      audioFilePath: 'creative/9999/audio_9999_story_short.mp3',
      storyLength: 'short',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'addFavorite triggers ensureCachedForFavorite on ParableService exactly once',
    () async {
      SharedPreferences.setMockInitialValues({});

      final storage = await StorageService.create();
      final fake = _RecordingParableService(storage);

      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWith((ref) async => storage),
          parableServiceProvider.overrideWith((ref) async => fake),
        ],
      );
      addTearDown(container.dispose);

      // Force the AppStateNotifier to build (resolving its dependencies on
      // the overridden providers above).
      await container.read(appStateProvider.future);

      final parable = _testParable();
      await container.read(appStateProvider.notifier).addFavorite(parable);

      // The hook is `unawaited(...)` — flush microtasks so the call lands
      // before we assert.
      await Future<void>.delayed(Duration.zero);

      expect(fake.callCount, 1,
          reason: 'addFavorite must invoke ensureCachedForFavorite exactly '
              'once on the ParableService');
      expect(fake.lastEnsured?.storyId, parable.storyId,
          reason: 'the same parable that was favorited must be passed through');
    },
  );
}
