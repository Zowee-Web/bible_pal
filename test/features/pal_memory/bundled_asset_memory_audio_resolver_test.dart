import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/pal_memory/bundled_asset_memory_audio_resolver.dart';
import 'package:bible_pal/features/pal_memory/memory_audio_paths.dart';
import 'package:bible_pal/features/pal_memory/memory_audio_plan.dart';
import 'package:bible_pal/features/pal_memory/memory_audio_policy.dart';
import 'package:bible_pal/features/pal_memory/pal_memory_line.dart';
import 'package:bible_pal/features/pal_memory/resolved_memory_line.dart';

/// Tests for [BundledAssetMemoryAudioResolver] — Slice 2c.3 of the PAL
/// Memory Doctrine (docs/PAL_MEMORY_DOCTRINE.md).
///
/// The resolver consults the bundle path set captured at construction
/// time. Tests construct directly with a synthetic set (skipping the
/// rootBundle factory) so they run in plain `flutter test` without any
/// Flutter widget test setup.
void main() {
  ResolvedMemoryLine buildLine({
    String voiceKey = 'VOICE_HOPE',
    String carrierClipId = 'carrier_yesterday_sat_with',
    String displayNameClipId = 'name_daniel',
  }) {
    return ResolvedMemoryLine(
      voiceKey: voiceKey,
      carrierClipId: carrierClipId,
      carrierText: 'Yesterday you sat with',
      displayName: 'Daniel',
      displayNameClipId: displayNameClipId,
      band: RecencyBand.yesterday,
      sourceStoryId: '1100',
    );
  }

  String carrierPath(String voice, String clip) =>
      PalMemoryAudioPaths.assetPathFor(voiceKey: voice, clipId: clip);

  group('happy path — both clips bundled', () {
    test('returns a structurally-valid 2-clip plan', () async {
      final resolver = BundledAssetMemoryAudioResolver({
        carrierPath('VOICE_HOPE', 'carrier_yesterday_sat_with'),
        carrierPath('VOICE_HOPE', 'name_daniel'),
      });
      final plan = await resolver.resolve(buildLine());
      expect(plan, isNotNull);
      plan!.validateStructure();
      expect(plan.voiceKey, 'VOICE_HOPE');
      expect(plan.clips.map((c) => c.clipId).toList(),
          ['carrier_yesterday_sat_with', 'name_daniel']);
      expect(plan.clips.map((c) => c.kind).toList(),
          [ClipKind.carrier, ClipKind.name]);
    });

    test('uses the policy gap between carrier and name', () async {
      final resolver = BundledAssetMemoryAudioResolver({
        carrierPath('VOICE_HOPE', 'carrier_yesterday_sat_with'),
        carrierPath('VOICE_HOPE', 'name_daniel'),
      });
      final plan = await resolver.resolve(buildLine());
      expect(plan!.gapsBetween, [PalMemoryAudioPolicy.carrierToNameGap]);
    });

    test('asset paths match the path-policy convention', () async {
      final resolver = BundledAssetMemoryAudioResolver({
        carrierPath('VOICE_HOPE', 'carrier_yesterday_sat_with'),
        carrierPath('VOICE_HOPE', 'name_daniel'),
      });
      final plan = await resolver.resolve(buildLine());
      expect(plan!.clips[0].assetPath,
          'assets/pal/audio/VOICE_HOPE/memory/carrier_yesterday_sat_with.mp3');
      expect(plan.clips[1].assetPath,
          'assets/pal/audio/VOICE_HOPE/memory/name_daniel.mp3');
    });
  });

  group('silence floor — null on missing clips', () {
    test('null when carrier clip is not bundled', () async {
      final resolver = BundledAssetMemoryAudioResolver({
        // Name present, carrier missing.
        carrierPath('VOICE_HOPE', 'name_daniel'),
      });
      expect(await resolver.resolve(buildLine()), isNull);
    });

    test('null when name clip is not bundled', () async {
      final resolver = BundledAssetMemoryAudioResolver({
        carrierPath('VOICE_HOPE', 'carrier_yesterday_sat_with'),
      });
      expect(await resolver.resolve(buildLine()), isNull);
    });

    test('null when neither clip is bundled', () async {
      final resolver = BundledAssetMemoryAudioResolver(const {});
      expect(await resolver.resolve(buildLine()), isNull);
    });

    test('null on empty bundle even when the line is well-formed', () async {
      final resolver = BundledAssetMemoryAudioResolver(const {});
      final plan = await resolver.resolve(buildLine());
      expect(plan, isNull,
          reason:
              'Empty bundle == no memory audio has shipped yet. Doctrine: '
              'silence is the correct response, not a runtime fallback.');
    });
  });

  group('per-voice isolation (Slice 2c voice multiplicity = 1)', () {
    test('asking for VOICE_SHEPHERD when only VOICE_HOPE is bundled → null',
        () async {
      final resolver = BundledAssetMemoryAudioResolver({
        carrierPath('VOICE_HOPE', 'carrier_yesterday_sat_with'),
        carrierPath('VOICE_HOPE', 'name_daniel'),
      });
      final plan = await resolver.resolve(buildLine(voiceKey: 'VOICE_SHEPHERD'));
      expect(plan, isNull,
          reason:
              'The active voice has no rendered memory clips. The doctrine '
              'forbids cross-voice fallback — silence is correct.');
    });

    test('multi-voice bundle resolves the requested voice cleanly', () async {
      final resolver = BundledAssetMemoryAudioResolver({
        carrierPath('VOICE_HOPE', 'carrier_yesterday_sat_with'),
        carrierPath('VOICE_HOPE', 'name_daniel'),
        carrierPath('VOICE_SHEPHERD', 'carrier_yesterday_sat_with'),
        carrierPath('VOICE_SHEPHERD', 'name_daniel'),
      });
      final hopePlan = await resolver.resolve(buildLine(voiceKey: 'VOICE_HOPE'));
      final shepherdPlan =
          await resolver.resolve(buildLine(voiceKey: 'VOICE_SHEPHERD'));
      expect(hopePlan, isNotNull);
      expect(shepherdPlan, isNotNull);
      expect(hopePlan!.voiceKey, 'VOICE_HOPE');
      expect(shepherdPlan!.voiceKey, 'VOICE_SHEPHERD');
      expect(hopePlan.clips[0].assetPath, contains('VOICE_HOPE'));
      expect(shepherdPlan.clips[0].assetPath, contains('VOICE_SHEPHERD'));
    });
  });
}
