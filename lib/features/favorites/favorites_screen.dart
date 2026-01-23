import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_state_notifier.dart';
import '../../providers/parable_player_notifier.dart';

/// Favorites Screen
/// Based on SPEC.md Feature #10: Favorites System
/// Displays user's favorited parables (unlimited capacity)
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  Future<void> _playFavorite(
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

  Future<void> _removeFavorite(
    BuildContext context,
    WidgetRef ref,
    String storyId,
    String title,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Favorite'),
        content: Text('Remove "$title" from favorites?'),
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
      await appState.removeFavorite(storyId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Removed from favorites'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider).requireValue;
    final favorites = appState.favorites;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites'),
      ),
      body: favorites.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No favorites yet',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the heart icon on any parable to save it here',
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
              itemCount: favorites.length,
              itemBuilder: (context, index) {
                final favorite = favorites[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.auto_stories,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      favorite.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          '${favorite.lengthBucket.displayLabel} • ${favorite.mood}',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (favorite.scriptureSources.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            favorite.scriptureSources.join(', '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _removeFavorite(
                        context,
                        ref,
                        favorite.storyId,
                        favorite.title,
                      ),
                    ),
                    onTap: () => _playFavorite(context, ref, favorite.storyId),
                  ),
                );
              },
            ),
    );
  }
}
