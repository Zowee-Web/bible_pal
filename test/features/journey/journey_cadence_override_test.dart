@Tags(['requires_journey_testing_define'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_pal/core/journey_testing_config.dart';
import 'package:bible_pal/features/pal_memory/pal_session_store.dart';
import 'package:bible_pal/services/storage_service.dart';

/// Regression coverage for the beta cadence override — the storage-shift
/// seam in [PalSessionStore.getLastJourneyContinuationSpokenAt] that
/// collapses the engine's fixed 3-day cooldown to a selected window,
/// WITHOUT touching the pure engine or fireJourneyOffer.
///
/// The override is compiled behind JOURNEY_TESTING_ENABLED, so these run
/// only under:
///   flutter test --run-skipped --tags=requires_journey_testing_define \
///     --dart-define=JOURNEY_TESTING_ENABLED=true
void main() {
  late StorageService storage;
  late PalSessionStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    store = PalSessionStore(storage);
  });

  test('the JOURNEY_TESTING_ENABLED define is set for this run', () {
    expect(kJourneyTestingEnabled, isTrue,
        reason: 'run with --dart-define=JOURNEY_TESTING_ENABLED=true');
  });

  test('no override → raw anchor returned unchanged', () async {
    final t = DateTime.now().subtract(const Duration(minutes: 1));
    await storage.setLastJourneyContinuationSpokenAt(t);
    final got = await store.getLastJourneyContinuationSpokenAt();
    expect(got, isNotNull);
    expect(got!.difference(t).inSeconds.abs(), lessThan(2));
  });

  test('5m cadence, within window → still on cooldown (non-null)', () async {
    await storage.setLastJourneyContinuationSpokenAt(
        DateTime.now().subtract(const Duration(minutes: 1)));
    await store.setJourneyCadenceOverride(const Duration(minutes: 5));
    // elapsed 1m < 5m → engine must still block → getter returns the real
    // recent anchor (non-null, well within the engine's 3-day window).
    expect(await store.getLastJourneyContinuationSpokenAt(), isNotNull);
  });

  test('5m cadence, past window → eligible (null)', () async {
    await storage.setLastJourneyContinuationSpokenAt(
        DateTime.now().subtract(const Duration(minutes: 6)));
    await store.setJourneyCadenceOverride(const Duration(minutes: 5));
    // elapsed 6m >= 5m → getter returns null so the engine treats it as
    // "no prior offer" → eligible.
    expect(await store.getLastJourneyContinuationSpokenAt(), isNull);
  });

  test('disabled (zero) → always eligible, even right after speaking',
      () async {
    await storage.setLastJourneyContinuationSpokenAt(DateTime.now());
    await store.setJourneyCadenceOverride(Duration.zero);
    expect(await store.getLastJourneyContinuationSpokenAt(), isNull);
  });

  test('setting override to null restores production (raw anchor)', () async {
    final t = DateTime.now();
    await storage.setLastJourneyContinuationSpokenAt(t);
    await store.setJourneyCadenceOverride(const Duration(minutes: 5));
    await store.setJourneyCadenceOverride(null);
    expect(await store.getLastJourneyContinuationSpokenAt(), isNotNull);
  });

  test('clear() also drops the cadence override', () async {
    await store.setJourneyCadenceOverride(const Duration(minutes: 5));
    await store.clear();
    expect(await store.getJourneyCadenceOverride(), isNull);
  });

  test('clearJourneyCooldownOnly resets cooldown but keeps sessions',
      () async {
    await store.seedDanielArcSession();
    await storage.setLastJourneyContinuationSpokenAt(DateTime.now());
    await store.clearJourneyCooldownOnly();
    expect((await store.all()).length, 1);
    expect(await storage.getLastJourneyContinuationSpokenAt(), isNull);
  });

  test('seedDanielArcSession records a Daniel-1 mappable session', () async {
    await store.seedDanielArcSession();
    final sessions = await store.all();
    expect(sessions.length, 1);
    // Engine adult pattern extracts the leading number; 1486 = Daniel 1.
    expect(sessions.single.storyId, contains('1486'));
  });
}
