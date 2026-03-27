import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/user_preferences.dart' show currentVoiceConsentVersion;
import '../../providers/app_state_notifier.dart';
import '../../providers/service_providers.dart' show nameAudioServiceProvider;
import '../../theme/app_theme.dart';
import '../../widgets/starfield_background.dart';

/// Key for tracking first-launch onboarding completion
const kFirstLaunchCompleteKey = 'first_launch_complete';

/// Key for tracking if the PAL intro overlay has been shown (first-launch only)
const kPalIntroShownKey = 'pal_intro_shown';

/// First-launch onboarding screen with silent typing animation.
///
/// Hard invariants:
/// - NO voice/TTS audio plays during this screen
/// - NO voice consent dialog is shown
/// - User is routed to Main Menu after name entry (PAL intro shows there)
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

  static const _introMessage =
      "Hi there! I'm PAL, your Personal Audio Listener. "
      "I'm here to share meaningful stories that speak to your heart. "
      "What's your name?";

  /// Typing speed (ms per character)
  static const _typingDelayMs = 40;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  /// Start the typing animation with fixed interval
  void _startTyping() {
    _typingTimer = Timer.periodic(
      const Duration(milliseconds: _typingDelayMs),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_charIndex >= _introMessage.length) {
          timer.cancel();
          setState(() {
            _typingComplete = true;
          });
          return;
        }

        setState(() {
          _charIndex++;
          _displayedText = _introMessage.substring(0, _charIndex);
        });
      },
    );
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
          // Fresh install: enable voice features by default
          storyNarrationEnabled: true,
          palGreetingsEnabled: true,
          voiceConsentVersion: currentVoiceConsentVersion,
        );
        await notifier.updateUserPreferences(updatedPrefs);
      }

      // Mark first launch complete in SharedPreferences
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(kFirstLaunchCompleteKey, true);

      // Fire-and-forget: generate name audio clips for personalized greetings
      final palVoiceKey = currentState?.userPreferences.palVoiceKey ?? 'VOICE_GRACE';
      ref.read(nameAudioServiceProvider).generateNamePhrases(
            name: name,
            voiceKey: palVoiceKey,
          );

      if (!mounted) return;

      // Navigate to main menu (where PAL intro overlay will show)
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/main_menu',
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
      body: GestureDetector(
        onTap: () {
          if (!_typingComplete) {
            _typingTimer?.cancel();
            setState(() {
              _displayedText = _introMessage;
              _charIndex = _introMessage.length;
              _typingComplete = true;
            });
          }
        },
        child: Stack(
        children: [
          const StarfieldBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 1),

                  // PAL avatar/icon — glowing celestial blue
                  Center(child: Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.glassCard,
                      border: Border.all(color: AppTheme.celestialBlue.withOpacity(0.5), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.celestialBlue.withOpacity(0.3),
                          blurRadius: 28,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.auto_stories,
                      size: 44,
                      color: AppTheme.celestialBlue,
                    ),
                  )),
                  const SizedBox(height: 36),

                  // Typing text display
                  Container(
                    constraints: const BoxConstraints(minHeight: 120),
                    child: Text(
                      _displayedText,
                      style: theme.textTheme.titleLarge?.copyWith(
                        height: 1.6,
                        color: AppTheme.warmIvory,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // Blinking cursor during typing
                  if (!_typingComplete)
                    Text(
                      '▋',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppTheme.celestialBlue,
                      ),
                      textAlign: TextAlign.center,
                    ),

                  const SizedBox(height: 32),

                  // Name input (visible after typing completes)
                  AnimatedOpacity(
                    opacity: _typingComplete ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 400),
                    child: Column(
                      children: [
                        TextField(
                          controller: _nameController,
                          enabled: _typingComplete && !_isSaving,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _handleContinue(),
                          style: const TextStyle(color: AppTheme.warmIvory),
                          decoration: const InputDecoration(
                            labelText: 'Your name',
                            hintText: 'Enter your name',
                            prefixIcon: Icon(Icons.person_outline, color: AppTheme.celestialBlue),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _typingComplete && !_isSaving
                                ? _handleContinue
                                : null,
                            child: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Begin'),
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
        ],
        ),
      ),
    );
  }
}

