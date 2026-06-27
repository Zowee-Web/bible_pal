import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/pal_memory/memory_audio_paths.dart';
import 'package:bible_pal/features/pal_memory/memory_audio_plan.dart';
import 'package:bible_pal/features/pal_memory/memory_audio_resolver.dart';
import 'package:bible_pal/features/pal_memory/pal_memory_line.dart';
import 'package:bible_pal/features/pal_memory/resolved_memory_line.dart';

/// Tests for the [MemoryAudioResolver] interface and the path policy
/// it composes plans against — Slice 2c.2 of the PAL Memory Doctrine
/// (docs/PAL_MEMORY_DOCTRINE.md).
///
/// The abstract resolver has no concrete implementation in 2c.2. These
/// tests exercise the contract via a small in-test stub that succeeds
/// only when all required clipIds appear in a provided allowlist —
/// the same shape the Slice 2c.3 inventory-aware implementation will
/// take, just with the allowlist swapped for a real asset manifest.
///
/// The doctrine's load-bearing rule lives here: **missing clip means
/// silence (null), not fallback generation.**
void main() {
  ResolvedMemoryLine buildResolved({
    String voiceKey = 'VOICE_HOPE',
    String carrierClipId = 'carrier_yesterday_sat_with',
    String carrierText = 'Yesterday you sat with',
    String displayName = 'Daniel',
    String displayNameClipId = 'name_daniel',
    RecencyBand band = RecencyBand.yesterday,
    String sourceStoryId = '1100',
  }) {
    return ResolvedMemoryLine(
      voiceKey: voiceKey,
      carrierClipId: carrierClipId,
      carrierText: carrierText,
      displayName: displayName,
      displayNameClipId: displayNameClipId,
      band: band,
      sourceStoryId: sourceStoryId,
    );
  }

  group('path policy ([PalMemoryAudioPaths])', () {
    test('composes the expected bundled-asset path', () {
      final p = PalMemoryAudioPaths.assetPathFor(
        voiceKey: 'VOICE_HOPE',
        clipId: 'name_daniel',
      );
      expect(p, 'assets/pal/audio/VOICE_HOPE/memory/name_daniel.mp3');
    });

    test('mirrors the existing PAL audio directory convention', () {
      // Sanity check that we land under assets/pal/audio/<VOICE>/ — the
      // same root the canonical PAL greeting and reflection clips live
      // under. The memory/ subdirectory keeps memory clips from
      // colliding with the existing flat layout.
      final p = PalMemoryAudioPaths.assetPathFor(
        voiceKey: 'VOICE_STILLWATER',
        clipId: 'carrier_few_days_ago_sat_with',
      );
      expect(p, startsWith('assets/pal/audio/VOICE_STILLWATER/'));
      expect(p, contains('/memory/'));
      expect(p, endsWith('.mp3'));
    });
  });

  group('stub MemoryAudioResolver — contract verification', () {
    test('returns a 2-clip plan when both required clips are available',
        () async {
      final resolver = _AllowlistMemoryAudioResolver({
        'carrier_yesterday_sat_with',
        'name_daniel',
      });
      final plan = await resolver.resolve(buildResolved());
      expect(plan, isNotNull);
      expect(plan!.voiceKey, 'VOICE_HOPE');
      expect(plan.clips, hasLength(2));
      expect(plan.gapsBetween, hasLength(1));
      // gap structure invariant: length always = clips.length - 1
      plan.validateStructure();
    });

    test('clip order is carrier-then-name', () async {
      final resolver = _AllowlistMemoryAudioResolver({
        'carrier_yesterday_sat_with',
        'name_daniel',
      });
      final plan = await resolver.resolve(buildResolved());
      expect(plan!.clips[0].kind, ClipKind.carrier);
      expect(plan.clips[0].clipId, 'carrier_yesterday_sat_with');
      expect(plan.clips[1].kind, ClipKind.name);
      expect(plan.clips[1].clipId, 'name_daniel');
    });

    test('clip asset paths come from PalMemoryAudioPaths', () async {
      final resolver = _AllowlistMemoryAudioResolver({
        'carrier_yesterday_sat_with',
        'name_daniel',
      });
      final plan = await resolver.resolve(buildResolved());
      expect(plan!.clips[0].assetPath,
          'assets/pal/audio/VOICE_HOPE/memory/carrier_yesterday_sat_with.mp3');
      expect(plan.clips[1].assetPath,
          'assets/pal/audio/VOICE_HOPE/memory/name_daniel.mp3');
    });
  });

  group('stub MemoryAudioResolver — silence-on-missing-clip (doctrine)', () {
    test('returns null when the carrier clip is missing', () async {
      final resolver = _AllowlistMemoryAudioResolver({
        // name available, carrier NOT
        'name_daniel',
      });
      final plan = await resolver.resolve(buildResolved());
      expect(plan, isNull);
    });

    test('returns null when the name clip is missing', () async {
      final resolver = _AllowlistMemoryAudioResolver({
        // carrier available, name NOT
        'carrier_yesterday_sat_with',
      });
      final plan = await resolver.resolve(buildResolved());
      expect(plan, isNull);
    });

    test('returns null when both clips are missing', () async {
      final resolver = _AllowlistMemoryAudioResolver(const {});
      final plan = await resolver.resolve(buildResolved());
      expect(plan, isNull);
    });

    test('availability is checked per (voice × clipId) pair', () async {
      // A resolver that has the clipIds but only knows about Hope's
      // voice should NOT serve a Shepherd-voice line. (Implementations
      // can enforce this via the path computation — different voice =
      // different asset path = different lookup.) We model that here by
      // having the allowlist key on the full asset path instead of just
      // the clipId.
      final resolver = _VoiceAwareAllowlistResolver({
        'assets/pal/audio/VOICE_HOPE/memory/carrier_yesterday_sat_with.mp3',
        'assets/pal/audio/VOICE_HOPE/memory/name_daniel.mp3',
      });
      expect(
        await resolver.resolve(buildResolved(voiceKey: 'VOICE_HOPE')),
        isNotNull,
      );
      expect(
        await resolver.resolve(buildResolved(voiceKey: 'VOICE_SHEPHERD')),
        isNull,
        reason:
            'Slice 2c voice-multiplicity = 1. If the active voice has no '
            'rendered memory clips, the resolver must stay silent — '
            'never fall back to another voice.',
      );
    });
  });
}

