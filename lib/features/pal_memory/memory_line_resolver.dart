import 'pal_memory_display_name_registry.dart';
import 'pal_memory_line.dart';
import 'resolved_memory_line.dart';

/// Combines a [PalMemoryLine] from [PalMemoryEngine] with the active
/// PAL voice and the editorial display-name registry to produce a
/// [ResolvedMemoryLine].
///
/// PAL Memory Doctrine, Slice 2c.2 (see docs/PAL_MEMORY_DOCTRINE.md):
/// pure function over its inputs. No IO, no asset bundle access — that
/// belongs to [MemoryAudioResolver]. This resolver is responsible only
/// for the editorial layer: looking up the spoken display name and
/// stitching the voice in.
///
/// Returns null in two opt-out cases:
/// - [PalMemoryLine.sourceBibleStoryKey] is null (the source story
///   has no canonical anchor — should not happen for Traditional
///   stories but is technically possible for legacy data).
/// - The display-name registry has no entry for that bibleStoryKey
///   (the editorial opt-out path — the doctrine's silence floor catches
///   this rather than falling back to a generic phrase).
class MemoryLineResolver {
  final PalMemoryDisplayNameRegistry _registry;

  const MemoryLineResolver(this._registry);

  /// Resolves [line] for [activeVoiceKey]. Returns null when the line
  /// cannot be editorially resolved — see class doc for the opt-out
  /// cases. The doctrine's silence floor expects null here to be a
  /// signal for "stay silent," NOT for the caller to invent a fallback.
  ResolvedMemoryLine? resolve({
    required PalMemoryLine line,
    required String activeVoiceKey,
  }) {
    final key = line.sourceBibleStoryKey;
    if (key == null) return null;

    final entry = _registry.lookup(key);
    if (entry == null) return null;

    return ResolvedMemoryLine(
      voiceKey: activeVoiceKey,
      carrierClipId: line.carrierClipId,
      displayNameClipId: entry.clipId,
      band: line.band,
      sourceStoryId: line.sourceStoryId,
      displayName: entry.displayName,
      carrierText: line.carrierText,
    );
  }
}
