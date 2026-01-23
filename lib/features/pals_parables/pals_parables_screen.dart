import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bible_pal/services/greeting_service.dart';
import 'package:bible_pal/services/mood_service.dart';
import 'package:bible_pal/services/verse_service.dart';
import 'package:bible_pal/providers/app_state_notifier.dart';
import 'package:bible_pal/providers/parable_player_notifier.dart';
import 'package:bible_pal/widgets/greeting_display.dart';
import 'package:bible_pal/core/app_logger.dart';
import 'package:bible_pal/core/story_length_bucket.dart';

/// PAL's Parables Screen
/// Based on SPEC.md Features 2, 2.1, 3, 4, 5, 14, 16
/// Complete flow: greeting → mood input → compassionate reply + verse → auto-transition to parable playback
class PalsParablesScreen extends ConsumerStatefulWidget {
  const PalsParablesScreen({super.key});

  @override
  ConsumerState<PalsParablesScreen> createState() => _PalsParablesScreenState();
}

class _PalsParablesScreenState extends ConsumerState<PalsParablesScreen> {
  final TextEditingController _moodController = TextEditingController();
  final GreetingService _greetingService = GreetingService();
  final VerseService _verseService = VerseService();

  String? _greeting;
  String? _emoji;
  String? _compassionateReply;
  MoodResult? _moodResult;
  VerseResponse? _verse;
  bool _isSelectingParable = false;

  @override
  void initState() {
    super.initState();
    _greeting = _greetingService.getGreeting();
    _emoji = _greetingService.getTimeWindowEmoji();

    // Log screen view
    logEvent('screen_view', {'screen_name': 'pals_parables'});
  }

  @override
  void dispose() {
    _moodController.dispose();
    super.dispose();
  }

  /// Handle mood detection, show verse, and display length selection
  Future<void> _handleMoodSubmission() async {
    if (_moodController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please share how you\'re doing')),
      );
      return;
    }

    final moodService = ref.read(appStateProvider.notifier).moodService;
    final result = moodService.detectMood(_moodController.text);
    final reply = moodService.generateCompassionateReply(result);
    final verse = _verseService.getVerseForMood(result.mood);

    setState(() {
      _moodResult = result;
      _compassionateReply = reply;
      _verse = verse;
    });
  }

  /// Handle length bucket selection and parable loading
  Future<void> _handleLengthSelection(StoryLengthBucket lengthBucket) async {
    if (_moodResult == null) {
      debugPrint('No mood result available');
      return;
    }

    // Log length selection (no user text logged!)
    // NOTE: length_bucket is canonical - no minute-based fields in telemetry (INVARIANTS.md)
    logEvent('length_selected', {
      'length_bucket': lengthBucket.name,
      'detected_mood': _moodResult!.mood,
    });

    setState(() => _isSelectingParable = true);

    try {
      final appStateNotifier = ref.read(appStateProvider.notifier);

      // Select parable based on mood, length bucket, and user's text for relatability
      final parable = await appStateNotifier.selectParable(
        mood: _moodResult!.mood,
        lengthBucket: lengthBucket,
        userText: _moodController.text,
      );

      if (!mounted) return;

      if (parable == null) {
        setState(() => _isSelectingParable = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No story available for this mood and length yet.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Add to history
      await appStateNotifier.addToHistory(parable);

      // Load into player
      if (!mounted) return;
      final playerNotifier = ref.read(parablePlayerProvider.notifier);
      await playerNotifier.loadParable(parable);

      if (!mounted) return;
      setState(() => _isSelectingParable = false);

      // Navigate to player screen
      if (!mounted) return;
      Navigator.of(context).pushNamed('/parable_player');
    } catch (e) {
      setState(() => _isSelectingParable = false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading parable: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Build a length selection button
  Widget _buildLengthButton(StoryLengthBucket bucket, ThemeData theme) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          onPressed: () => _handleLengthSelection(bucket),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            backgroundColor: theme.colorScheme.secondary,
            foregroundColor: theme.colorScheme.onSecondary,
          ),
          child: Text(bucket.displayLabel),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PAL\'s Stories'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Greeting Display
          GreetingDisplay(
            greeting: _greeting ?? '',
            emoji: _emoji ?? '✨',
          ),
          const SizedBox(height: 12),

          // Subtitle
          Text(
            'Share how you\'re really doing so PAL can choose a story for your heart.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Mood Input Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _moodController,
                    maxLines: 3,
                    autofocus: false,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'Share how you\'re doing',
                      hintText: 'Type a few words about your day or night...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _compassionateReply != null
                        ? null
                        : _handleMoodSubmission,
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),

          // Compassionate Reply with Verse Section
          if (_compassionateReply != null) ...[
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // PAL's Response Header
                    Row(
                      children: [
                        Icon(
                          Icons.favorite,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'PAL\'s Response',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Compassionate Reply
                    Text(
                      _compassionateReply!,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),

                    // Verse Section
                    if (_verse != null) ...[
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 16),

                      // Verse Reference with Translation Label
                      Text(
                        '${_verse!.reference} (${_verse!.translation})',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Verse Text
                      Text(
                        '"${_verse!.text}"',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Verse Context
                      Text(
                        _verse!.context,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer
                              .withOpacity(0.9),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Length Selection or Loading State
                      if (_isSelectingParable) ...[
                        const Divider(),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Preparing your story...',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        const Divider(),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            'Choose a story length:',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildLengthButton(StoryLengthBucket.short, theme),
                            _buildLengthButton(StoryLengthBucket.full, theme),
                            _buildLengthButton(StoryLengthBucket.long, theme),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
