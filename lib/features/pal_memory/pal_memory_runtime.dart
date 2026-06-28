import 'package:flutter/foundation.dart' show immutable;

import '../../models/user_preferences.dart';
import 'memory_audio_plan.dart';
import 'memory_audio_resolver.dart';
import 'memory_line_resolver.dart';
import 'pal_memory_display_name_registry.dart';
import 'pal_memory_engine.dart';
import 'pal_session_store.dart';

/// Outcome of a single PAL Memory cascade attempt. Caller-visible so
/// tests can assert exact branches and integration sites can wire
/// follow-up behavior (e.g. settings dialogs on `consentBlocked`).
enum MemoryLineOutcome {
  /// Voice consent gate stopped the cascade — user has not granted
  /// PAL voice permission or PAL voice is the master-switch-off state.
  consentBlocked,

  /// [PalMemoryEngine.nextLine] returned null (min-completions,
  /// recency, or cooldown gates closed).
  engineSilent,

  /// Engine fired but the editorial display-name registry has no entry
  /// for the source story — the doctrine's opt-out path.
  noDisplayName,

  /// Engine and editorial resolution both succeeded but the audio
  /// resolver could not produce a plan (carrier or name clip missing
  /// from the bundle for this voice).
  missingClip,

  /// Plan produced but [MemoryPlanPlayer] returned false (audio
  /// playback failed mid-flight).
  playbackFailed,

  /// Any unhandled exception in the cascade was swallowed; the
  /// integration site continues silently.
  exception,

  /// PAL spoke; cooldown advanced.
  played,
}

@immutable
class MemoryLineResult {
  final MemoryLineOutcome outcome;
  final String? skippedReason;
  const MemoryLineResult(this.outcome, {this.skippedReason});
}

/// Plays a [MemoryAudioPlan] and returns true on successful playback.
/// Returning false MUST keep the cooldown un-advanced.
typedef MemoryPlanPlayer = Future<bool> Function(MemoryAudioPlan plan);

/// Structured-event sink mirroring [AppLogger.logEvent]'s signature.
/// Optional so unit tests can omit it; the integration site passes the
/// real `logEvent` function.
typedef EventLogger = void Function(String event, Map<String, Object?> props);

