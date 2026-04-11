import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/story_length_bucket.dart';
import '../../core/app_logger.dart';
import '../../providers/app_state_notifier.dart';
import '../../providers/parable_player_notifier.dart';
import '../../providers/service_providers.dart';
import '../../theme/living_sky.dart';
import '../../widgets/living_sky_background.dart';
import '../pals_parables/parable_player_screen.dart';

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
  StoryLengthBucket? _selectedBucket;

  Future<void> _pickLength(StoryLengthBucket bucket) async {
    if (_isLoading) return;

    // Visual selection + haptic
    HapticFeedback.lightImpact();
    setState(() => _selectedBucket = bucket);

    // Brief pause to let glow animation show before navigating
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

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
        setState(() {
          _isLoading = false;
          _selectedBucket = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No story available for this mood and length yet.')),
        );
        return;
      }

      await appStateNotifier.addToHistory(parable);
      if (!mounted) return;

      final playerNotifier = ref.read(parablePlayerProvider.notifier);
      final success = await playerNotifier.loadParable(parable);

      if (!mounted) return;

      if (!success) {
        final playerState = ref.read(parablePlayerProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(playerState.errorMessage ??
                'This story needs an internet connection the first time you play it.'),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      // Smooth fade + scale transition into player
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const ParablePlayerScreen(),
          transitionsBuilder: (_, animation, __, child) {
            final curved = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 260),
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _selectedBucket = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                          style: TextStyle(
                            fontSize: 16,
                            color: palette.textColor,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      const Spacer(flex: 2),

                      Text(
                        'How long would you like\nyour story?',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: palette.textColor,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 32),

                      // Three length cards
                      for (final bucket in StoryLengthBucket.values) ...[
                        _LengthCard(
                          bucket: bucket,
                          isSelected: _selectedBucket == bucket,
                          palette: palette,
                          onTap: () => _pickLength(bucket),
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

/// Individual length card with glow + scale on selection.
class _LengthCard extends StatefulWidget {
  final StoryLengthBucket bucket;
  final bool isSelected;
  final SkyPalette palette;
  final VoidCallback onTap;

  const _LengthCard({
    required this.bucket,
    required this.isSelected,
    required this.palette,
    required this.onTap,
  });

  @override
  State<_LengthCard> createState() => _LengthCardState();
}

class _LengthCardState extends State<_LengthCard> {
  bool _pressed = false;

  double get _scale {
    if (_pressed) return 0.97;
    if (widget.isSelected) return 1.03;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final bucket = widget.bucket;
    final isSelected = widget.isSelected;
    final glow = palette.glowIntensity;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: palette.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? palette.orbGlowColor.withOpacity(0.6)
                    : palette.cardBorder,
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: palette.orbGlowColor.withOpacity(0.2 * glow),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  bucket.displayLabel,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: palette.textColor,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  bucket.subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: palette.subtitleColor.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
