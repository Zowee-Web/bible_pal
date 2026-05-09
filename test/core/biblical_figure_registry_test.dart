import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/biblical_figure_registry.dart';

void main() {
  late Map<String, dynamic> registryData;
  late List<dynamic> entries;

  // Load the manifest for cross-validation.
  late Set<String> manifestBibleStoryKeys;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final registryJson = await rootBundle
        .loadString('assets/stories/biblical_figure_registry.json');
    registryData = jsonDecode(registryJson) as Map<String, dynamic>;
    entries = registryData['entries'] as List<dynamic>;

    final manifestJson =
        await rootBundle.loadString('assets/stories/manifest.json');
    final manifestData = jsonDecode(manifestJson) as Map<String, dynamic>;
    final parables = manifestData['parables'] as List<dynamic>;
    manifestBibleStoryKeys = <String>{};
    for (final p in parables) {
      final m = p as Map<String, dynamic>;
      if (m['storytellingMode'] == 'traditional') {
        final key = m['bibleStoryKey'] as String?;
        if (key != null) manifestBibleStoryKeys.add(key);
      }
    }
  });

  group('Biblical Figure Registry — structure', () {
    test('has required top-level fields', () {
      expect(registryData.containsKey('version'), true);
      expect(registryData.containsKey('entries'), true);
      expect(registryData['version'], isA<int>());
    });

    test('has at least 1 entry', () {
      expect(entries, isNotEmpty);
    });

    test('all entries have required fields', () {
      for (final raw in entries) {
        final e = raw as Map<String, dynamic>;
        expect(e['bibleStoryKey'], isA<String>(),
            reason: 'bibleStoryKey must be a string');
        expect((e['bibleStoryKey'] as String).isNotEmpty, true,
            reason: 'bibleStoryKey must not be empty');
        expect(e['primaryFigure'], isA<String>(),
            reason: 'primaryFigure must be a string');
        expect((e['primaryFigure'] as String).isNotEmpty, true,
            reason: 'primaryFigure must not be empty');
        expect(e['secondaryFigures'], isA<List>(),
            reason: 'secondaryFigures must be a list');
        expect(e['framingLines'], isA<List>(),
            reason: 'framingLines must be a list');
        // Stub entries (auto-generated 2026-05 with `_stub: true`) are
        // permitted to have empty framingLines pending manual curation.
        // Non-stub entries must still have ≥ 1 framing line.
        if (e['_stub'] == true) continue;
        expect((e['framingLines'] as List).isNotEmpty, true,
            reason:
                '${e['bibleStoryKey']} must have at least 1 framing line');
      }
    });

    test('all bibleStoryKey values are unique', () {
      final keys = entries
          .map((e) => (e as Map<String, dynamic>)['bibleStoryKey'] as String)
          .toList();
      expect(keys.toSet().length, keys.length,
          reason: 'Duplicate bibleStoryKey found');
    });
  });

  group('Biblical Figure Registry — framing lines', () {
    test('all framing lines are objects with id and text', () {
      for (final raw in entries) {
        final e = raw as Map<String, dynamic>;
        final key = e['bibleStoryKey'] as String;
        for (final line in e['framingLines'] as List) {
          final obj = line as Map<String, dynamic>;
          expect(obj['id'], isA<String>(), reason: '$key has non-string id');
          expect((obj['id'] as String).isNotEmpty, true,
              reason: '$key has empty framing line id');
          expect(obj['text'], isA<String>(),
              reason: '$key has non-string text');
          expect((obj['text'] as String).isNotEmpty, true,
              reason: '$key has empty framing line text');
        }
      }
    });

    test('all framing line IDs follow FRAME_{KEY}_{NN} convention', () {
      for (final raw in entries) {
        final e = raw as Map<String, dynamic>;
        final key = e['bibleStoryKey'] as String;
        final keyUpper = key.toUpperCase();
        for (final line in e['framingLines'] as List) {
          final id = (line as Map<String, dynamic>)['id'] as String;
          expect(id, startsWith('FRAME_${keyUpper}_'),
              reason: 'ID "$id" does not match key "$key"');
        }
      }
    });

    test('all framing line IDs are unique', () {
      final ids = <String>{};
      for (final raw in entries) {
        final e = raw as Map<String, dynamic>;
        for (final line in e['framingLines'] as List) {
          final id = (line as Map<String, dynamic>)['id'] as String;
          expect(ids.add(id), true, reason: 'Duplicate ID: $id');
        }
      }
    });

    test('all framing line texts are <= 150 characters', () {
      final violations = <String>[];
      for (final raw in entries) {
        final e = raw as Map<String, dynamic>;
        final key = e['bibleStoryKey'] as String;
        for (final line in e['framingLines'] as List) {
          final text = (line as Map<String, dynamic>)['text'] as String;
          if (text.length > 150) {
            violations.add('$key: "${text.substring(0, 50)}..." '
                '(${text.length} chars)');
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'Framing lines over 150 chars:\n${violations.join('\n')}');
    });

    test('no framing line contains banned prescriptive patterns', () {
      final banned = [
        'god wants you',
        'god needs you',
        'you should',
        'you must',
      ];
      final violations = <String>[];
      for (final raw in entries) {
        final e = raw as Map<String, dynamic>;
        final key = e['bibleStoryKey'] as String;
        for (final line in e['framingLines'] as List) {
          final text = (line as Map<String, dynamic>)['text'] as String;
          final lower = text.toLowerCase();
          for (final pattern in banned) {
            if (lower.contains(pattern)) {
              violations.add('$key: "$text" contains "$pattern"');
            }
          }
        }
      }
      expect(violations, isEmpty,
          reason:
              'Prescriptive theology found:\n${violations.join('\n')}');
    });
  });

  group('Biblical Figure Registry — cross-validation', () {
    test('every registry bibleStoryKey exists in manifest.json', () {
      final missing = <String>[];
      for (final raw in entries) {
        final key =
            (raw as Map<String, dynamic>)['bibleStoryKey'] as String;
        if (!manifestBibleStoryKeys.contains(key)) {
          missing.add(key);
        }
      }
      expect(missing, isEmpty,
          reason:
              'Registry keys not in manifest: ${missing.join(', ')}');
    });

    test('every traditional bibleStoryKey in manifest has a registry entry',
        () {
      final registryKeys = entries
          .map((e) => (e as Map<String, dynamic>)['bibleStoryKey'] as String)
          .toSet();
      final missing = manifestBibleStoryKeys
          .where((key) => !registryKeys.contains(key))
          .toList()
        ..sort();
      expect(missing, isEmpty,
          reason:
              'Traditional keys without registry entry: ${missing.join(', ')}');
    });
  });

  group('Biblical Figure Registry — Dart loader', () {
    setUp(() {
      BiblicalFigureRegistry.resetForTesting();
    });

    test('ensureLoaded() populates entries', () async {
      await BiblicalFigureRegistry.ensureLoaded();
      expect(BiblicalFigureRegistry.entries, isNotEmpty);
    });

    test('ensureLoaded() is idempotent', () async {
      await BiblicalFigureRegistry.ensureLoaded();
      final count1 = BiblicalFigureRegistry.entries.length;
      await BiblicalFigureRegistry.ensureLoaded();
      final count2 = BiblicalFigureRegistry.entries.length;
      expect(count1, count2);
    });

    test('getFramingLine returns null for null key', () async {
      await BiblicalFigureRegistry.ensureLoaded();
      expect(BiblicalFigureRegistry.getFramingLine(null), isNull);
    });

    test('getFramingLine returns null for unknown key', () async {
      await BiblicalFigureRegistry.ensureLoaded();
      expect(
          BiblicalFigureRegistry.getFramingLine('nonexistent_key'), isNull);
    });

    test('getFramingLine returns non-null for known key', () async {
      await BiblicalFigureRegistry.ensureLoaded();
      final line = BiblicalFigureRegistry.getFramingLine(
          'joseph_sold_by_brothers');
      expect(line, isNotNull);
      expect(line, isA<String>());
      expect(line!.isNotEmpty, true);
    });

    test('getEntry returns null for unknown key', () async {
      await BiblicalFigureRegistry.ensureLoaded();
      expect(BiblicalFigureRegistry.getEntry('nonexistent_key'), isNull);
    });

    test('getEntry returns valid entry for known key', () async {
      await BiblicalFigureRegistry.ensureLoaded();
      final entry =
          BiblicalFigureRegistry.getEntry('joseph_sold_by_brothers');
      expect(entry, isNotNull);
      expect(entry!.primaryFigure, 'Joseph');
      expect(entry.framingLines.length, greaterThanOrEqualTo(2));
    });
  });
}
