import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:bible_pal/providers/parable_player_notifier.dart';
import 'package:bible_pal/providers/app_state_notifier.dart';
import 'package:bible_pal/features/my_pals/select_pals_dialog.dart';
import 'package:bible_pal/features/consent/voice_consent_dialog.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/models/share_record.dart';
import 'package:bible_pal/services/reflection_service.dart';
import 'package:bible_pal/services/voice_consent_gate.dart';
import 'package:bible_pal/core/app_logger.dart';
import 'package:uuid/uuid.dart';

/// Parable Player Screen
/// Based on SPEC.md Features 11, 12, 16, 17, 34-37
/// Displays parable with scripture sources, audio playback, and post-story reflection
class ParablePlayerScreen extends ConsumerStatefulWidget {
  const ParablePlayerScreen({super.key});

  @override
  ConsumerState<ParablePlayerScreen> createState() =>
      _ParablePlayerScreenState();
}

class _ParablePlayerScreenState extends ConsumerState<ParablePlayerScreen> {
  bool _isFavorited = false;
  bool _showReflection = false;
  bool _reflectionDismissed = false;
  bool _reflectionExpanded = true;
  bool _isReflectionPlaying = false;
  bool _reflectionAudioPlayed = false;
  bool _hasReflectionAudio = false;
  final ReflectionService _reflectionService = ReflectionService();

  // Separate audio player for reflection (to not interfere with story player)
  AudioPlayer? _reflectionPlayer;

  @override
  void initState() {
    super.initState();
    _checkIfFavorited();
    _listenForPlaybackCompletion();
    _checkReflectionAudioExists();
  }

  @override
  void dispose() {
    _reflectionPlayer?.dispose();
    super.dispose();
  }

  /// Check if pre-generated reflection audio exists for current parable
  Future<void> _checkReflectionAudioExists() async {
    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable == null) return;

    final reflectionPath = _getReflectionAudioPath(playerState.currentParable!);
    if (reflectionPath == null) return;

