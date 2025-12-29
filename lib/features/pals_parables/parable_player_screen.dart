import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bible_pal/providers/parable_player_notifier.dart';
import 'package:bible_pal/providers/app_state_notifier.dart';
import 'package:bible_pal/features/my_pals/select_pals_dialog.dart';
import 'package:bible_pal/models/share_record.dart';
import 'package:uuid/uuid.dart';

/// Parable Player Screen
/// Based on SPEC.md Features 11, 12, 16, 17
/// Displays parable with scripture sources and audio playback controls
class ParablePlayerScreen extends ConsumerStatefulWidget {
  const ParablePlayerScreen({super.key});

  @override
  ConsumerState<ParablePlayerScreen> createState() => _ParablePlayerScreenState();
}

class _ParablePlayerScreenState extends ConsumerState<ParablePlayerScreen> {
  bool _isFavorited = false;

  @override
  void initState() {
    super.initState();
    _checkIfFavorited();
  }

  Future<void> _checkIfFavorited() async {
    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable != null) {
      final appStateNotifier = ref.read(appStateProvider.notifier);
      final favorited =
          await appStateNotifier.isFavorited(playerState.currentParable!.storyId);
      if (mounted) {
        setState(() {
          _isFavorited = favorited;
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable == null) return;

    final appStateNotifier = ref.read(appStateProvider.notifier);

    if (_isFavorited) {
      await appStateNotifier.removeFavorite(playerState.currentParable!.storyId);
      if (mounted) {
        setState(() => _isFavorited = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Removed from favorites'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      await appStateNotifier.addFavorite(playerState.currentParable!);
      if (mounted) {
        setState(() => _isFavorited = true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Added to favorites'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _shareWithPals() async {
    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable == null) return;

    final appStateAsync = ref.read(appStateProvider);
    final pals = appStateAsync.valueOrNull?.pals ?? [];

    if (!mounted) return;

    // Show dialog to select PALs
    final selectedPalIds = await showDialog<List<String>>(
      context: context,
      builder: (context) => SelectPalsDialog(pals: pals),
    );

    if (selectedPalIds == null || selectedPalIds.isEmpty) return;

    final appStateNotifier = ref.read(appStateProvider.notifier);
    final parable = playerState.currentParable!;

    // Share with each selected PAL
    for (final palId in selectedPalIds) {
      final shareId = const Uuid().v4();
      final share = ShareRecord(
        shareId: shareId,
        storyId: parable.storyId,
        storyTitle: parable.title,
        toPalId: palId,
        timestamp: DateTime.now(),
        direction: ShareDirection.sent,
      );

      await appStateNotifier.shareStoryWithPal(share);
    }

    if (!mounted) return;

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          selectedPalIds.length == 1
              ? 'Shared with 1 PAL'
              : 'Shared with ${selectedPalIds.length} PALs',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(parablePlayerProvider);
    final playerNotifier = ref.watch(parablePlayerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PAL\'s Story'),
      ),
      body: playerState.currentParable == null
          ? const Center(
              child: Text('No parable loaded'),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Parable Title
                Text(
                  playerState.currentParable!.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Metadata
                Text(
                  'Mood: ${playerState.currentParable!.mood} • ${playerState.currentParable!.length} minutes',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Scripture Sources Panel (SPEC.md Feature #12)
                if (playerState.currentParable!.scriptureSources.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.menu_book,
                                color: theme.colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Scripture Sources',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            playerState.currentParable!.scriptureSources.join(', '),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Audio Playback Controls
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Position Slider
                        StreamBuilder<Duration>(
                          stream: playerNotifier.positionStream,
                          builder: (context, snapshot) {
                            final position = snapshot.data ?? Duration.zero;
                            final duration = playerNotifier.duration ?? Duration.zero;
                            final max = duration.inMilliseconds.toDouble();
                            final value = position.inMilliseconds
                                .toDouble()
                                .clamp(0.0, max);

                            return Column(
                              children: [
                                Slider(
                                  value: value,
                                  max: max > 0 ? max : 1,
                                  onChanged: (newValue) {
                                    playerNotifier.seek(
                                      Duration(
                                        milliseconds: newValue.toInt(),
                                      ),
                                    );
                                  },
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(_formatDuration(position)),
                                      Text(_formatDuration(duration)),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // Play/Pause/Stop Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Play/Pause Button
                            IconButton(
                              icon: Icon(
                                playerNotifier.isPlaying
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_filled,
                                size: 64,
                              ),
                              color: theme.colorScheme.primary,
                              onPressed: () {
                                if (playerNotifier.isPlaying) {
                                  playerNotifier.pause();
                                } else {
                                  playerNotifier.play();
                                }
                              },
                            ),
                            const SizedBox(width: 24),

                            // Stop Button
                            IconButton(
                              icon: const Icon(
                                Icons.stop_circle,
                                size: 48,
                              ),
                              color: theme.colorScheme.secondary,
                              onPressed: () {
                                playerNotifier.stop();
                              },
                            ),
                          ],
                        ),

                        // Loading or Error State
                        if (playerState.isLoading)
                          const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: CircularProgressIndicator(),
                          ),
                        if (playerState.errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              playerState.errorMessage!,
                              style: TextStyle(
                                color: theme.colorScheme.error,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Add to Favorites
                    OutlinedButton.icon(
                      onPressed: _toggleFavorite,
                      icon: Icon(
                        _isFavorited
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: _isFavorited ? Colors.red : null,
                      ),
                      label: Text(_isFavorited ? 'Favorited' : 'Favorite'),
                    ),

                    // Share with a PAL (SPEC.md Feature #14)
                    OutlinedButton.icon(
                      onPressed: _shareWithPals,
                      icon: const Icon(Icons.share),
                      label: const Text('Share with a PAL'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  /// Format duration to MM:SS
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
