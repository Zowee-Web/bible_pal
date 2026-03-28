import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/story_length_bucket.dart';
import '../../core/app_logger.dart';
import '../../providers/app_state_notifier.dart';
import '../../providers/parable_player_notifier.dart';
import '../../providers/service_providers.dart';
import '../../theme/living_sky.dart';
import '../../widgets/living_sky_background.dart';

/// Full-screen story length picker shown before the audio player.
///
/// Receives a detected mood and optional user text, presents three
/// length options, selects a story, and navigates to the player.
class LengthPickerScreen extends ConsumerStatefulWidget {
  final String mood;
  final String userText;

  const LengthPickerScreen({
    super.key,
    required this.mood,
    this.userText = '',
  });

  @override
  ConsumerState<LengthPickerScreen> createState() => _LengthPickerScreenState();
}

class _LengthPickerScreenState extends ConsumerState<LengthPickerScreen> {
  bool _isLoading = false;

  Future<void> _pickLength(StoryLengthBucket bucket) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final appStateNotifier = ref.read(appStateProvider.notifier);
      ref.read(sessionLengthBucketProvider.notifier).state = bucket;
      await appStateNotifier.updatePreferredLengthBucket(bucket.name);

      logEvent('length_selected', {
        'length_bucket': bucket.name,
        'detected_mood': widget.mood,
      });

      final parable = await appStateNotifier.selectParable(
        mood: widget.mood,
        lengthBucket: bucket,
        userText: widget.userText,
      );

      if (!mounted) return;

      if (parable == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No story available for this mood and length yet.')),
        );
        return;
      }

      await appStateNotifier.addToHistory(parable);
      if (!mounted) return;

      final playerNotifier = ref.read(parablePlayerProvider.notifier);
      await playerNotifier.loadParable(parable);

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/parable_player');
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = LivingSky.getPalette(LivingSky.getPhase());

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          const LivingSkyBackground(),
          SafeArea(
            child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: palette.textColor),
                        const SizedBox(height: 16),
                        Text(
                          'Finding your story...',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      const Spacer(flex: 2),

                      Text(
                        'How long would you like\nyour story?',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 32),

                      // Three length cards
                      for (final bucket in StoryLengthBucket.values) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
                          child: GestureDetector(
                            onTap: () => _pickLength(bucket),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                              decoration: BoxDecoration(
                                color: palette.cardColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: palette.cardBorder, width: 1),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          bucket.displayLabel,
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          bucket.subtitle,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: palette.subtitleColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    bucket.durationLabel,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],

                      const Spacer(flex: 3),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
