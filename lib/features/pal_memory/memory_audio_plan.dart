import 'package:flutter/foundation.dart' show immutable;

/// What kind of clip occupies a slot in a [MemoryAudioPlan].
///
/// Slice 2c.2 produces only `carrier` + `name` plans. Future slices may
/// add `question` for a follow-up beat ("Want to hear what came after?").
enum ClipKind {
  /// The "Yesterday you sat with" fragment — spoken before the name.
  carrier,

  /// The display name itself — "Daniel", "the Good Samaritan".
  name,
}

/// One audio clip in a [MemoryAudioPlan] — clipId + kind + the expected
/// bundled-asset path. Implementations of [MemoryAudioResolver] can also
/// surface an R2 URL or a cache path here; the abstract field is just
/// "where would this clip come from."
@immutable
class MemoryAudioClipRef {
  final String clipId;
  final ClipKind kind;
  final String assetPath;

  const MemoryAudioClipRef({
    required this.clipId,
    required this.kind,
    required this.assetPath,
  });
}

/// Ordered description of what PAL would play to deliver one memory
/// line. Pure data — no audio dependencies, no just_audio types.
///
/// PAL Memory Doctrine, Slice 2c.2 (see docs/PAL_MEMORY_DOCTRINE.md):
/// the plan is the permanent return type of [MemoryAudioResolver].
/// A later slice's audio player materializes a plan into a
/// `ConcatenatingAudioSource` via just_audio; the resolver and the
/// inventory validator stay testable without any audio dependency.
///
/// A null plan (from [MemoryAudioResolver.resolve]) means PAL stays
/// silent — typically because a required clip is missing. The doctrine
/// forbids runtime fallback generation.
@immutable
class MemoryAudioPlan {
  /// PAL voice this plan was resolved for — `'VOICE_HOPE'` etc.
  final String voiceKey;

  /// Clip refs in playback order. Non-empty by construction.
  final List<MemoryAudioClipRef> clips;

  /// Programmatic silences between clips. `gapsBetween[i]` is the
  /// silence inserted between `clips[i]` and `clips[i+1]`. Length is
  /// always `clips.length - 1` — for the carrier+name case this is one
  /// gap (the natural breath between the carrier and the name).
  final List<Duration> gapsBetween;

  const MemoryAudioPlan({
    required this.voiceKey,
    required this.clips,
    required this.gapsBetween,
  });

  /// Sanity-check the plan structure. Throws [StateError] for shapes
  /// that violate the contract (empty clips, gap count mismatch).
  /// Consumers can call this in debug builds before materializing audio.
  void validateStructure() {
    if (clips.isEmpty) {
      throw StateError('MemoryAudioPlan must contain at least one clip');
    }
    if (gapsBetween.length != clips.length - 1) {
      throw StateError(
          'MemoryAudioPlan gapsBetween length must equal clips.length - 1 '
          '(got ${gapsBetween.length} gaps for ${clips.length} clips)');
    }
  }
}