    try {
      // Try to load the asset to check if it exists
      await rootBundle.load('assets/stories/$reflectionPath');
      if (mounted) {
        setState(() => _hasReflectionAudio = true);
      }
    } catch (_) {
      // Asset doesn't exist - reflection audio not available
      if (mounted) {
        setState(() => _hasReflectionAudio = false);
      }
    }
  }

  /// Get reflection audio path from parable metadata or derive from story audio path
  /// Convention: parable_001_joyful_5min.mp3 → parable_001_joyful_5min.reflection.mp3
  String? _getReflectionAudioPath(Parable parable) {
    // Prefer explicit reflection path from manifest
    if (parable.reflectionAudioPath != null) {
      return parable.reflectionAudioPath;
    }
    // Fall back to convention-based derivation
    final storyAudioPath = parable.audioFilePath;
    if (storyAudioPath == null) return null;
    if (!storyAudioPath.endsWith('.mp3')) return null;
    return storyAudioPath.replaceAll('.mp3', '.reflection.mp3');
  }

  void _listenForPlaybackCompletion() {
    final playerNotifier = ref.read(parablePlayerProvider.notifier);
    playerNotifier.audioService.playbackCompletedStream.listen((_) async {
      if (mounted && !_reflectionDismissed) {
        setState(() => _showReflection = true);

        // Auto-play reflection if voice consent is granted and audio exists
        await _maybeAutoPlayReflection();
      }
    });
  }

  /// ADR-010: Reflection audio is NEVER auto-played.
  /// User must tap "Hear Reflection" button to play.
  /// This method is intentionally empty - kept for backwards compatibility.
  Future<void> _maybeAutoPlayReflection() async {
    // ADR-010: Reflection is opt-in only. Never auto-play.
    // User must tap "Hear Reflection" button.
    // This method intentionally does nothing.
  }

  /// Play pre-generated reflection audio from local assets
  Future<void> _playReflectionAudio() async {
    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable == null) return;

    final reflectionPath = _getReflectionAudioPath(playerState.currentParable!);
    if (reflectionPath == null) return;

    try {
      // Initialize reflection player if needed
      _reflectionPlayer ??= AudioPlayer();

      // Load from assets
      await _reflectionPlayer!.setAsset('assets/stories/$reflectionPath');

      logEvent('reflection_start', {
        'story_id': playerState.currentParable!.storyId,
      });

      setState(() {
        _isReflectionPlaying = true;
        _reflectionAudioPlayed = true;
      });

      await _reflectionPlayer!.play();

      // Listen for completion
      _reflectionPlayer!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) {
            setState(() => _isReflectionPlaying = false);
          }
        }
      });
    } catch (e) {
      debugPrint('[ReflectionAudio] Error playing: $e');

      logEvent('reflection_fail', {
        'story_id': playerState.currentParable!.storyId,
        'error_type': e.runtimeType.toString(),
      }, level: LogLevel.error);

      setState(() {
        _isReflectionPlaying = false;
        _hasReflectionAudio = false; // Mark as unavailable
      });
    }
  }

  /// Stop reflection audio playback
  Future<void> _stopReflectionAudio() async {
    if (_reflectionPlayer != null) {
      await _reflectionPlayer!.stop();
      setState(() => _isReflectionPlaying = false);
    }
  }

  /// Replay reflection audio
  Future<void> _replayReflectionAudio() async {
    if (_reflectionPlayer != null) {
      await _reflectionPlayer!.seek(Duration.zero);
      await _reflectionPlayer!.play();
      setState(() => _isReflectionPlaying = true);
    } else {
      await _playReflectionAudio();
    }
  }

  /// Handle play reflection button with consent check
  Future<void> _handlePlayReflection() async {
    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState == null) return;

    final gateResult =
        VoiceConsentGate.checkStoryNarration(appState.userPreferences);

    switch (gateResult) {
      case VoiceGateResult.allowed:
        await _playReflectionAudio();
        break;

      case VoiceGateResult.needsConsent:
        if (!mounted) return;
        final consentResult = await VoiceConsentDialog.show(context);
        if (consentResult == VoiceConsentResult.enabled) {
          await _playReflectionAudio();
        }
        break;

      case VoiceGateResult.blocked:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Voice narration is disabled. Enable it in Settings.'),
            duration: Duration(seconds: 3),
          ),
        );
        break;
    }
  }

  Future<void> _checkIfFavorited() async {
    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable != null) {
      final appStateNotifier = ref.read(appStateProvider.notifier);
      final favorited = await appStateNotifier
          .isFavorited(playerState.currentParable!.storyId);
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
      await appStateNotifier
          .removeFavorite(playerState.currentParable!.storyId);
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

  /// Handle play button press with voice consent check.
  /// Shows VoiceConsentDialog if user hasn't consented yet.
  Future<void> _handlePlay(ParablePlayerNotifier playerNotifier) async {
    final result = await playerNotifier.play();

    if (!mounted) return;

    switch (result) {
      case VoicePlayResult.played:
        // Audio started successfully, nothing more to do
        break;

      case VoicePlayResult.needsConsent:
        // Show consent dialog
        final consentResult = await VoiceConsentDialog.show(context);

        if (!mounted) return;

        // If user enabled narration, retry play
        if (consentResult == VoiceConsentResult.enabled) {
          // Re-check consent by playing again
          await playerNotifier.play();
        }
        // If declined or dismissed, stay in text-only mode (no action needed)
        break;

      case VoicePlayResult.disabled:
        // User explicitly disabled narration - show snackbar as gentle reminder
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Story narration is disabled. Enable it in Settings.'),
            duration: Duration(seconds: 3),
          ),
        );
        break;

      case VoicePlayResult.noParable:
        // Should not happen since button is only visible when parable is loaded
        break;

      case VoicePlayResult.error:
        // Error message is set in state, will be displayed by UI
        break;
    }
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
                  'Mood: ${playerState.currentParable!.mood} • ${playerState.currentParable!.lengthBucket.displayLabel}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Scripture Reference Panel (ADR-010)
                // For Traditional stories: Show bibleSourceRef AFTER story completes
                // For Creative stories: Show scriptureSources if present (always visible)
                if (_showReflection &&
                    playerState.currentParable!.storytellingMode ==
                        'traditional' &&
                    playerState.currentParable!.hasBibleSourceRef) ...[
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
                                'Scripture Reference',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            playerState.currentParable!.bibleSourceRef!,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ] else if (playerState.currentParable!.storytellingMode ==
                        'creative' &&
                    playerState
                        .currentParable!.scriptureSources.isNotEmpty) ...[
                  // Creative stories can show scriptureSources during playback
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
                            playerState.currentParable!.scriptureSources
                                .join(', '),
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
                            final duration =
                                playerNotifier.duration ?? Duration.zero;
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
                              onPressed: () async {
                                if (playerNotifier.isPlaying) {
                                  playerNotifier.pause();
                                } else {
                                  await _handlePlay(playerNotifier);
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
                        _isFavorited ? Icons.favorite : Icons.favorite_border,
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

                // Post-Story Reflection (SPEC.md Features #34-37)
                _buildReflectionSection(theme),
              ],
            ),
    );
  }

  /// Build the post-story reflection section
  /// Only shows when:
  /// - Playback has completed
  /// - User has showEverydayReflections enabled
  /// - Reflection has not been dismissed
  Widget _buildReflectionSection(ThemeData theme) {
    if (!_showReflection || _reflectionDismissed) {
      return const SizedBox.shrink();
    }

    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable == null) {
      return const SizedBox.shrink();
    }

    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState == null) {
      return const SizedBox.shrink();
    }

    // Check if reflections are enabled
    if (!appState.userPreferences.showEverydayReflections) {
      return const SizedBox.shrink();
    }

    final isKidMode = appState.userPreferences.kidFriendlyOnly;
    final reflection = _reflectionService.getReflectionForParable(
      parable: playerState.currentParable!,
      isKidMode: isKidMode,
    );

    if (reflection == null) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        const SizedBox(height: 24),
        Card(
          elevation: 2,
          color: theme.colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with expand/collapse and dismiss buttons
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      color: theme.colorScheme.onTertiaryContainer,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A moment to reflect',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Expand/collapse toggle
                    IconButton(
                      icon: Icon(
                        _reflectionExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                      onPressed: () {
                        setState(
                            () => _reflectionExpanded = !_reflectionExpanded);
                      },
                      tooltip: _reflectionExpanded ? 'Collapse' : 'Expand',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 20,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                      onPressed: () {
                        _stopReflectionAudio();
                        setState(() => _reflectionDismissed = true);
                      },
                      tooltip: 'Dismiss',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                // Collapsible content
                if (_reflectionExpanded) ...[
                  const SizedBox(height: 12),

                  // Reflection text
                  Text(
                    reflection.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),

                  // Optional reflection question (not shown in kid mode)
                  if (reflection.question != null && !isKidMode) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.help_outline,
                            size: 18,
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              reflection.question!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onTertiaryContainer,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Audio controls (if pre-generated reflection audio exists)
                  if (_hasReflectionAudio) ...[
                    const SizedBox(height: 16),
                    _buildReflectionAudioControls(theme),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Build audio control buttons for reflection
  Widget _buildReflectionAudioControls(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Play/Stop/Replay button
        if (_isReflectionPlaying)
          OutlinedButton.icon(
            onPressed: _stopReflectionAudio,
            icon: const Icon(Icons.stop, size: 18),
            label: const Text('Stop'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.onTertiaryContainer,
              side: BorderSide(
                color: theme.colorScheme.onTertiaryContainer.withOpacity(0.5),
              ),
            ),
          )
        else if (_reflectionAudioPlayed)
          OutlinedButton.icon(
            onPressed: _replayReflectionAudio,
            icon: const Icon(Icons.replay, size: 18),
            label: const Text('Replay'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.onTertiaryContainer,
              side: BorderSide(
                color: theme.colorScheme.onTertiaryContainer.withOpacity(0.5),
              ),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: _handlePlayReflection,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Hear Reflection'), // ADR-010: User taps to hear
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.onTertiaryContainer,
              side: BorderSide(
                color: theme.colorScheme.onTertiaryContainer.withOpacity(0.5),
              ),
            ),
          ),
      ],
    );
  }

  /// Format duration to MM:SS
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
