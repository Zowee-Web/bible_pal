import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import 'memory_audio_paths.dart';
import 'memory_audio_plan.dart';
import 'memory_audio_policy.dart';
import 'memory_audio_resolver.dart';
import 'resolved_memory_line.dart';

/// Bundled-asset [MemoryAudioResolver] — consults Flutter's
/// [AssetManifest] to verify every required clip is present in the app
/// bundle. Returns null when any required clip is missing.
///
/// PAL Memory Doctrine, Slice 2c.3 (see docs/PAL_MEMORY_DOCTRINE.md):
/// **missing clip means silence, not fallback generation.** This
/// implementation never substitutes another voice, never falls back to
/// runtime TTS, never emits a partial plan. The doctrine's silence
/// floor is the failure mode.
///
/// The set of bundled paths is captured at construction time so every
/// [resolve] call is a synchronous Set lookup. Production callers use
/// the [load] factory to populate the set from the live asset bundle;
/// tests construct directly with a synthetic path set.
///
/// Mirrors the shape of `bundledAudioPathsProvider` in
/// `lib/providers/service_providers.dart` — same `AssetManifest` source,
/// scoped to PAL memory audio (`assets/pal/audio/*/memory/*.mp3`).
class BundledAssetMemoryAudioResolver implements MemoryAudioResolver {
  /// Full bundled-asset paths of every PAL memory audio clip that
  /// exists in the bundle at construction time.
  final Set<String> bundledPaths;

  const BundledAssetMemoryAudioResolver(this.bundledPaths);

  /// Production factory — loads [AssetManifest] from [rootBundle] and
  /// filters to PAL memory audio paths. Call once at app launch and
  /// hold the resulting instance for the lifetime of the session.
  static Future<BundledAssetMemoryAudioResolver> load() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    const prefix = 'assets/pal/audio/';
    const memoryFragment = '/memory/';
    final paths = manifest
        .listAssets()
        .where((p) =>
            p.startsWith(prefix) &&
            p.contains(memoryFragment) &&
            p.endsWith('.mp3'))
        .toSet();
    return BundledAssetMemoryAudioResolver(paths);
  }

  @override
  Future<MemoryAudioPlan?> resolve(ResolvedMemoryLine line) async {
    final carrierPath = PalMemoryAudioPaths.assetPathFor(
        voiceKey: line.voiceKey, clipId: line.carrierClipId);
    final namePath = PalMemoryAudioPaths.assetPathFor(
        voiceKey: line.voiceKey, clipId: line.displayNameClipId);

    if (!bundledPaths.contains(carrierPath)) return null;
    if (!bundledPaths.contains(namePath)) return null;

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
      gapsBetween: const [PalMemoryAudioPolicy.carrierToNameGap],
    );
  }
}
