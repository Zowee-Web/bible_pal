/// Diagnostics Screen
///
/// Hidden screen for exporting diagnostic breadcrumbs.
/// Only accessible when DIAGNOSTICS_ENABLED=true.
///
/// Features:
/// - Shows last 50 breadcrumbs as formatted JSON
/// - Copy all to clipboard button
/// - Clear breadcrumbs button
/// - Loads both in-memory and persisted breadcrumbs
/// - [DEBUG ONLY] Reset First Launch button for dev testing
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_logger.dart';
import '../../core/breadcrumb_store.dart';
import '../../core/crash_log_store.dart';
import '../../core/diagnostics_config.dart';
import '../../core/journey_testing_config.dart';
import 'journey_testing_panel.dart';
import '../../providers/app_state_notifier.dart';
import '../../providers/service_providers.dart';
import '../../services/storage_service.dart';

/// Diagnostics screen for viewing and exporting breadcrumbs.
///
/// Shows a "not available" message if diagnostics disabled.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  List<Map<String, Object?>> _breadcrumbs = [];
  bool _loading = true;
  String? _copyStatus;

  @override
  void initState() {
    super.initState();
    _loadBreadcrumbs();
  }

  Future<void> _loadBreadcrumbs() async {
    setState(() => _loading = true);

    try {
      // Get in-memory breadcrumbs
      final inMemory = getRecentBreadcrumbs();

      // Get persisted breadcrumbs (if diagnostics enabled)
      final persisted = await loadPersistedBreadcrumbs();

      // Merge: persisted (older) + in-memory (newer), dedupe by timestamp
      final merged = <String, Map<String, Object?>>{};

      for (final b in persisted) {
        final ts = b['ts']?.toString() ?? '';
        merged[ts] = b;
      }
      for (final b in inMemory) {
        final ts = b['ts']?.toString() ?? '';
        merged[ts] = b;
      }

      // Sort by timestamp (oldest first)
      final sorted = merged.values.toList()
        ..sort((a, b) {
          final tsA = a['ts']?.toString() ?? '';
          final tsB = b['ts']?.toString() ?? '';
          return tsA.compareTo(tsB);
        });

      // Keep last 50
      final trimmed =
          sorted.length > 50 ? sorted.sublist(sorted.length - 50) : sorted;

      setState(() {
        _breadcrumbs = trimmed;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _breadcrumbs = [];
        _loading = false;
      });
    }
  }

  /// Build the full support bundle for export
  Future<Map<String, Object?>> _buildSupportBundle() async {
    // Load crash log summaries (metadata only, not full content)
    final crashLogs = await loadCrashLogs();
    final crashLogSummary = crashLogs.take(5).map((log) => {
          'timestamp': log.timestamp.toUtc().toIso8601String(),
          'error_type': log.errorType,
          'breadcrumb_count': log.breadcrumbs.length,
        }).toList();

    // Get current mode state from UserPreferences
    final appState = ref.read(appStateProvider);
    final prefs = appState.valueOrNull?.userPreferences;
    final modeState = prefs != null
        ? {
            'storytellingMode': prefs.storytellingMode,
            'kidFriendlyOnly': prefs.kidFriendlyOnly,
          }
        : null;

    // Truncate platform_version if too long
    var platformVersion = Platform.operatingSystemVersion;
    if (platformVersion.length > 200) {
      platformVersion = '${platformVersion.substring(0, 200)}... [truncated]';
    }

    return {
      // Metadata
      'session_id': getSessionId(),
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'diagnostics_enabled': kDiagnosticsEnabled,

      // App info
      'app_version': AppLogger.instance.appVersion,
      'app_build': AppLogger.instance.appBuild,

      // Platform info (safe, non-PII)
      'platform': Platform.operatingSystem,
      'platform_version': platformVersion,
      'number_of_processors': Platform.numberOfProcessors,

      // Current mode state (if available)
      if (modeState != null) 'current_mode_state': modeState,

      // Crash log summary (last 5, metadata only)
      'crash_log_count': crashLogs.length,
      if (crashLogSummary.isNotEmpty) 'recent_crashes': crashLogSummary,

      // Last known filters (already sanitized)
      'last_filters': getLastFilters(),

      // Breadcrumbs (already sanitized)
      'breadcrumb_count': _breadcrumbs.length,
      'breadcrumbs': _breadcrumbs,
    };
  }

  Future<void> _copyToClipboard() async {
    try {
      const jsonEncoder = JsonEncoder.withIndent('  ');
      final supportBundle = await _buildSupportBundle();
      final jsonString = jsonEncoder.convert(supportBundle);

      await Clipboard.setData(ClipboardData(text: jsonString));

      setState(() => _copyStatus = 'Copied!');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _copyStatus = null);
        }
      });
    } catch (e) {
      setState(() => _copyStatus = 'Copy failed');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _copyStatus = null);
        }
      });
    }
  }

  Future<void> _clearBreadcrumbs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Breadcrumbs?'),
        content: const Text(
            'This will clear all diagnostic breadcrumbs from memory and disk.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      AppLogger.instance.clearBreadcrumbs();
      await BreadcrumbStore.instance.clear();
      await _loadBreadcrumbs();
    }
  }

  /// [DEBUG ONLY] Play test audio asset for dev testing.
  Future<void> _playTestAudio() async {
    final audioService = ref.read(audioServiceProvider);
    await audioService.playAsset('assets/audio/pal_test_greeting_sarah.mp3');
  }

  /// [DEBUG ONLY] Play story audio test for macOS audio routing diagnostics.
  Future<void> _playStoryAudioTest() async {
    final audioService = ref.read(audioServiceProvider);

    if (kDebugMode) {
      debugPrint('DiagnosticsScreen: Testing story audio playback (just_audio)');
    }

    try {
      // Test story audio playback using just_audio
      // This helps diagnose macOS audio routing issues
      await audioService.playAsset('assets/audio/pal_test_greeting_sarah.mp3');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Story audio test started. Listen for playback.'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('DiagnosticsScreen: Story audio test failed: $e');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Story audio test failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// [DEBUG ONLY] Reset first-launch state for dev testing.
  /// Calls StorageService.resetFirstLaunchDevOnly() which is the single source of truth.
  Future<void> _resetFirstLaunch() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset First Launch?'),
        content: const Text(
            'This will reset onboarding state:\n\n'
            '• Onboarding completion flag\n'
            '• User name\n'
            '• Voice consent settings\n\n'
            'Favorites and history will be preserved.\n\n'
            'Restart the app to re-run onboarding.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final sp = await SharedPreferences.getInstance();
      final storageService = StorageService(sp);
      await storageService.resetFirstLaunchDevOnly();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('First launch reset. Restart app to re-run onboarding.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reset failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDiagnosticsEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Diagnostics')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Diagnostics not available.\n\n'
              'Enable with:\nflutter run --dart-define=DIAGNOSTICS_ENABLED=true',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          if (_copyStatus != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  _copyStatus!,
                  style: TextStyle(
                    color: _copyStatus == 'Copied!' ? Colors.green : Colors.red,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy to Clipboard',
            onPressed: _breadcrumbs.isEmpty ? null : _copyToClipboard,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear Breadcrumbs',
            onPressed: _breadcrumbs.isEmpty ? null : _clearBreadcrumbs,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadBreadcrumbs,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // [DEBUG ONLY] Reset First Launch button
                if (kDebugMode)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.orange.withValues(alpha: 0.1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Developer Tools',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _resetFirstLaunch,
                            icon: const Icon(Icons.restart_alt, size: 18),
                            label: const Text('Reset First Launch (Dev)'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange,
                              side: const BorderSide(color: Colors.orange),
                            ),
                          ),
                        ),
                        if (kDiagnosticsEnabled) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _playTestAudio,
                              icon: const Icon(Icons.play_arrow, size: 18),
                              label: const Text('Play Test Audio (Dev)'),
                            ),
                          ),
                        ],
                        if (const bool.fromEnvironment('DEBUG_AUDIO_PANEL')) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _playStoryAudioTest,
                              icon: const Icon(Icons.volume_up, size: 18),
                              label: const Text('Test Story Audio (just_audio)'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue,
                                side: const BorderSide(color: Colors.blue),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              'macOS audio routing test: Should play via just_audio when SoLoud is disabled',
                              style: TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                // Beta-only Journey testing panel (JOURNEY_TESTING_ENABLED).
                // A sibling of the kDebugMode block above — NOT nested in
                // it — so it shows in release beta builds, not just debug.
                if (kJourneyTestingEnabled) const JourneyTestingPanel(),
                // Breadcrumbs list or empty state
                Expanded(
                  child: _breadcrumbs.isEmpty
                      ? const Center(
                          child: Text(
                            'No breadcrumbs recorded yet.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _breadcrumbs.length,
                          itemBuilder: (context, index) {
                            final breadcrumb = _breadcrumbs[index];
                            final event =
                                breadcrumb['event']?.toString() ?? 'unknown';
                            final level =
                                breadcrumb['level']?.toString() ?? 'info';
                            final ts = breadcrumb['ts']?.toString() ?? '';

                            // Format timestamp for display
                            String formattedTs = ts;
                            try {
                              final dt = DateTime.parse(ts);
                              formattedTs =
                                  '${dt.hour.toString().padLeft(2, '0')}:'
                                  '${dt.minute.toString().padLeft(2, '0')}:'
                                  '${dt.second.toString().padLeft(2, '0')}';
                            } catch (_) {}

                            // Level color
                            final levelColor = switch (level) {
                              'debug' => Colors.grey,
                              'info' => Colors.blue,
                              'warn' => Colors.orange,
                              'error' => Colors.red,
                              _ => Colors.grey,
                            };

                            // Remove event/level/ts from data for display
                            final data = Map<String, Object?>.from(breadcrumb)
                              ..remove('event')
                              ..remove('level')
                              ..remove('ts');

                            return ExpansionTile(
                              leading: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: levelColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  level.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: levelColor,
                                  ),
                                ),
                              ),
                              title: Text(
                                event,
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                              subtitle: Text(
                                formattedTs,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                              children: [
                                if (data.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.grey.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        const JsonEncoder.withIndent('  ')
                                            .convert(data),
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
