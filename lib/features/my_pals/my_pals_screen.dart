import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_state_notifier.dart';
import '../../models/pal.dart';
import 'add_pal_dialog.dart';

/// My PALs Screen - Manage friends and view shared stories
/// v1.0: Simple list with add/remove, shows shared stories per PAL
class MyPalsScreen extends ConsumerWidget {
  const MyPalsScreen({super.key});

  Future<void> _addPal(BuildContext context, WidgetRef ref) async {
    final pal = await showDialog<PAL>(
      context: context,
      builder: (context) => const AddPalDialog(),
    );

    if (pal != null && context.mounted) {
      final appState = ref.read(appStateProvider.notifier);
      await appState.addPal(pal);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${pal.displayName} added as a PAL'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _removePal(
    BuildContext context,
    WidgetRef ref,
    PAL pal,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove PAL'),
        content: Text('Remove ${pal.displayName} from your PALs?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final appState = ref.read(appStateProvider.notifier);
      await appState.removePal(pal.palId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PAL removed'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _togglePin(WidgetRef ref, PAL pal) async {
    final appState = ref.read(appStateProvider.notifier);
    await appState.updatePal(pal.copyWith(pinned: !pal.pinned));
  }

  Future<void> _showSharedStories(
    BuildContext context,
    WidgetRef ref,
    PAL pal,
  ) async {
    final appState = ref.read(appStateProvider.notifier);
    final shares = await appState.getSharesToPal(pal.palId);

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Shared with ${pal.displayName}'),
        content: shares.isEmpty
            ? const Text('No stories shared yet')
            : SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: shares.length,
                  itemBuilder: (context, index) {
                    final share = shares[index];
                    return ListTile(
                      leading: const Icon(Icons.auto_stories),
                      title: Text(share.storyTitle),
                      subtitle: Text(
                        share.timestamp.toString().split('.')[0],
                      ),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider).requireValue;
    final pals = appState.pals;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My PALs'),
      ),
      body: pals.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 64,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No PALs yet',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add friends to share stories with',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _addPal(context, ref),
                      icon: const Icon(Icons.person_add),
                      label: const Text('Add Your First PAL'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: pals.length,
              itemBuilder: (context, index) {
                final pal = pals[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          radius: 24,
                          child: Text(
                            pal.displayName[0].toUpperCase(),
                            style: TextStyle(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        if (pal.pinned)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.push_pin,
                                size: 12,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Text(
                      pal.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          pal.shareCount == 0
                              ? 'No stories shared yet'
                              : '${pal.shareCount} ${pal.shareCount == 1 ? "story" : "stories"} shared',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton(
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          onTap: () => _togglePin(ref, pal),
                          child: Row(
                            children: [
                              Icon(
                                pal.pinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                              ),
                              const SizedBox(width: 8),
                              Text(pal.pinned ? 'Unpin' : 'Pin'),
                            ],
                          ),
                        ),
                        if (pal.shareCount > 0)
                          PopupMenuItem(
                            onTap: () {
                              Future.delayed(
                                Duration.zero,
                                () {
                                  if (context.mounted) {
                                    _showSharedStories(context, ref, pal);
                                  }
                                },
                              );
                            },
                            child: const Row(
                              children: [
                                Icon(Icons.history),
                                SizedBox(width: 8),
                                Text('View Shared'),
                              ],
                            ),
                          ),
                        PopupMenuItem(
                          onTap: () {
                            Future.delayed(
                              Duration.zero,
                              () {
                                if (context.mounted) {
                                  _removePal(context, ref, pal);
                                }
                              },
                            );
                          },
                          child: const Row(
                            children: [
                              Icon(Icons.delete_outline),
                              SizedBox(width: 8),
                              Text('Remove'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    onTap: pal.shareCount > 0
                        ? () => _showSharedStories(context, ref, pal)
                        : null,
                  ),
                );
              },
            ),
      floatingActionButton: pals.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _addPal(context, ref),
              icon: const Icon(Icons.person_add),
              label: const Text('Add PAL'),
            )
          : null,
    );
  }
}
