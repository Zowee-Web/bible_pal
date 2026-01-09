import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bible_pal/providers/app_state_notifier.dart';

/// Result returned by VoiceConsentDialog.
enum VoiceConsentResult {
  /// User enabled at least one voice feature
  enabled,

  /// User chose "Text Only" (declined all)
  declined,

  /// User dismissed dialog without choosing
  dismissed,
}

/// Voice Consent Dialog
/// Shows on first attempt to play voice audio (story narration or PAL greetings).
/// Per plan: gate voice audio only (not UI sounds).
///
/// Allows granular consent for:
/// - Story Narration (audio playback of parables)
/// - PAL Greetings (voice greetings - future feature)
class VoiceConsentDialog extends ConsumerStatefulWidget {
  const VoiceConsentDialog({super.key});

  /// Show the voice consent dialog and return the result.
  /// Returns [VoiceConsentResult] indicating what the user chose.
  static Future<VoiceConsentResult> show(BuildContext context) async {
    final result = await showDialog<VoiceConsentResult>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const VoiceConsentDialog(),
    );
    return result ?? VoiceConsentResult.dismissed;
  }

  @override
  ConsumerState<VoiceConsentDialog> createState() => _VoiceConsentDialogState();
}

class _VoiceConsentDialogState extends ConsumerState<VoiceConsentDialog> {
  // Default to OFF - safest interpretation of "explicit consent"
  // User must actively check boxes to enable voice features
  bool _storyNarrationEnabled = false;
  bool _palGreetingsEnabled = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.volume_up,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Voice Features'),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your PAL can speak to you in two ways:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),

            // Story Narration option
            CheckboxListTile(
              value: _storyNarrationEnabled,
              onChanged: (value) {
                setState(() => _storyNarrationEnabled = value ?? false);
              },
              title: const Text('Story Narration'),
              subtitle: const Text('Audio playback of parables'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),

            // PAL Greetings option
            CheckboxListTile(
              value: _palGreetingsEnabled,
              onChanged: (value) {
                setState(() => _palGreetingsEnabled = value ?? false);
              },
              title: const Text('PAL Greetings'),
              subtitle: const Text('"How is your day going?"'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _handleTextOnly(),
          child: const Text('Text Only for Now'),
        ),
        FilledButton(
          onPressed: () => _handleEnableSelected(),
          child: const Text('Enable Selected'),
        ),
      ],
    );
  }

  Future<void> _handleEnableSelected() async {
    final appNotifier = ref.read(appStateProvider.notifier);

    // Save consent with current selections
    await appNotifier.updateVoiceConsent(
      storyNarrationEnabled: _storyNarrationEnabled,
      palGreetingsEnabled: _palGreetingsEnabled,
    );

    if (mounted) {
      final anyEnabled = _storyNarrationEnabled || _palGreetingsEnabled;
      Navigator.of(context).pop(
        anyEnabled ? VoiceConsentResult.enabled : VoiceConsentResult.declined,
      );
    }
  }

  Future<void> _handleTextOnly() async {
    final appNotifier = ref.read(appStateProvider.notifier);

    // Save explicit decline for both features
    await appNotifier.updateVoiceConsent(
      storyNarrationEnabled: false,
      palGreetingsEnabled: false,
    );

    if (mounted) {
      Navigator.of(context).pop(VoiceConsentResult.declined);
    }
  }
}
