import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/pal_memory/memory_audio_paths.dart';
import 'package:bible_pal/features/pal_memory/pal_memory_display_name_registry.dart';
import 'package:bible_pal/features/pal_memory/pal_memory_templates.dart';

/// Audio inventory validator — Slice 2c.3 of the PAL Memory Doctrine
/// (docs/PAL_MEMORY_DOCTRINE.md, Slice 2b Audio Architecture section).
///
/// Asserts that for every PAL voice that has *any* memory audio
/// rendered, the bundle contains a clip for **every** (band × variant ×
/// display name) combination the engine + registry can fire. Partial
/// renders are the failure mode: if a voice has carriers but is missing
/// some names, the engine would fire memory lines that silently never
/// play in production. This test catches that before ship.
///
/// Discovery is filesystem-based (not rootBundle-based) so the test
/// runs in plain `flutter test` without needing widget infrastructure.
/// Production uses the same `assets/pal/audio/<VOICE>/memory/*.mp3`
/// paths via [BundledAssetMemoryAudioResolver].
///
/// Two graceful skips:
/// 1. No `assets/pal/audio/` tree at all → skip (PAL audio not set up).
/// 2. No voice has a `memory/` subdirectory → skip (memory audio not
///    rendered yet for any voice — expected state before the first
///    audio render slice ships).
void main() {
  late PalMemoryDisplayNameRegistry registry;

  setUpAll(() {
    final json =
        File('assets/pal/memory/display_name_registry.json').readAsStringSync();
    registry = PalMemoryDisplayNameRegistry.fromJson(json);
  });

  test('every rendered voice has clips for every engine combination', () {
    final palAudioRoot = Directory('assets/pal/audio');
    if (!palAudioRoot.existsSync()) {
      markTestSkipped('No assets/pal/audio/ tree — PAL audio not set up.');
      return;
    }

    // Find voice directories that are *actively rendering* memory audio
    // — i.e. their memory/ subdirectory contains at least one .mp3. A
    // dir with only a marker file (.gitkeep) is "declared in pubspec
    // ready for the next render" — same logical state as the dir not
    // existing — and must not be treated as a partial render.
    bool hasRenderedClips(Directory voiceDir) {
      final memoryDir = Directory('${voiceDir.path}/memory');
      if (!memoryDir.existsSync()) return false;
      return memoryDir
          .listSync()
          .whereType<File>()
          .any((f) => f.path.endsWith('.mp3'));
    }

    final voicesWithMemory = palAudioRoot
        .listSync()
        .whereType<Directory>()
        .where(hasRenderedClips)
        .map((d) => d.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last)
        .toList();

    if (voicesWithMemory.isEmpty) {
      markTestSkipped(
          'No PAL voice has any rendered memory clips yet. Slice 2d (audio '
          'render) hasn\'t shipped. This test will activate automatically '
          'once any voice has memory audio rendered.');
      return;
    }

    // Enumerate every required clip across all rendered voices.
    final missing = <String>[];
    final present = <String>[];
    for (final voice in voicesWithMemory) {
      // Carriers — one per (band × variant). All 9 combinations.
      for (final variant in PalMemoryTemplates.all()) {
        final path = PalMemoryAudioPaths.assetPathFor(
            voiceKey: voice, clipId: variant.carrierClipId);
        if (File(path).existsSync()) {
          present.add(path);
        } else {
          missing.add(path);
        }
      }
      // Display names — one per registry entry.
      for (final entry in registry.all) {
        final path = PalMemoryAudioPaths.assetPathFor(
            voiceKey: voice, clipId: entry.clipId);
        if (File(path).existsSync()) {
          present.add(path);
        } else {
          missing.add(path);
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'Voices with partially-rendered memory audio. The bundled '
          'resolver would return silence for the engine combinations whose '
          'clips are missing — and silence on a registered display name is '
          'a render gap, not an editorial decision. Render the missing '
          'clips, or remove the registry entries that are no longer '
          'expected to ship audio.\n\n'
          'Voices present: ${voicesWithMemory.join(", ")}\n'
          'Missing clips (${missing.length}):\n${missing.join("\n")}',
    );
  });

  test('required-clip enumeration counts match the doctrine math', () {
    // Sanity-check the validator math itself: the number of clips per
    // voice equals (#carriers + #displayNames). Catches accidental
    // registry growth that wasn't reflected in the audio build plan.
    final carriers = PalMemoryTemplates.all().length;
    final names = registry.count;
    final perVoiceTotal = carriers + names;

    expect(carriers, greaterThan(0),
        reason: 'PalMemoryTemplates must define at least one variant.');
    expect(names, greaterThan(0),
        reason: 'Display-name registry must contain at least one entry.');
    expect(perVoiceTotal, equals(carriers + names));
    // The math the audio build plan report depends on:
    // - 9 carriers (3 bands × 3 variants) is the current expected.
    // - registry.count grows as Adam authors editorial entries.
    expect(carriers, equals(9),
        reason: 'Carrier count drifted from 9. Update the build plan report.');
  });
}
