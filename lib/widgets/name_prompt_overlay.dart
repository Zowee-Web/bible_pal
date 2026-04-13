import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_state_notifier.dart';
import '../providers/service_providers.dart' show nameAudioServiceProvider;
import '../theme/living_sky.dart';

/// SharedPreferences key — prevents re-showing after skip or submit.
const kHasSeenNamePromptKey = 'has_seen_name_prompt';

/// Soft, non-blocking name prompt shown after first story completion.
///
/// Trigger conditions (checked by caller):
/// - playbackCompleted == true
/// - userPreferences.userName is null or empty
/// - kHasSeenNamePromptKey is false
class NamePromptOverlay extends ConsumerStatefulWidget {
  final VoidCallback onDismiss;

  const NamePromptOverlay({super.key, required this.onDismiss});

  /// Check if the name prompt should be shown.
  static Future<bool> shouldShow(String? userName) async {
    if (userName != null && userName.isNotEmpty) return false;
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(kHasSeenNamePromptKey) != true;
  }

  @override
  ConsumerState<NamePromptOverlay> createState() => _NamePromptOverlayState();
}

class _NamePromptOverlayState extends ConsumerState<NamePromptOverlay>
    with SingleTickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));
    _fadeAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeIn,
    );

    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _markSeen() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(kHasSeenNamePromptKey, true);
  }

  Future<void> _handleSubmit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSaving = true);

    final notifier = ref.read(appStateProvider.notifier);
    final currentState = ref.read(appStateProvider).valueOrNull;

    if (currentState != null) {
      final updatedPrefs = currentState.userPreferences.copyWith(
        userName: name,
      );
      await notifier.updateUserPreferences(updatedPrefs);
    }

    await _markSeen();

    // Fire-and-forget name audio generation
    final palVoiceKey =
        currentState?.userPreferences.palVoiceKey ?? 'VOICE_GRACE';
    ref.read(nameAudioServiceProvider).generateNamePhrases(
          name: name,
          voiceKey: palVoiceKey,
        );

    if (!mounted) return;
    _dismiss();
  }

  Future<void> _handleSkip() async {
    await _markSeen();
    if (!mounted) return;
    _dismiss();
  }

  void _dismiss() {
    _slideController.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    final glow = palette.glowIntensity;

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: palette.cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: palette.orbGlowColor.withOpacity(0.3 * glow),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.orbGlowColor.withOpacity(0.1 * glow),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'What should I call you?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleSubmit(),
                  style: TextStyle(color: palette.textColor),
                  decoration: InputDecoration(
                    hintText: 'Your name',
                    hintStyle: TextStyle(
                      color: palette.foreground.tertiaryText,
                    ),
                    filled: true,
                    fillColor: palette.cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: palette.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: palette.cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: palette.warmHighlight.withOpacity(0.5),
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving ? null : _handleSkip,
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: palette.foreground.tertiaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 40,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _handleSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: palette.warmHighlight,
                          foregroundColor: palette.textColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: _isSaving
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: palette.textColor,
                                ),
                              )
                            : const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