/// In-test stub. Treats an opaque set of clipIds as "available" and
/// emits a plan iff every required clipId is in the set. Mirrors the
/// shape of the eventual bundled-asset and R2 implementations: ask
/// the allowlist a question, return null on any missing.
class _AllowlistMemoryAudioResolver implements MemoryAudioResolver {
  final Set<String> availableClipIds;

  _AllowlistMemoryAudioResolver(this.availableClipIds);

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
      gapsBetween: const [Duration(milliseconds: 50)],
    );
  }
}

/// Voice-aware variant of [_AllowlistMemoryAudioResolver]. The allowlist
/// is keyed by full asset path (which includes the voice), so a missing
/// voice = silence — matching the doctrine.
class _VoiceAwareAllowlistResolver implements MemoryAudioResolver {
  final Set<String> availablePaths;

  _VoiceAwareAllowlistResolver(this.availablePaths);

  @override
  Future<MemoryAudioPlan?> resolve(ResolvedMemoryLine line) async {
    final carrierPath = PalMemoryAudioPaths.assetPathFor(
        voiceKey: line.voiceKey, clipId: line.carrierClipId);
    final namePath = PalMemoryAudioPaths.assetPathFor(
        voiceKey: line.voiceKey, clipId: line.displayNameClipId);
    if (!availablePaths.contains(carrierPath)) return null;
    if (!availablePaths.contains(namePath)) return null;
    return MemoryAudioPlan(
      voiceKey: line.voiceKey,
      clips: [
        MemoryAudioClipRef(
          clipId: line.carrierClipId,
          kind: ClipKind.carrier,
          assetPath: carrierPath,
        ),
        MemoryAudioClipRef(
          clipId: line.displayNameClipId,
          kind: ClipKind.name,
          assetPath: namePath,
        ),
      ],
      gapsBetween: const [Duration(milliseconds: 50)],
    );
  }
}
