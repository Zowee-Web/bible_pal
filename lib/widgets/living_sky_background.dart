import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/living_sky.dart';
import 'starfield_background.dart';

/// A dynamic sky background that shifts its gradient and particle overlay
/// based on the current [SkyPhase].
///
/// During the [SkyPhase.night] phase the existing [StarfieldBackground] is
/// layered on top of the gradient. For all other phases, softly drifting
/// particles are rendered via a [CustomPainter].
class LivingSkyBackground extends StatefulWidget {
  /// If non-null, forces the sky to this phase regardless of time.
  /// When null, the phase is auto-detected from the device clock.
  final SkyPhase? phase;

  const LivingSkyBackground({super.key, this.phase});

  @override
  State<LivingSkyBackground> createState() => _LivingSkyBackgroundState();
}

class _LivingSkyBackgroundState extends State<LivingSkyBackground>
    with SingleTickerProviderStateMixin {
  late SkyPhase _phase;
  late AnimationController _particleController;
  Timer? _phaseTimer;

  @override
  void initState() {
    super.initState();
    _phase = widget.phase ?? LivingSky.getPhase();

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Poll every 60 seconds to catch phase transitions while the app is open.
    _phaseTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkPhase();
    });
  }

  @override
  void didUpdateWidget(LivingSkyBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase != oldWidget.phase) {
      setState(() {
        _phase = widget.phase ?? LivingSky.getPhase();
      });
    }
  }

  void _checkPhase() {
    if (widget.phase != null) return; // externally controlled
    final newPhase = LivingSky.getPhase();
    if (newPhase != _phase) {
      setState(() {
        _phase = newPhase;
      });
    }
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = LivingSky.getPalette(_phase);
    final isNight = _phase == SkyPhase.night;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Gradient layer — animates smoothly when the phase changes.
        AnimatedContainer(
          duration: const Duration(seconds: 2),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: palette.gradientColors,
              stops: palette.gradientStops,
            ),
          ),
        ),

        // Overlay: starfield at night, floating particles otherwise.
        AnimatedSwitcher(
          duration: const Duration(seconds: 2),
          child: isNight
              ? const StarfieldBackground(key: ValueKey('stars'))
              : AnimatedBuilder(
                  key: ValueKey('particles-$_phase'),
                  animation: _particleController,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _FloatingParticlesPainter(
                        progress: _particleController.value,
                        particleColor: palette.particleColor,
                        maxOpacity: palette.particleOpacity,
                      ),
                      size: Size.infinite,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Renders ~40 small circles that drift slowly upward, wrapping at the top.
///
/// Uses a fixed random seed (42) so particle positions are stable across
/// rebuilds and hot-reloads.
class _FloatingParticlesPainter extends CustomPainter {
  _FloatingParticlesPainter({
    required this.progress,
    required this.particleColor,
    required this.maxOpacity,
  });

  /// Normalized animation progress in [0, 1).
  final double progress;

  /// Base color for each particle.
  final Color particleColor;

  /// Maximum opacity any particle may have.
  final double maxOpacity;

  // Pre-computed particle data: (x, y, radius, speed, opacityFraction).
  // Static so it survives across painter instances.
  static final List<_Particle> _particles = _buildParticles();

  static List<_Particle> _buildParticles() {
    final rng = Random(42);
    return List.generate(40, (_) {
      return _Particle(
        x: rng.nextDouble(),
        baseY: rng.nextDouble(),
        radius: 1.0 + rng.nextDouble() * 2.0, // 1–3 px
        speed: 0.02 + rng.nextDouble() * 0.06, // 0.02–0.08 per cycle
        opacityFraction: 0.1 + rng.nextDouble() * 0.9, // 0.1–1.0
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in _particles) {
      // Drift upward: subtract speed * progress, wrap via modulo.
      final y = (p.baseY - p.speed * progress) % 1.0;
      final opacity = (p.opacityFraction * maxOpacity).clamp(0.0, 1.0);

      paint.color = particleColor.withOpacity(opacity);
      canvas.drawCircle(
        Offset(p.x * size.width, y * size.height),
        p.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FloatingParticlesPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.particleColor != particleColor ||
        oldDelegate.maxOpacity != maxOpacity;
  }
}

class _Particle {
  final double x;
  final double baseY;
  final double radius;
  final double speed;
  final double opacityFraction;

  const _Particle({
    required this.x,
    required this.baseY,
    required this.radius,
    required this.speed,
    required this.opacityFraction,
  });
}
