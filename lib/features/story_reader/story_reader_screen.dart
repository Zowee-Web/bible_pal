import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bible_pal/providers/parable_player_notifier.dart';
import 'package:bible_pal/core/app_logger.dart';

/// Story Reader Screen — scrollable text-only story display.
///
/// - Shows full story text immediately
/// - Scrollable to read all content
/// - Back button clears player state and returns to main menu
class StoryReaderScreen extends ConsumerWidget {
  const StoryReaderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    logEvent('screen_view', {'screen_name': 'story_reader'});

    final theme = Theme.of(context);
    final playerState = ref.watch(parablePlayerProvider);
    final parable = playerState.currentParable;
    final storyText = playerState.parableText ?? '';

    Future<void> goBack() async {
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(parable?.title ?? 'Story'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: goBack,
          ),
        ),
        body: storyText.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No story text available.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                child: Text(
                  storyText,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.8,
                    fontSize: 17,
                  ),
                ),
              ),
      ),
    );
  }
}
