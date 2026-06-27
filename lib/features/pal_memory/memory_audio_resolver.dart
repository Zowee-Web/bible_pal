import 'memory_audio_plan.dart';
import 'resolved_memory_line.dart';

/// Locates the audio clips required to play a [ResolvedMemoryLine] and
/// returns a [MemoryAudioPlan] — or null if any required clip is missing.
///
/// PAL Memory Doctrine, Slice 2c.2 (see docs/PAL_MEMORY_DOCTRINE.md):
/// pure interface, no concrete implementation in 2c.2. Real
/// implementations (bundled-asset-aware, R2-aware) ship in later slices.
/// The contract is the load-bearing piece: **missing clip means silence,
/// not fallback generation.** Runtime TTS substitution is forbidden by
/// the doctrine.
///
/// Implementations:
/// - Slice 2c.3 will add a bundled-asset implementation that consults
///   Flutter's `AssetManifest`.
/// - A future slice may add an R2-aware implementation for memory clips
///   that ship via the cloud catalog rather than the local bundle.
///
/// In tests, a small in-memory stub (see
/// `test/features/pal_memory/memory_audio_resolver_test.dart`) makes
/// it easy to assert "given these available clip ids, does the resolver
/// return the expected plan?" without touching any real asset.
abstract class MemoryAudioResolver {
  /// Returns the audio plan for [line], or null when any required clip
  /// is missing. Implementations MUST NOT fall back to runtime TTS,
  /// alternative voices, or partial plans — silence is the doctrine's
  /// preferred floor.
  Future<MemoryAudioPlan?> resolve(ResolvedMemoryLine line);
}
