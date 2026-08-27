// CRITICAL: Single production manifest authority contract.
//
// The historical manifest_opus.json may remain on disk, but it must never be
// bundled or referenced by active runtime and production tooling.

@Tags(['critical'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _authoritativeManifest = 'assets/stories/manifest.json';
const _historicalManifest = 'assets/stories/manifest_opus.json';

Iterable<File> _sourceFiles(String root, Set<String> extensions) sync* {
  for (final entity in Directory(root).listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final path = entity.path.replaceAll('\\', '/');
    if (extensions.any(path.endsWith)) yield entity;
  }
}

String _normalizedPath(File file) => file.path.replaceAll('\\', '/');

void main() {
  test('pubspec bundles only the authoritative production manifest', () {
    final declarations = File('pubspec.yaml')
        .readAsLinesSync()
        .map((line) => line.trim())
        .where((line) => line.startsWith('- assets/stories/'))
        .toSet();

    expect(declarations, contains('- $_authoritativeManifest'));
    expect(declarations, isNot(contains('- $_historicalManifest')));
  });

  test('runtime references manifest.json and never manifest_opus.json', () {
    final runtimeSources = _sourceFiles('lib', const {'.dart'}).toList();
    final authoritativeReferences = <String>[];
    final historicalReferences = <String>[];

    for (final file in runtimeSources) {
      final content = file.readAsStringSync();
      if (content.contains(_authoritativeManifest)) {
        authoritativeReferences.add(_normalizedPath(file));
      }
      if (content.contains(_historicalManifest)) {
        historicalReferences.add(_normalizedPath(file));
      }
    }

    expect(authoritativeReferences, isNotEmpty,
        reason: 'Runtime must reference $_authoritativeManifest.');
    expect(historicalReferences, isEmpty,
        reason: 'Active runtime must not reference $_historicalManifest:\n'
            '${historicalReferences.join('\n')}');
  });

  test('active production tooling never uses manifest_opus.json', () {
    const explicitlyArchivalTooling = {
      'scripts/archive_creative_to_t9.sh',
    };
    final historicalReferences = <String>[];

    for (final file in _sourceFiles('scripts', const {'.py', '.sh'})) {
      final path = _normalizedPath(file);
      if (path.startsWith('scripts/tests/') ||
          explicitlyArchivalTooling.contains(path)) {
        continue;
      }
      if (file.readAsStringSync().contains(_historicalManifest)) {
        historicalReferences.add(path);
      }
    }

    expect(historicalReferences, isEmpty,
        reason: 'Active production/catalog tooling must not use '
            '$_historicalManifest:\n${historicalReferences.join('\n')}');
  });

  test('core promotion and publication tools target manifest.json', () {
    const authoritativeTools = {
      'scripts/promote_traditional_stories.py',
      'scripts/promote_kid_stories.py',
      'scripts/story_factory/generate_story_claude.py',
      'scripts/upload_r2_catalog.sh',
    };

    for (final path in authoritativeTools) {
      final content = File(path).readAsStringSync();
      expect(content, contains('manifest.json'), reason: '$path drifted');
      expect(content, isNot(contains('manifest_opus.json')),
          reason: '$path reintroduced historical manifest authority');
    }
  });
}
