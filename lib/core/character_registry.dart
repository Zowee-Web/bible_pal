import 'dart:convert';

import 'package:flutter/services.dart';

/// A single entry in the PALs Paths character registry (SPEC 50.3 + 50.8).
///
/// Each entry carries a canonical disambiguated snake_case ID, a display
/// name for UI, a short descriptor, and a `reservedForJesusLife` flag used
/// only for the special `jesus` entry (Feature 50.8 "Jesus special case").
class CharacterEntry {
  final String id;
  final String displayName;
  final String descriptor;
  final bool reservedForJesusLife;

  const CharacterEntry({
    required this.id,
    required this.displayName,
    required this.descriptor,
    this.reservedForJesusLife = false,
  });

  factory CharacterEntry.fromJson(String id, Map<String, dynamic> json) {
    return CharacterEntry(
      id: id,
      displayName: json['displayName'] as String,
      descriptor: json['descriptor'] as String? ?? '',
      reservedForJesusLife:
          json['reserved_for_jesus_life'] as bool? ?? false,
    );
  }
}

/// Canonical PALs Paths character registry (SPEC 50.3 + 50.8 — LOCKED seed).
///
/// Loaded lazily from `assets/stories/character_registry.json`.
///
/// Rules enforced here:
/// - Characters have disambiguated snake_case IDs
///   (`john_baptist` vs `john_disciple`, three Marys, three Jameses, etc.)
/// - `jesus` is a reserved ID. It appears in this registry so `characterIds`
///   lookups resolve, but [charactersForPathList] excludes it — the
///   Characters path never surfaces Jesus. Jesus is surfaced exclusively
///   through `jesus_life` and `timeline.jesus_ministry`. (Feature 50.8)
class CharacterRegistry {
  CharacterRegistry._();

  static Map<String, CharacterEntry>? _byId;

  /// Load registry from bundled asset. Safe to call multiple times.
  static Future<void> ensureLoaded() async {
    if (_byId != null) return;
    final jsonStr = await rootBundle
        .loadString('assets/stories/character_registry.json');
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final characters = data['characters'] as Map<String, dynamic>;
    _byId = {
      for (final entry in characters.entries)
        entry.key: CharacterEntry.fromJson(
          entry.key,
          entry.value as Map<String, dynamic>,
        ),
    };
  }

  /// Reset internal state (for testing only).
  static void resetForTest() {
    _byId = null;
  }

  /// Look up a character entry by its canonical ID. Returns null if the
  /// registry is not loaded or the ID does not exist.
  static CharacterEntry? getById(String id) {
    return _byId?[id];
  }

  /// Display name for a given character ID. Returns the ID itself as a
  /// safe fallback when the registry is not loaded or the ID is unknown.
  static String getDisplayName(String id) {
    return _byId?[id]?.displayName ?? id;
  }

  /// True if the given ID is registered. Useful for validating
  /// `primaryCharacterId` values on Traditional stories.
  static bool isKnown(String id) {
    return _byId?.containsKey(id) ?? false;
  }

  /// True if the given ID is reserved for the special `jesus_life` path
  /// and must NEVER appear in the Characters path list. (Feature 50.8)
  static bool isReservedForJesusLife(String id) {
    return _byId?[id]?.reservedForJesusLife ?? false;
  }

  /// All registered character IDs (insertion order from the JSON asset).
  /// Includes `jesus`.
  static List<String> allIds() {
    return _byId?.keys.toList() ?? const <String>[];
  }

  /// Character IDs eligible for the Characters path list — all registered
  /// IDs EXCEPT those reserved for `jesus_life`. (SPEC Feature 50.8: "the
  /// Characters path enumerates every `primaryCharacterId` present in the
  /// manifest except `jesus`".)
  static List<String> charactersForPathList() {
    return _byId?.values
            .where((e) => !e.reservedForJesusLife)
            .map((e) => e.id)
            .toList() ??
        const <String>[];
  }
}
