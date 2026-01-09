import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/app_state_notifier.dart';

/// Key for tracking first-launch onboarding completion
const kFirstLaunchCompleteKey = 'first_launch_complete';

/// First-launch onboarding screen with silent typing animation.
///
/// Hard invariants:
/// - NO audio plays during this screen
/// - NO voice consent dialog is shown
/// - User is routed directly to PAL's Stories after name entry
class FirstLaunchScreen extends ConsumerStatefulWidget {
  const FirstLaunchScreen({super.key});

  @override
  ConsumerState<FirstLaunchScreen> createState() => _FirstLaunchScreenState();
}

class _FirstLaunchScreenState extends ConsumerState<FirstLaunchScreen> {
  final TextEditingController _nameController = TextEditingController();

  // Typing animation state
  String _displayedText = '';
  int _charIndex = 0;
  Timer? _typingTimer;
  bool _typingComplete = false;
  bool _isSaving = false;

  static const _introMessage = "Hi there! I'm PAL, your Personal Audio Listener. "
      "I'm here to share meaningful stories that speak to your heart. "
      "What's your name?";

  @override
  void initState() {
    super.initState();
    _startTypingAnimation();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  void _startTypingAnimation() {
    _typingTimer = Timer.periodic(const Duration(milliseconds: 35), (timer) {
      if (_charIndex < _introMessage.length) {
        setState(() {
          _charIndex++;
          _displayedText = _introMessage.substring(0, _charIndex);
        });
      } else {
        timer.cancel();
        setState(() {
          _typingComplete = true;
        });
      }
    });
  }

  Future<void> _handleContinue() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Save user name and mark onboarding complete
      final notifier = ref.read(appStateProvider.notifier);
      final currentState = ref.read(appStateProvider).valueOrNull;

      if (currentState != null) {
        final updatedPrefs = currentState.userPreferences.copyWith(
          userName: name,
          hasCompletedOnboarding: true,
        );
        await notifier.updateUserPreferences(updatedPrefs);
      }

      // Mark first launch complete in SharedPreferences
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(kFirstLaunchCompleteKey, true);

      if (!mounted) return;

      // Navigate to PAL's Stories screen
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/pals_parables',
        (_) => false,
      );
    } catch (e) {
      setState(() => _isSaving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 1),

              // PAL avatar/icon
              Icon(
                Icons.auto_stories,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 32),

              // Typing text display
              Container(
                constraints: const BoxConstraints(minHeight: 120),
                child: Text(
                  _displayedText,
                  style: theme.textTheme.titleLarge?.copyWith(
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              // Blinking cursor during typing
              if (!_typingComplete)
                Text(
                  '▋',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),

              const SizedBox(height: 32),

              // Name input (visible after typing completes)
              AnimatedOpacity(
                opacity: _typingComplete ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      enabled: _typingComplete && !_isSaving,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _handleContinue(),
                      decoration: InputDecoration(
                        labelText: 'Your name',
                        hintText: 'Enter your name',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.person_outline),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _typingComplete && !_isSaving
                            ? _handleContinue
                            : null,
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Continue'),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
