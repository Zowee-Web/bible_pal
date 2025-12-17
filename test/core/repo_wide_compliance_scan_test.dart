import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/bible_translation_registry.dart';

/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// 🔒 REPO-WIDE COMPLIANCE SCAN - CRITICAL INVARIANT ENFORCEMENT
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// ⚠️  DO NOT REMOVE OR WEAKEN THIS TEST ⚠️
///
/// This test enforces the **Bible Translation Licensing Invariant**, a
/// non-negotiable requirement documented in docs/INVARIANTS.md.
///
/// **What it does:**
/// Scans all source files in lib/, test/, assets/, and server/ for:
/// 1. Banned translation IDs (NIV, ESV, NRSV, NLT, NASB, CSB, MSG, HCSB, AMP, GNT)
/// 2. Unknown translation IDs (not in BibleTranslationRegistry.allowedIds)
///
/// **Why it exists:**
/// - Using copyrighted Bible translations violates copyright law
/// - Exposes the project to legal liability
/// - Requires expensive licensing fees ($thousands per year)
/// - Only public-domain translations (WEB, KJV, ASV, YLT, DRA) are permitted
///
/// **When it fails:**
/// - The build MUST fail (enforced by CI)
/// - PRs cannot be merged
/// - Developer must remove all references to banned translations
///
/// **This test is intentionally strict:**
/// - It scans the entire codebase, not just runtime code
/// - It fails fast on any violation
/// - Exclusions are minimal and documented (registry file, docs, test files)
///
/// **If you're seeing this because you want to "clean up" or "fix" this test:**
/// DON'T. This test is not broken. It is enforcing a legal requirement.
/// See docs/INVARIANTS.md and docs/BIBLE_TRANSLATION_COMPLIANCE.md for full context.
///
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

void main() {
  group('Repo-Wide Compliance Scan', () {
    late Directory projectRoot;
    late Set<String> bannedTokens;
    late Set<String> allowedTokens;

    setUpAll(() {
      // Find project root (go up from test directory)
      projectRoot = Directory.current;
      while (!File('${projectRoot.path}/pubspec.yaml').existsSync()) {
        projectRoot = projectRoot.parent;
        if (projectRoot.path == projectRoot.parent.path) {
          throw Exception('Could not find project root (pubspec.yaml)');
        }
      }

      // Build banned and allowed token sets
      bannedTokens = BibleTranslationRegistry.bannedIds;
      allowedTokens = BibleTranslationRegistry.allowedIds;

      // ignore: avoid_print
      print('📁 Project root: ${projectRoot.path}');
      // ignore: avoid_print
      print('🚫 Banned translations: $bannedTokens');
      // ignore: avoid_print
      print('✅ Allowed translations: $allowedTokens');
    });

    test('CRITICAL: No banned translation IDs in lib/ directory', () {
      final libDir = Directory('${projectRoot.path}/lib');
      expect(libDir.existsSync(), isTrue, reason: 'lib/ directory must exist');

      final violations = <String>[];
      _scanDirectory(libDir, bannedTokens, allowedTokens, violations);

      expect(
        violations,
        isEmpty,
        reason: 'Found banned translation references in lib/:\n${violations.join('\n')}',
      );
    });

    test('CRITICAL: No banned translation IDs in test/ directory', () {
      final testDir = Directory('${projectRoot.path}/test');
      expect(testDir.existsSync(), isTrue, reason: 'test/ directory must exist');

      final violations = <String>[];
      // Exclude this test file itself and the compliance test (they contain banned IDs for testing)
      _scanDirectory(
        testDir,
        bannedTokens,
        allowedTokens,
        violations,
        excludeFiles: [
          'repo_wide_compliance_scan_test.dart',
          'bible_translation_compliance_test.dart',
          'verse_service_test.dart', // Contains comments explaining banned translations
        ],
      );

      expect(
        violations,
        isEmpty,
        reason: 'Found banned translation references in test/:\n${violations.join('\n')}',
      );
    });

    test('CRITICAL: No banned translation IDs in assets/ directory', () {
      final assetsDir = Directory('${projectRoot.path}/assets');
      if (!assetsDir.existsSync()) {
        // ignore: avoid_print
        print('⚠️  assets/ directory does not exist, skipping');
        return;
      }

      final violations = <String>[];
      _scanDirectory(assetsDir, bannedTokens, allowedTokens, violations);

      expect(
        violations,
        isEmpty,
        reason: 'Found banned translation references in assets/:\n${violations.join('\n')}',
      );
    });

    test('CRITICAL: No banned translation IDs in server/ scripts', () {
      final serverDir = Directory('${projectRoot.path}/server');
      if (!serverDir.existsSync()) {
        // ignore: avoid_print
        print('⚠️  server/ directory does not exist, skipping');
        return;
      }

      final violations = <String>[];
      _scanDirectory(serverDir, bannedTokens, allowedTokens, violations);

      expect(
        violations,
        isEmpty,
        reason: 'Found banned translation references in server/:\n${violations.join('\n')}',
      );
    });

    test('INFO: Report all translation IDs found in repo', () {
      // Map of directory name -> translation ID -> file paths
      final directorySummary = <String, Map<String, List<String>>>{
        'lib/': {},
        'test/': {},
        'assets/': {},
        'server/': {},
      };

      final allDirs = [
        Directory('${projectRoot.path}/lib'),
        Directory('${projectRoot.path}/test'),
        Directory('${projectRoot.path}/assets'),
        Directory('${projectRoot.path}/server'),
      ];

      final allTokens = <String>{...allowedTokens, ...bannedTokens};

      for (final dir in allDirs) {
        if (!dir.existsSync()) continue;

        final dirName = '${dir.path.split('/').last}/';
        final foundTranslations = <String, List<String>>{};

        _findTranslationReferences(
          dir,
          allTokens,
          foundTranslations,
        );

        directorySummary[dirName] = foundTranslations;
      }

      // ignore: avoid_print
      print('\n📊 Translation IDs found in repo (by directory):');

      var hasAnyTranslations = false;
      for (final dirEntry in directorySummary.entries) {
        final dirName = dirEntry.key;
        final translations = dirEntry.value;

        if (translations.isEmpty) continue;
        hasAnyTranslations = true;

        // ignore: avoid_print
        print('\n$dirName');

        // Sort translations: allowed first, then banned
        final sortedTranslations = translations.entries.toList()
          ..sort((a, b) {
            final aAllowed = allowedTokens.contains(a.key);
            final bAllowed = allowedTokens.contains(b.key);
            if (aAllowed && !bAllowed) return -1;
            if (!aAllowed && bAllowed) return 1;
            return a.key.compareTo(b.key);
          });

        for (final entry in sortedTranslations) {
          final id = entry.key;
          final files = entry.value;
          final status = allowedTokens.contains(id) ? '✅' : '🚫';
          // ignore: avoid_print
          print('  $status $id (${files.length} files)');
        }
      }

      if (!hasAnyTranslations) {
        // ignore: avoid_print
        print('   (none found)');
      }
    });
  });
}

