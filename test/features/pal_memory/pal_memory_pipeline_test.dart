import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/pal_memory/memory_audio_paths.dart';
import 'package:bible_pal/features/pal_memory/memory_audio_plan.dart';
import 'package:bible_pal/features/pal_memory/memory_audio_resolver.dart';
import 'package:bible_pal/features/pal_memory/memory_line_resolver.dart';
import 'package:bible_pal/features/pal_memory/pal_memory_display_name_registry.dart';
import 'package:bible_pal/features/pal_memory/pal_memory_engine.dart';
import 'package:bible_pal/features/pal_memory/pal_memory_line.dart';
import 'package:bible_pal/features/pal_memory/resolved_memory_line.dart';
import 'package:bible_pal/features/pal_memory/pal_session.dart';

/// End-to-end text-only pipeline test — Slice 2c.2 of the PAL Memory
/// Doctrine (docs/PAL_MEMORY_DOCTRINE.md).
///
/// This is the proof that the architecture works *without rendering any
/// audio*. The test composes:
///   PalSession[] → PalMemoryEngine → PalMemoryLine
///                → MemoryLineResolver → ResolvedMemoryLine
///                → MemoryAudioResolver → MemoryAudioPlan
/// and asserts the plan that comes out is exactly what we expect for a
/// given (synthetic) listening history. If this test passes for a given
/// session log + registry + voice, the eventual audio render is a pure
/// production task: render the carrier and name clips per voice, swap
/// the in-memory resolver for a bundle-aware one, ship.
void main() {
  // "Now" is mid-afternoon to avoid midnight rollover edge cases.
  final now = DateTime.utc(2026, 6, 18, 15, 0);

  late PalMemoryDisplayNameRegistry registry;
  setUpAll(() {
    final json =
        File('assets/pal/memory/display_name_registry.json').readAsStringSync();
    registry = PalMemoryDisplayNameRegistry.fromJson(json);
  });

  PalSession session({
    required String storyId,
    String? bibleStoryKey,
    required DateTime completedAt,
  }) =>
      PalSession(
        storyId: storyId,
        completedAt: completedAt,
        bibleStoryKey: bibleStoryKey,
        languageStyle: 'WEB',
      );

  group('Daniel-in-the-lions-den happy path', () {
    test('session log of Daniel → expected plan for VOICE_HOPE', () async {
      // Three completions; the newest is Daniel from yesterday. Pads
      // satisfy the min-completions gate without competing for "most recent."
      final sessions = [
        session(
            storyId: 'pad_old',
            completedAt: now.subtract(const Duration(days: 9))),
        session(
            storyId: 'pad_older',
            completedAt: now.subtract(const Duration(days: 8))),
        session(
          storyId: '1100',
          bibleStoryKey: 'daniel_in_the_lions_den',
          completedAt: now.subtract(const Duration(days: 1)),
        ),
      ];

      // 1) Engine
      const engine = PalMemoryEngine();
      final line = engine.nextLine(
          sessions: sessions, lastSpokenAt: null, now: now);
      expect(line, isNotNull);
      expect(line!.band, RecencyBand.yesterday);
      expect(line.sourceBibleStoryKey, 'daniel_in_the_lions_den');
      expect(line.carrierClipId, startsWith('carrier_yesterday_'));
      expect(line.template, contains('{storyName}'));

      // 2) Line resolver — uses the editorial registry to fill the name.
      final lineResolver = MemoryLineResolver(registry);
      final resolved = lineResolver.resolve(
          line: line, activeVoiceKey: 'VOICE_HOPE');
      expect(resolved, isNotNull);
      expect(resolved!.voiceKey, 'VOICE_HOPE');
      expect(resolved.displayName, 'Daniel');
      expect(resolved.displayNameClipId, 'name_daniel');
      expect(resolved.fullText, endsWith(' Daniel.'));
      expect(resolved.fullText, startsWith('Yesterday you '));

      // 3) Audio resolver — stub that has both clips available → plan.
      final audioResolver = _PerfectAllowlistResolver({
        resolved.carrierClipId,
        resolved.displayNameClipId,
      });
      final plan = await audioResolver.resolve(resolved);
      expect(plan, isNotNull);
      plan!.validateStructure();
      expect(plan.voiceKey, 'VOICE_HOPE');
      expect(plan.clips, hasLength(2));
      expect(plan.clips[0].clipId, resolved.carrierClipId);
      expect(plan.clips[0].kind, ClipKind.carrier);
      expect(plan.clips[0].assetPath,
          'assets/pal/audio/VOICE_HOPE/memory/${resolved.carrierClipId}.mp3');
      expect(plan.clips[1].clipId, 'name_daniel');
      expect(plan.clips[1].kind, ClipKind.name);
      expect(plan.clips[1].assetPath,
          'assets/pal/audio/VOICE_HOPE/memory/name_daniel.mp3');
      expect(plan.gapsBetween, [const Duration(milliseconds: 250)]);
    });

    test('same session repeated → same plan (full pipeline determinism)',
        () async {
      // The engine is deterministic per source session; the resolver
      // and audio resolver are pure functions of their inputs. The end
      // result must be byte-identical on repeat queries — this is what
      // lets pre-rendered audio + the silence floor compose safely.
      final sessions = [
        session(
            storyId: 'pad_a',
            completedAt: now.subtract(const Duration(days: 8))),
        session(
            storyId: 'pad_b',
            completedAt: now.subtract(const Duration(days: 9))),
        session(
          storyId: '1100',
          bibleStoryKey: 'daniel_in_the_lions_den',
          completedAt: now.subtract(const Duration(days: 1)),
        ),
      ];
      const engine = PalMemoryEngine();
      final lineResolver = MemoryLineResolver(registry);

      Future<MemoryAudioPlan?> runPipeline() async {
        final line = engine.nextLine(
            sessions: sessions, lastSpokenAt: null, now: now);
        final resolved = lineResolver.resolve(
            line: line!, activeVoiceKey: 'VOICE_HOPE');
        final audioResolver = _PerfectAllowlistResolver({
          resolved!.carrierClipId,
          resolved.displayNameClipId,
        });
        return audioResolver.resolve(resolved);
      }

      final a = await runPipeline();
      final b = await runPipeline();
      expect(a!.voiceKey, b!.voiceKey);
      expect(a.clips.map((c) => c.clipId).toList(),
          b.clips.map((c) => c.clipId).toList());
      expect(a.clips.map((c) => c.assetPath).toList(),
          b.clips.map((c) => c.assetPath).toList());
      expect(a.gapsBetween, b.gapsBetween);
    });
  });

  group('silence floor — full-pipeline failures land as null', () {
    test('engine returns null when min-completions gate fails → no plan',
        () async {
      // Only 1 session; engine returns null; everything downstream is
      // never even invoked. The test is to assert the pipeline returns
      // null cleanly at the first gate.
      final sessions = [
        session(
          storyId: '1100',
          bibleStoryKey: 'daniel_in_the_lions_den',
          completedAt: now.subtract(const Duration(days: 1)),
        ),
      ];
      const engine = PalMemoryEngine();
      final line = engine.nextLine(
          sessions: sessions, lastSpokenAt: null, now: now);
      expect(line, isNull);
    });

    test('display-name opt-out → resolved line is null → no plan', () async {
      // 3 completions, newest is an unregistered story (no editorial
      // display name). Engine returns a line, line resolver returns null,
      // audio resolver is never asked. The doctrine's opt-out silence
      // floor catches this without any clip lookup.
      final sessions = [
        session(
            storyId: 'pad_a',
            completedAt: now.subtract(const Duration(days: 8))),
        session(
            storyId: 'pad_b',
            completedAt: now.subtract(const Duration(days: 9))),
        session(
          storyId: '9999',
          bibleStoryKey: 'a_story_with_no_editorial_display_name',
          completedAt: now.subtract(const Duration(days: 1)),
        ),
      ];
      const engine = PalMemoryEngine();
      final line = engine.nextLine(
          sessions: sessions, lastSpokenAt: null, now: now);
      expect(line, isNotNull);

      final lineResolver = MemoryLineResolver(registry);
      final resolved = lineResolver.resolve(
          line: line!, activeVoiceKey: 'VOICE_HOPE');
      expect(resolved, isNull);
    });

    test('missing carrier clip → audio resolver returns null', () async {
      final sessions = [
        session(
            storyId: 'pad_a',
            completedAt: now.subtract(const Duration(days: 8))),
        session(
            storyId: 'pad_b',
            completedAt: now.subtract(const Duration(days: 9))),
        session(
          storyId: '1100',
          bibleStoryKey: 'daniel_in_the_lions_den',
          completedAt: now.subtract(const Duration(days: 1)),
        ),
      ];
      const engine = PalMemoryEngine();
      final line = engine.nextLine(
          sessions: sessions, lastSpokenAt: null, now: now)!;
      final resolved = MemoryLineResolver(registry).resolve(
          line: line, activeVoiceKey: 'VOICE_HOPE')!;

      // Audio resolver has the name but NOT the carrier.
      final audioResolver = _PerfectAllowlistResolver({
        resolved.displayNameClipId,
      });
      final plan = await audioResolver.resolve(resolved);
      expect(plan, isNull,
          reason:
              'Doctrine: missing clip means silence, not fallback generation. '
              'If the carrier render is missing, the entire plan must be null.');
    });
  });
}

/// Test stub — emits a plan when every required clipId is in
/// [availableClipIds]; null otherwise.
class _PerfectAllowlistResolver implements MemoryAudioResolver {
  final Set<String> availableClipIds;
  _PerfectAllowlistResolver(this.availableClipIds);

  @override
  Future<MemoryAudioPlan?> resolve(ResolvedMemoryLine line) async {
    if (!availableClipIds.contains(line.carrierClipId)) return null;
    if (!availableClipIds.contains(line.displayNameClipId)) return null;
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
      gapsBetween: const [Duration(milliseconds: 250)],
    );
  }
}
