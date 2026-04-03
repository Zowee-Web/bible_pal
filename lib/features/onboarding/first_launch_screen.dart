import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/user_preferences.dart' show currentVoiceConsentVersion;
import '../../providers/app_state_notifier.dart';
import '../../theme/living_sky.dart';
import '../../widgets/living_sky_background.dart';
import '../../widgets/premium_components.dart';

/// Key for tracking first-launch onboarding completion
const kFirstLaunchCompleteKey = 'first_launch_complete';

/// Key for tracking if the PAL intro overlay has been shown (first-launch only)
const kPalIntroShownKey = 'pal_intro_shown';

/// Silent first-launch onboarding screen.
///
/// Flow:
/// 1. Fade in from black → Living Sky appears
/// 2. PAL orb fades in with breathing animation
/// 3. "How are you feeling?" fades in
/// 4. Mood buttons appear with staggered fade-in
/// 5. User taps mood → mark complete → navigate to main menu
///
/// Hard invariants:
/// - NO voice/TTS audio plays during this screen
/// - NO voice consent dialog is shown
/// - NO name input — name is collected post-first-story
class FirstLaunchScreen extends ConsumerStatefulWidget {
  const FirstLaunchScreen({super.key});

  @override
  ConsumerState<FirstLaunchScreen> createState() => _FirstLaunchScreenState();
}

class _FirstLaunchScreenState extends ConsumerState<FirstLaunchScreen>
    with TickerProviderStateMixin {
  // Master fade-in from black
  late final AnimationController _fadeController;

  // Orb appearance
  late final AnimationController _orbFadeController;

  // Orb breathing
  late final AnimationController _breathController;
  late final Animation<double> _breathScale;
  late final Animation<double> _breathGlow;

  // Orb glow pulse cue
  late final AnimationController _orbPulseController;
  late final Animation<double> _orbPulse;

  // Text appearance
  late final AnimationController _textFadeController;

  // Mood button stagger
  late final AnimationController _moodFadeController;

  static const _moods = [
    ('Joyful', 'joyful'),
    ('Grateful', 'grateful'),
    ('Weary', 'weary'),
    ('Anxious', 'anxious'),
    ('Hurting', 'hurting'),
    ('Peaceful', 'calm_peaceful'),
  ];

  @override
  void initState() {
    super.initState();

    // 1. Master fade from black (~1.5s)
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // 2. Orb fade-in (starts after ~1s)
    _orbFadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Orb breathing — continuous
    _breathController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );
    _breathScale = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );
    _breathGlow = Tween<double>(begin: 0.25, end: 0.45).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );

    // Orb glow pulse cue (single stronger pulse)
    _orbPulseController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _orbPulse = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _orbPulseController, curve: Curves.easeInOut),
    );

    // 3. Text fade-in (starts after ~2s)
    _textFadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // 4. Mood buttons stagger (starts after ~3s)
    _moodFadeController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    _startSequence();
  }

  void _startSequence() async {
    // Step 1: Fade in from black
    _fadeController.forward();

    // Step 2: Orb appears after 1s
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    _orbFadeController.forward();
    _breathController.repeat(reverse: true);

    // Step 3: Text appears after 2s
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    _textFadeController.forward();

    // Step 4: Mood buttons appear after 3s
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    _moodFadeController.forward();

    // Step 5: Orb glow pulse cue after buttons are visible
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _orbPulseController.forward().then((_) {
      if (mounted) _orbPulseController.reverse();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _orbFadeController.dispose();
    _breathController.dispose();
    _orbPulseController.dispose();
    _textFadeController.dispose();
    _moodFadeController.dispose();
    super.dispose();
  }

  Future<void> _handleMoodTap(String mood) async {
    // Save onboarding-complete state + consent defaults
    final notifier = ref.read(appStateProvider.notifier);
    final currentState = ref.read(appStateProvider).valueOrNull;

    if (currentState != null) {
      final updatedPrefs = currentState.userPreferences.copyWith(
        hasCompletedOnboarding: true,
        storyNarrationEnabled: true,
        palGreetingsEnabled: true,
        voiceConsentVersion: currentVoiceConsentVersion,
      );
      await notifier.updateUserPreferences(updatedPrefs);
    }

    // Mark first launch complete
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(kFirstLaunchCompleteKey, true);

    // Persist detected mood (guard: state may not be loaded in test)
    if (currentState != null) {
      notifier.updateLastDetectedMood(mood);
    }

    if (!mounted) return;

    // Navigate to main menu — user will start their first story from there
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/main_menu',
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    final glow = palette.glowIntensity;

    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fadeController,
        child: Stack(
          children: [
            const LivingSkyBackground(),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(flex: 2),

                      // PAL orb with breathing + pulse cue
                      FadeTransition(
                        opacity: _orbFadeController,
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_breathScale, _orbPulse]),
                          builder: (context, child) {
                            final scale = _breathScale.value *
                                _orbPulse.value;
                            return Transform.scale(
                              scale: scale,
                              child: child,
                            );
                          },
                          child: AnimatedBuilder(
                            animation: _breathGlow,
                            builder: (context, child) {
                              return Container(
                                width: 160,
                                height: 160,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    center: const Alignment(-0.3, -0.4),
                                    radius: 1.1,
                                    colors: palette.orbGradientColors,
                                    stops: const [0.0, 0.55, 1.0],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: palette.orbGlowColor
                                          .withOpacity(_breathGlow.value * glow),
                                      blurRadius: 32,
                                      spreadRadius: 4,
                                    ),
                                    BoxShadow(
                                      color: palette.orbGlowColor
                                          .withOpacity(_breathGlow.value * 0.4 * glow),
                                      blurRadius: 60,
                                      spreadRadius: 12,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    'PAL',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 36,
                                      letterSpacing: 6,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 48),

                      // "How are you feeling?"
                      FadeTransition(
                        opacity: _textFadeController,
                        child: Text(
                          'How are you feeling?',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: palette.textColor,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Mood buttons with staggered fade
                      FadeTransition(
                        opacity: _moodFadeController,
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: _moods.map((entry) {
                            final (label, moodKey) = entry;
                            return PrimaryGlowButton(
                              label: label,
                              onPressed: () => _handleMoodTap(moodKey),
                            );
                          }).toList(),
                        ),
                      ),

                      const Spacer(flex: 3),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