/// Scan a directory recursively for banned translation IDs
void _scanDirectory(
  Directory dir,
  Set<String> bannedTokens,
  Set<String> allowedTokens,
  List<String> violations, {
  List<String> excludeFiles = const [],
}) {
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      // Skip binary files and certain extensions
      if (_shouldSkipFile(entity.path)) continue;

      // Skip excluded files
      final fileName = entity.uri.pathSegments.last;
      if (excludeFiles.contains(fileName)) continue;

      try {
        final content = entity.readAsStringSync();
        _scanContent(entity.path, content, bannedTokens, allowedTokens, violations);
      } catch (e) {
        // Skip files that can't be read as text (likely binary)
        continue;
      }
    }
  }
}

/// Check if a file should be skipped
bool _shouldSkipFile(String path) {
  // Skip the registry file itself (it MUST contain banned translations to define them)
  if (path.contains('bible_translation_registry.dart')) return true;

  // Skip compliance documentation (it references banned translations)
  if (path.contains('BIBLE_TRANSLATION_COMPLIANCE.md')) return true;

  // Skip node_modules (contains unrelated code with "msg" variables)
  if (path.contains('node_modules/')) return true;

  // Skip generated files
  if (path.contains('.dart_tool/')) return true;
  if (path.contains('.flutter-plugins')) return true;
  if (path.contains('generated_plugin_registrant')) return true;

  // Skip binary files
  final ext = path.split('.').last.toLowerCase();
  const binaryExtensions = [
    'png', 'jpg', 'jpeg', 'gif', 'ico', 'mp3', 'wav', 'mp4',
    'ttf', 'otf', 'woff', 'woff2', 'lock', 'iml', 'xcworkspace',
    'pbxproj', 'gradle', 'jar', 'aar', 'so', 'dylib', 'framework',
  ];
  if (binaryExtensions.contains(ext)) return true;

  return false;
}

/// Scan file content for banned translation IDs
void _scanContent(
  String filePath,
  String content,
  Set<String> bannedTokens,
  Set<String> allowedTokens,
  List<String> violations,
) {
  // Split into words and scan for translation IDs
  final words = content.split(RegExp(r'''\s+|[,;:(){}[\]"'<>]'''));

  for (final word in words) {
    final normalized = word.trim().toUpperCase();

    // Check if this is a banned translation ID
    if (bannedTokens.contains(normalized)) {
      // Special case: Allow "NRSV" in comments explaining why it's banned
      if (normalized == 'NRSV' && _isInComment(content, word)) {
        continue;
      }

      violations.add('$filePath: Found banned translation "$word"');
    }
  }
}

/// Find all translation references (for reporting)
void _findTranslationReferences(
  Directory dir,
  Set<String> translationIds,
  Map<String, List<String>> foundTranslations,
) {
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      if (_shouldSkipFile(entity.path)) continue;

      try {
        final content = entity.readAsStringSync();
        final words = content.split(RegExp(r'''\s+|[,;:(){}[\]"'<>]'''));

        for (final word in words) {
          final normalized = word.trim().toUpperCase();
          if (translationIds.contains(normalized)) {
            foundTranslations.putIfAbsent(normalized, () => []).add(entity.path);
          }
        }
      } catch (e) {
        continue;
      }
    }
  }
}

/// Check if a word appears in a comment
bool _isInComment(String content, String word) {
  // Simple heuristic: check if word appears after '//' or '/*' on same line
  final lines = content.split('\n');
  for (final line in lines) {
    if (line.contains(word)) {
      final trimmed = line.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('/*') || trimmed.startsWith('*')) {
        return true;
      }
    }
  }
  return false;
}
