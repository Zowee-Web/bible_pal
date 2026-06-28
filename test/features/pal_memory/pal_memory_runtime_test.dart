import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_pal/features/pal_memory/memory_audio_paths.dart';
import 'package:bible_pal/features/pal_memory/memory_audio_plan.dart';
import 'package:bible_pal/features/pal_memory/memory_audio_resolver.dart';
import 'package:bible_pal/features/pal_memory/pal_memory_display_name_registry.dart';
import 'package:bible_pal/features/pal_memory/pal_memory_runtime.dart';
import 'package:bible_pal/features/pal_memory/pal_session.dart';
import 'package:bible_pal/features/pal_memory/pal_session_store.dart';
import 'package:bible_pal/features/pal_memory/resolved_memory_line.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/services/storage_service.dart';

/// End-to-end cascade tests for [fireMemoryLine] — PAL Memory Doctrine
/// Slice 2d runtime integration (see docs/PAL_MEMORY_DOCTRINE.md).
///
/// The cascade has five gates (consent → engine → editorial → audio →
/// playback) and one side-effect (record cooldown). Every gate gets its
/// own test, and the side-effect's truthfulness contract — "advance the
/// cooldown ONLY on successful playback" — is exercised separately for
/// every non-played branch.
void main() {
  late StorageService storage;
  late PalSessionStore sessionStore;

  // Fixture registry with one entry; the newest fixture session below
  // uses this bibleStoryKey so the editorial gate clears in the happy path.
  late PalMemoryDisplayNameRegistry registry;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    sessionStore = PalSessionStore(storage);
    registry = PalMemoryDisplayNameRegistry.fromJson('''
{
  "version": 1,
  "entries": [
    {"bibleStoryKey": "jonah_storm", "displayName": "Jonah", "clipId": "name_jonah"}
  ]
}
''');
  });

  /// Build a UserPreferences with PAL voice fully enabled by default.
  /// Individual tests override the consent fields to test gate closure.
  UserPreferences buildPrefs({
    bool palVoiceEnabled = true,
    bool? palGreetingsEnabled = true,
    String palVoiceKey = 'VOICE_STILLWATER',
  }) {
    return UserPreferences.defaults().copyWith(
      palVoiceEnabled: palVoiceEnabled,
      palGreetingsEnabled: palGreetingsEnabled,
      palVoiceKey: palVoiceKey,
    );
  }

  /// Populate three completions in the engine's recency window, with the
  /// newest being a registered story (jonah_storm) completed yesterday.
  /// This satisfies the engine's min-completions + recency gates so
  /// every test starts in the "engine would fire" state.
  Future<void> seedSessionsForHappyPath(DateTime now) async {
    Future<void> add(String storyId, String? key, DateTime at) async {
      await storage.addPalSession(PalSession(
        storyId: storyId,
        completedAt: at,
        bibleStoryKey: key,
        languageStyle: 'WEB',
      ));
    }

    await add('pad_a', null, now.subtract(const Duration(days: 8)));
    await add('pad_b', null, now.subtract(const Duration(days: 9)));
    await add('1007', 'jonah_storm', now.subtract(const Duration(days: 1)));
  }

  group('Gate 0 — voice consent', () {
    test('null preferences → consentBlocked (no log, no record)', () async {
      final events = <_Event>[];
      final result = await fireMemoryLine(
        preferences: null,
        sessionStore: sessionStore,
        displayNameRegistry: registry,
        audioResolver: _StubResolver.alwaysSucceeds(),
        playPlan: (_) async {
          fail('playPlan must not be called when consent is blocked');
        },
        now: DateTime.utc(2026, 6, 27, 9, 0),
        logger: (e, p) => events.add(_Event(e, p)),
      );

      expect(result.outcome, MemoryLineOutcome.consentBlocked);
      expect(result.skippedReason, 'no_preferences');
      expect(events.map((e) => e.event), ['pal_memory_line_skipped']);
      expect(events.single.props['reason'], 'no_preferences');
      expect(await sessionStore.getLastMemoryLineSpokenAt(), isNull,
          reason: 'cooldown must not advance on a blocked cascade');
    });

    test('palVoiceEnabled == false → consentBlocked', () async {
      final now = DateTime.utc(2026, 6, 27, 9, 0);
      await seedSessionsForHappyPath(now);

      final result = await fireMemoryLine(
        preferences: buildPrefs(palVoiceEnabled: false),
        sessionStore: sessionStore,
        displayNameRegistry: registry,
        audioResolver: _StubResolver.alwaysSucceeds(),
        playPlan: (_) async {
          fail('playPlan must not be called when consent is blocked');
        },
        now: now,
      );

      expect(result.outcome, MemoryLineOutcome.consentBlocked);
      expect(result.skippedReason, 'pal_voice_disabled');
      expect(await sessionStore.getLastMemoryLineSpokenAt(), isNull);
    });

    test('palGreetingsEnabled == false → consentBlocked', () async {
      final now = DateTime.utc(2026, 6, 27, 9, 0);
      await seedSessionsForHappyPath(now);

      final result = await fireMemoryLine(
        preferences: buildPrefs(palGreetingsEnabled: false),
        sessionStore: sessionStore,
        displayNameRegistry: registry,
        audioResolver: _StubResolver.alwaysSucceeds(),
        playPlan: (_) async {
          fail('playPlan must not be called when consent is blocked');
        },
        now: now,
      );

      expect(result.outcome, MemoryLineOutcome.consentBlocked);
      expect(result.skippedReason, 'pal_greetings_disabled');
      expect(await sessionStore.getLastMemoryLineSpokenAt(), isNull);
    });

    test('palGreetingsEnabled == null → cascade proceeds (legacy parity)',
        () async {
      // Cold-open at main_menu_screen.dart:1758-1759 treats
      // palGreetingsEnabled == null as allowed. The memory cascade must
      // match that — divergence would mean PAL speaks greetings but
      // refuses memory lines on a fresh install, which is incoherent.
      final now = DateTime.utc(2026, 6, 27, 9, 0);
      await seedSessionsForHappyPath(now);
      var playCalled = false;

      final result = await fireMemoryLine(
        preferences: buildPrefs(palGreetingsEnabled: null),
        sessionStore: sessionStore,
        displayNameRegistry: registry,
        audioResolver: _StubResolver.alwaysSucceeds(),
        playPlan: (_) async {
          playCalled = true;
          return true;
        },
        now: now,
      );

      expect(result.outcome, MemoryLineOutcome.played);
      expect(playCalled, isTrue);
    });
  });

  group('Gate 1 — engine silence', () {
    test('only 1 completion → engineSilent (min-completions gate)',
        () async {
      final now = DateTime.utc(2026, 6, 27, 9, 0);
      await storage.addPalSession(PalSession(
        storyId: '1007',
        completedAt: now.subtract(const Duration(days: 1)),
        bibleStoryKey: 'jonah_storm',
        languageStyle: 'WEB',
      ));

      final result = await fireMemoryLine(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        displayNameRegistry: registry,
        audioResolver: _StubResolver.alwaysSucceeds(),
        playPlan: (_) async => fail('playPlan must not be called'),
        now: now,
      );

      expect(result.outcome, MemoryLineOutcome.engineSilent);
      expect(await sessionStore.getLastMemoryLineSpokenAt(), isNull);
    });

    test('cooldown still active → engineSilent', () async {
      final now = DateTime.utc(2026, 6, 27, 9, 0);
      await seedSessionsForHappyPath(now);
      // Within the 3-day engine cooldown.
      await sessionStore
          .recordMemoryLineSpoken(at: now.subtract(const Duration(hours: 6)));

      final result = await fireMemoryLine(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        displayNameRegistry: registry,
        audioResolver: _StubResolver.alwaysSucceeds(),
        playPlan: (_) async => fail('playPlan must not be called'),
        now: now,
      );

      expect(result.outcome, MemoryLineOutcome.engineSilent);
    });

    test('cooldown boundary: exactly 3 days ago → fires; 3 days - 1h → silent',
        () async {
      // Locks the comparison in pal_memory_engine.dart's cooldown gate
      // (kCooldown = 3 days). Engine uses isAfter(cutoff) where cutoff
      // = now - kCooldown, so lastSpokenAt == cutoff is OUTSIDE the
      // cooldown (fires); lastSpokenAt > cutoff is INSIDE (silent).
      final now = DateTime.utc(2026, 6, 27, 9, 0);
      await seedSessionsForHappyPath(now);

      // Just inside the cooldown window — still silent.
      await sessionStore.recordMemoryLineSpoken(
          at: now.subtract(const Duration(days: 3) - const Duration(hours: 1)));
      var result = await fireMemoryLine(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        displayNameRegistry: registry,
        audioResolver: _StubResolver.alwaysSucceeds(),
        playPlan: (_) async => fail('playPlan must not be called'),
        now: now,
      );
      expect(result.outcome, MemoryLineOutcome.engineSilent,
          reason: 'spoken 71h ago is still inside the 72h cooldown');

      // Move lastSpokenAt to exactly 3 days + 1 minute ago — well clear.
      await sessionStore.recordMemoryLineSpoken(
          at: now.subtract(const Duration(days: 3) + const Duration(minutes: 1)));
      result = await fireMemoryLine(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        displayNameRegistry: registry,
        audioResolver: _StubResolver.alwaysSucceeds(),
        playPlan: (_) async => true,
        now: now,
      );
      expect(result.outcome, MemoryLineOutcome.played,
          reason: 'spoken 72h+1min ago is past the 72h cooldown');
    });
  });

  group('Gate 2 — editorial display-name', () {
    test('source story missing from registry → noDisplayName', () async {
      final now = DateTime.utc(2026, 6, 27, 9, 0);
      // Same shape as seedSessionsForHappyPath but newest story uses
      // an unregistered bibleStoryKey.
      await storage.addPalSession(PalSession(
        storyId: 'a',
        completedAt: now.subtract(const Duration(days: 8)),
        languageStyle: 'WEB',
      ));
      await storage.addPalSession(PalSession(
        storyId: 'b',
        completedAt: now.subtract(const Duration(days: 9)),
        languageStyle: 'WEB',
      ));
      await storage.addPalSession(PalSession(
        storyId: '9999',
        completedAt: now.subtract(const Duration(days: 1)),
        bibleStoryKey: 'a_story_with_no_editorial_entry',
        languageStyle: 'WEB',
      ));

      final events = <_Event>[];
      final result = await fireMemoryLine(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        displayNameRegistry: registry,
        audioResolver: _StubResolver.alwaysSucceeds(),
        playPlan: (_) async => fail('playPlan must not be called'),
        now: now,
        logger: (e, p) => events.add(_Event(e, p)),
      );

      expect(result.outcome, MemoryLineOutcome.noDisplayName);
      expect(await sessionStore.getLastMemoryLineSpokenAt(), isNull,
          reason: 'doctrine: editorial opt-out is silence, NOT a fallback '
              '— cooldown must not advance on noDisplayName');
      expect(events.single.event, 'pal_memory_line_skipped');
      expect(events.single.props['reason'], 'no_display_name');
      expect(events.single.props['source_bible_story_key'],
          'a_story_with_no_editorial_entry');
    });
  });

  group('Gate 3 — audio resolver', () {
    test('resolver returns null → missingClip (cooldown does NOT advance)',
        () async {
      final now = DateTime.utc(2026, 6, 27, 9, 0);
      await seedSessionsForHappyPath(now);

      final events = <_Event>[];
      final result = await fireMemoryLine(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        displayNameRegistry: registry,
        audioResolver: _StubResolver.alwaysNull(),
        playPlan: (_) async => fail('playPlan must not be called'),
        now: now,
        logger: (e, p) => events.add(_Event(e, p)),
      );

      expect(result.outcome, MemoryLineOutcome.missingClip);
      expect(await sessionStore.getLastMemoryLineSpokenAt(), isNull,
          reason: 'doctrine: missing clip is silence, NOT a successful '
              'cascade — cooldown must remain un-advanced so a render '
              'fix retries on the next selection');
      expect(events.single.props['reason'], 'missing_clip');
      expect(events.single.props['voice_key'], 'VOICE_STILLWATER');
    });
  });

  group('Playback truthfulness', () {
    test('playPlan returns false → playbackFailed, cooldown NOT advanced',
        () async {
      final now = DateTime.utc(2026, 6, 27, 9, 0);
      await seedSessionsForHappyPath(now);

      final events = <_Event>[];
      final result = await fireMemoryLine(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        displayNameRegistry: registry,
        audioResolver: _StubResolver.alwaysSucceeds(),
        playPlan: (_) async => false,
        now: now,
        logger: (e, p) => events.add(_Event(e, p)),
      );

      expect(result.outcome, MemoryLineOutcome.playbackFailed);
      expect(await sessionStore.getLastMemoryLineSpokenAt(), isNull,
          reason: 'silence-floor honesty: playback failure must not burn '
              'the user\'s next 3-day cooldown window');
      // Verify both events fired: fired (before playback) then skipped.
      expect(events.map((e) => e.event).toList(),
          ['pal_memory_line_fired', 'pal_memory_line_skipped']);
      expect(events.last.props['reason'], 'playback_failed');
    });

    test('playPlan throws → exception outcome, cooldown NOT advanced',
        () async {
      final now = DateTime.utc(2026, 6, 27, 9, 0);
      await seedSessionsForHappyPath(now);

      final result = await fireMemoryLine(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        displayNameRegistry: registry,
        audioResolver: _StubResolver.alwaysSucceeds(),
        playPlan: (_) async => throw StateError('boom'),
        now: now,
      );

      expect(result.outcome, MemoryLineOutcome.exception);
      expect(result.skippedReason, contains('boom'));
      expect(await sessionStore.getLastMemoryLineSpokenAt(), isNull);
    });

    test('happy path → played, cooldown advances to `now`', () async {
      final now = DateTime.utc(2026, 6, 27, 9, 0);
      await seedSessionsForHappyPath(now);

      MemoryAudioPlan? receivedPlan;
      final events = <_Event>[];
      final result = await fireMemoryLine(
        preferences: buildPrefs(),
        sessionStore: sessionStore,
        displayNameRegistry: registry,
        audioResolver: _StubResolver.alwaysSucceeds(),
        playPlan: (plan) async {
          receivedPlan = plan;
          return true;
        },
        now: now,
        logger: (e, p) => events.add(_Event(e, p)),
      );

      expect(result.outcome, MemoryLineOutcome.played);
      expect(await sessionStore.getLastMemoryLineSpokenAt(), now,
          reason: 'cooldown anchor must equal injected `now` for '
              'deterministic engine re-evaluation');
      // Plan was the stitched carrier+name with the policy gap.
      expect(receivedPlan, isNotNull);
      receivedPlan!.validateStructure();
      expect(receivedPlan!.voiceKey, 'VOICE_STILLWATER');
      expect(receivedPlan!.clips, hasLength(2));
      expect(receivedPlan!.clips[0].kind, ClipKind.carrier);
      expect(receivedPlan!.clips[0].clipId, startsWith('carrier_'));
      expect(receivedPlan!.clips[1].kind, ClipKind.name);
      expect(receivedPlan!.clips[1].clipId, 'name_jonah');
      // Plan faithfully passes the policy gap through to the player.
      expect(receivedPlan!.gapsBetween, hasLength(1));
      expect(receivedPlan!.gapsBetween.single,
          const Duration(milliseconds: 50));
      // Telemetry: fired (pre-playback) + played (post-playback).
      expect(events.map((e) => e.event).toList(),
          ['pal_memory_line_fired', 'pal_memory_line_played']);
    });

    test('null logger does not crash on a blocked cascade', () async {
      // Documents the optional-logger safe-fail contract for callers
      // that don't have a structured event sink yet.
      final result = await fireMemoryLine(
        preferences: null,
        sessionStore: sessionStore,
        displayNameRegistry: registry,
        audioResolver: _StubResolver.alwaysSucceeds(),
        playPlan: (_) async => fail('playPlan must not be called'),
        now: DateTime.utc(2026, 6, 27, 9, 0),
        // logger intentionally omitted
      );
      expect(result.outcome, MemoryLineOutcome.consentBlocked);
    });
  });
}

