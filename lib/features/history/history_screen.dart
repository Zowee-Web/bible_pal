import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_state_notifier.dart';
import '../../providers/parable_player_notifier.dart';

/// History Screen
/// Based on SPEC.md Feature #11: History System
/// Displays last 20 listened parables (FIFO), most recent first
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  Future<void> _playHistoryEntry(
    BuildContext context,
    WidgetRef ref,
    String storyId,
  ) async {
    final appState = ref.read(appStateProvider.notifier);
    final player = ref.read(parablePlayerProvider.notifier);

    // Look up the parable by ID
    final parable = await appState.getParableById(storyId);

    if (!context.mounted) return;

    if (parable == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Story not found'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Load into player
    await player.loadParable(parable);

    if (!context.mounted) return;

    // Navigate to player screen
    Navigator.of(context).pushNamed('/parable_player');
  }

  Future<void> _clearHistory(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text(
          'Are you sure you want to clear all history? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final appState = ref.read(appStateProvider.notifier);
      await appState.clearHistory();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('History cleared'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      // Simple date format: Dec 8, 2025
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${months[timestamp.month - 1]} ${timestamp.day}, ${timestamp.year}';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider).requireValue;
    final history = appState.history;
    final theme = Theme.of(context);

    // Contract enforcement: History must never exceed 20 entries
    // This assertion helps detect if AppState is providing uncapped data
    assert(
      history.length <= 20,
      'History violated cap: ${history.length} items (expected ≤20). '
      'This indicates AppState.history is not properly capped by StorageService.',
    );

    // Debug logging (strips in release builds)
    assert(() {
      debugPrint('📜 History Screen: ${history.length} items');
      if (history.isNotEmpty) {
        debugPrint('  First: ${history.first.storyId} at ${history.first.timestamp}');
        debugPrint('  Last: ${history.last.storyId} at ${history.last.timestamp}');
      }
      return true;
    }());

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: history.isNotEmpty
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_sweep),
                  onPressed: () => _clearHistory(context, ref),
                  tooltip: 'Clear History',
                ),
              ]
            : null,
      ),
      body: history.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No history yet',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Stories you listen to will appear here',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              itemBuilder: (context, index) {
                final entry = history[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      child: Icon(
                        Icons.play_arrow,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    title: Text(
                      entry.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          '${entry.length} min • ${entry.mood}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(entry.timestamp),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _playHistoryEntry(context, ref, entry.storyId),
                  ),
                );
              },
            ),
    );
  }
}
