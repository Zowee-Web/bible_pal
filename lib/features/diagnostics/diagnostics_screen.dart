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
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_logger.dart';
import '../../core/breadcrumb_store.dart';
import '../../core/diagnostics_config.dart';

/// Diagnostics screen for viewing and exporting breadcrumbs.
///
/// Shows a "not available" message if diagnostics disabled.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
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
      final trimmed = sorted.length > 50 ? sorted.sublist(sorted.length - 50) : sorted;

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
  Map<String, Object?> _buildSupportBundle() {
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
      'platform_version': Platform.operatingSystemVersion,

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
      final supportBundle = _buildSupportBundle();
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
        content: const Text('This will clear all diagnostic breadcrumbs from memory and disk.'),
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
          : _breadcrumbs.isEmpty
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
                    final event = breadcrumb['event']?.toString() ?? 'unknown';
                    final level = breadcrumb['level']?.toString() ?? 'info';
                    final ts = breadcrumb['ts']?.toString() ?? '';

                    // Format timestamp for display
                    String formattedTs = ts;
                    try {
                      final dt = DateTime.parse(ts);
                      formattedTs = '${dt.hour.toString().padLeft(2, '0')}:'
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      children: [
                        if (data.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                const JsonEncoder.withIndent('  ').convert(data),
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
    );
  }
}