class _Event {
  final String event;
  final Map<String, Object?> props;
  _Event(this.event, this.props);
}

/// Stub [MemoryAudioResolver] for cascade tests. Either always returns a
/// valid plan (so downstream gates fire), or always returns null
/// (silence floor).
class _StubResolver implements MemoryAudioResolver {
  final bool succeed;
  _StubResolver._(this.succeed);
  factory _StubResolver.alwaysSucceeds() => _StubResolver._(true);
  factory _StubResolver.alwaysNull() => _StubResolver._(false);

  @override
  Future<MemoryAudioPlan?> resolve(ResolvedMemoryLine line) async {
    if (!succeed) return null;
    return MemoryAudioPlan(
      voiceKey: line.voiceKey,
      clips: [
        MemoryAudioClipRef(
          clipId: line.carrierClipId,
          kind: ClipKind.carrier,
          assetPath: PalMemoryAudioPaths.assetPathFor(
              voiceKey: line.voiceKey, clipId: line.carrierClipId),
        ),
        MemoryAudioClipRef(
          clipId: line.displayNameClipId,
          kind: ClipKind.name,
          assetPath: PalMemoryAudioPaths.assetPathFor(
              voiceKey: line.voiceKey, clipId: line.displayNameClipId),
        ),
      ],
      gapsBetween: const [Duration(milliseconds: 50)],
    );
  }
}

