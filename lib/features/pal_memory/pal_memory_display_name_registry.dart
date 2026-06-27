import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/services.dart' show rootBundle;

/// One editorial mapping from a Bible story to the phrase PAL speaks when
/// referring to that story in a memory line.
///
/// PAL Memory Doctrine, Slice 2c.1 (see docs/PAL_MEMORY_DOCTRINE.md):
/// the spoken form of a story is an editorial decision distinct from the
/// title, [bibleStoryKey], or character name. "Daniel" / "the Good
/// Samaritan" / "the lost son" — never inferred from titles.
@immutable
class DisplayNameEntry {
  /// Canonical Bible story identifier — matches an entry in
  /// `assets/stories/scripture_anchor_registry.json`.
  final String bibleStoryKey;

  /// The exact phrase PAL speaks — e.g. "Daniel", "the Good Samaritan".
  final String displayName;

  /// Audio-layer identifier. Eventually maps to one MP3 per PAL voice
  /// (e.g. `name_daniel.mp3`). Decoupled from [displayName] so a future
  /// re-wording can reuse an existing render. Must be filesystem-safe
  /// (lowercase, alphanumeric, underscores only).
  final String clipId;

  const DisplayNameEntry({
    required this.bibleStoryKey,
    required this.displayName,
    required this.clipId,
  });
}

/// Editorial registry of spoken memory names. Backs the `{storyName}`
/// placeholder in [PalMemoryEngine] templates (Slice 2a).
///
/// PAL Memory Doctrine, Slice 2c.1: opt-in. Stories without a registry
/// entry will not produce a memory line — the engine's silence floor
/// catches them. The doctrine prefers under-speaking to fabricating a
/// display name from a title.
///
/// Construction enforces structural invariants: unique [bibleStoryKey],
/// unique [clipId], non-empty fields, filesystem-safe [clipId]. Failures
/// throw [StateError] at construction time so registry edits can't ship
/// a broken artifact silently.
class PalMemoryDisplayNameRegistry {
  static const String assetPath =
      'assets/pal/memory/display_name_registry.json';
  static final RegExp _safeClipId = RegExp(r'^[a-z0-9_]+$');

  final int version;
  final Map<String, DisplayNameEntry> _byKey;

  PalMemoryDisplayNameRegistry._(this.version, this._byKey);

  /// Production loader — reads the bundled asset.
  static Future<PalMemoryDisplayNameRegistry> load() async {
    final json = await rootBundle.loadString(assetPath);
    return PalMemoryDisplayNameRegistry.fromJson(json);
  }

  /// Pure factory — used by tests and any caller that wants to inject a
  /// fixture instead of reading from the asset bundle.
  factory PalMemoryDisplayNameRegistry.fromJson(String jsonString) {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final version = data['version'] as int;
    final rawEntries = (data['entries'] as List<dynamic>);

    final byKey = <String, DisplayNameEntry>{};
    final seenClipIds = <String>{};
    for (final raw in rawEntries) {
      final e = raw as Map<String, dynamic>;
      final entry = DisplayNameEntry(
        bibleStoryKey: e['bibleStoryKey'] as String,
        displayName: e['displayName'] as String,
        clipId: e['clipId'] as String,
      );
      if (entry.bibleStoryKey.isEmpty) {
        throw StateError('Empty bibleStoryKey in PAL memory display name registry');
      }
      if (entry.displayName.isEmpty || entry.displayName.trim() != entry.displayName) {
        throw StateError(
            'Empty or whitespace-padded displayName in PAL memory display name registry '
            'for bibleStoryKey="${entry.bibleStoryKey}"');
      }
      if (entry.clipId.isEmpty || !_safeClipId.hasMatch(entry.clipId)) {
        throw StateError(
            'clipId "${entry.clipId}" must be lowercase alphanumeric + underscores only '
            '(bibleStoryKey="${entry.bibleStoryKey}")');
      }
      if (byKey.containsKey(entry.bibleStoryKey)) {
        throw StateError(
            'Duplicate bibleStoryKey "${entry.bibleStoryKey}" in PAL memory '
            'display name registry');
      }
      if (!seenClipIds.add(entry.clipId)) {
        throw StateError(
            'Duplicate clipId "${entry.clipId}" in PAL memory display name registry '
            '(bibleStoryKey="${entry.bibleStoryKey}")');
      }
      byKey[entry.bibleStoryKey] = entry;
    }

    return PalMemoryDisplayNameRegistry._(version, byKey);
  }

  /// Returns the registry entry for [bibleStoryKey], or null when no
  /// entry exists. Null is the opt-out path — callers should treat it as
  /// "this story has no editorial spoken name, fall through to silence."
  DisplayNameEntry? lookup(String bibleStoryKey) => _byKey[bibleStoryKey];

  /// Every registered entry. Used by the audio inventory validator
  /// (Slice 2c.3) to enumerate required clips at build time.
  Iterable<DisplayNameEntry> get all => _byKey.values;

  /// Number of registered stories.
  int get count => _byKey.length;
}
