import 'package:flutter/material.dart';
import '../theme/living_sky.dart';

/// Greeting Display Widget
/// Displays time-appropriate greeting with emoji
/// Based on SPEC.md Feature 2.1
class GreetingDisplay extends StatelessWidget {
  final String greeting;
  final String emoji;

  const GreetingDisplay({
    super.key,
    required this.greeting,
    required this.emoji,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = LivingSky.getPalette(LivingSky.getPhase()).foreground;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Time window emoji
          Text(
            emoji,
            style: const TextStyle(fontSize: 48),
          ),
          const SizedBox(height: 16),

          // Greeting text
          Text(
            greeting,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: fg.primaryText,
              shadows: fg.textShadow,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