/// Run the PAL Memory cascade end-to-end and play the line if the
/// engine + editorial + audio gates all clear. Pure-ish: every IO
/// dependency is injected so unit tests can exercise every branch
/// without a Riverpod ProviderContainer or a widget harness.
///
/// PAL Memory Doctrine, Slice 2d (see docs/PAL_MEMORY_DOCTRINE.md):
/// the cascade is consent → engine → editorial → audio → play →
/// record. Any null/failure short-circuits to silence; the doctrine's
/// silence floor must NEVER fall back to a different voice, an
/// alternate phrasing, or runtime TTS.
///
/// `lastMemoryLineSpokenAt` is recorded ONLY after [playPlan] returns
/// true. A render gap, a missing clip, or a playback failure does NOT
/// burn the user's next 3-day cooldown window — the engine will
/// re-attempt on the next selection.
///
/// Any exception thrown inside the cascade is caught and reported as
/// [MemoryLineOutcome.exception]; the integration site can safely
/// `await` this without try/catch and proceed to story selection.
Future<MemoryLineResult> fireMemoryLine({
  required UserPreferences? preferences,
  required PalSessionStore sessionStore,
  required PalMemoryDisplayNameRegistry displayNameRegistry,
  required MemoryAudioResolver audioResolver,
  required MemoryPlanPlayer playPlan,
  required DateTime now,
  EventLogger? logger,
}) async {
  void log(String event, Map<String, Object?> props) {
    final l = logger;
    if (l != null) l(event, props);
  }

  try {
    // Gate 0 — voice consent. Mirrors the legacy cold-open pattern in
    // main_menu_screen.dart (palVoiceEnabled must be true; null on
    // palGreetingsEnabled is treated as allowed for parity with the
    // existing greeting). Skip silently — never prompt from here;
    // memory lines are background.
    if (preferences == null) {
      log('pal_memory_line_skipped', const {'reason': 'no_preferences'});
      return const MemoryLineResult(
        MemoryLineOutcome.consentBlocked,
        skippedReason: 'no_preferences',
      );
    }
    if (preferences.palVoiceEnabled != true) {
      log('pal_memory_line_skipped', const {'reason': 'pal_voice_disabled'});
      return const MemoryLineResult(
        MemoryLineOutcome.consentBlocked,
        skippedReason: 'pal_voice_disabled',
      );
    }
    if (preferences.palGreetingsEnabled == false) {
      log('pal_memory_line_skipped',
          const {'reason': 'pal_greetings_disabled'});
      return const MemoryLineResult(
        MemoryLineOutcome.consentBlocked,
        skippedReason: 'pal_greetings_disabled',
      );
    }
    final voiceKey = preferences.palVoiceKey;

    // Gate 1 — engine (pure rules over sessions + cooldown).
    const engine = PalMemoryEngine();
    final sessions = await sessionStore.all();
    final lastSpokenAt = await sessionStore.getLastMemoryLineSpokenAt();
    final line = engine.nextLine(
      sessions: sessions,
      lastSpokenAt: lastSpokenAt,
      now: now,
    );
    if (line == null) {
      log('pal_memory_line_skipped', const {'reason': 'engine_silent'});
      return const MemoryLineResult(
        MemoryLineOutcome.engineSilent,
        skippedReason: 'engine_silent',
      );
    }

    // Gate 2 — editorial display-name resolution.
    final resolved = MemoryLineResolver(displayNameRegistry)
        .resolve(line: line, activeVoiceKey: voiceKey);
    if (resolved == null) {
      log('pal_memory_line_skipped', {
        'reason': 'no_display_name',
        'source_story_id': line.sourceStoryId,
        'source_bible_story_key': line.sourceBibleStoryKey,
      });
      return const MemoryLineResult(
        MemoryLineOutcome.noDisplayName,
        skippedReason: 'no_display_name',
      );
    }

    // Gate 3 — audio plan (bundled-asset existence check).
    final plan = await audioResolver.resolve(resolved);
    if (plan == null) {
      log('pal_memory_line_skipped', {
        'reason': 'missing_clip',
        'voice_key': resolved.voiceKey,
        'carrier_clip_id': resolved.carrierClipId,
        'display_name_clip_id': resolved.displayNameClipId,
      });
      return const MemoryLineResult(
        MemoryLineOutcome.missingClip,
        skippedReason: 'missing_clip',
      );
    }

    // Fire telemetry BEFORE playback so a crash mid-playback still
    // leaves a 'fired' breadcrumb in the log for diagnostics.
    log('pal_memory_line_fired', {
      'voice_key': resolved.voiceKey,
      'band': resolved.band.name,
      'source_story_id': resolved.sourceStoryId,
    });

    final played = await playPlan(plan);
    if (!played) {
      log('pal_memory_line_skipped', {
        'reason': 'playback_failed',
        'voice_key': resolved.voiceKey,
      });
      return const MemoryLineResult(
        MemoryLineOutcome.playbackFailed,
        skippedReason: 'playback_failed',
      );
    }

    // Record AFTER successful playback. The cooldown only advances
    // when PAL actually spoke; a render gap or playback failure does
    // not burn the user's next 3-day window.
    await sessionStore.recordMemoryLineSpoken(at: now);
    log('pal_memory_line_played', {
      'voice_key': resolved.voiceKey,
      'band': resolved.band.name,
      'source_story_id': resolved.sourceStoryId,
    });
    return const MemoryLineResult(MemoryLineOutcome.played);
  } catch (e) {
    // Safe-fail: a memory-beat failure must NEVER block story
    // selection. The integration site awaits this without try/catch.
    log('pal_memory_line_skipped', {
      'reason': 'exception',
      'error': e.toString(),
    });
    return MemoryLineResult(
      MemoryLineOutcome.exception,
      skippedReason: 'exception: $e',
    );
  }
}
