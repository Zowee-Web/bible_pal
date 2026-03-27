import 'dart:math';
import 'package:flutter/material.dart';

/// Full-screen Sacred Night background: deep navy gradient + painted star field.
///
/// Uses a fixed random seed so stars are stable across rebuilds.
/// [shouldRepaint] returns false — zero per-frame overhead.
class StarfieldBackground extends StatelessWidget {
  const StarfieldBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _StarfieldPainter(),
      ),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  // Fixed seed → stable star positions across hot-reloads and rebuilds.
  static final _rng = Random(137);

  // Pre-computed star data: (fractional-x, fractional-y, radius, opacity)
  static final List<(double, double, double, double)> _stars = _buildStars();

  static List<(double, double, double, double)> _buildStars() {
    final stars = <(double, double, double, double)>[];
    for (int i = 0; i < 130; i++) {
      final x = _rng.nextDouble();
      final y = _rng.nextDouble();
      // Slightly more tiny stars, a handful of larger bright ones
      final radius = i < 10
          ? 1.2 + _rng.nextDouble() * 0.8   // 10 bright stars: 1.2–2.0px
          : 0.4 + _rng.nextDouble() * 0.8;  // 120 dim stars: 0.4–1.2px
      final opacity = i < 10
          ? 0.55 + _rng.nextDouble() * 0.35 // bright: 0.55–0.90
          : 0.15 + _rng.nextDouble() * 0.40; // dim: 0.15–0.55
      stars.add((x, y, radius, opacity));
    }
    return stars;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ── Background gradient ────────────────────────────────────────────────
    final rect = Offset.zero & size;
    const gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF091422), // deepest at top
        Color(0xFF0D1827), // mid
        Color(0xFF0F1E30), // slight warm blue at bottom
      ],
      stops: [0.0, 0.55, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));

    // ── Stars ──────────────────────────────────────────────────────────────
    final starPaint = Paint()..style = PaintingStyle.fill;
    for (final (fx, fy, radius, opacity) in _stars) {
      starPaint.color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(
        Offset(fx * size.width, fy * size.height),
        radius,
        starPaint,
      );
    }

    // ── Subtle horizon glow (warm gold at very bottom) ─────────────────────
    final glowRect = Rect.fromLTWH(0, size.height * 0.75, size.width, size.height * 0.25);
    const glowGradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        Color(0x14D4AF37), // very faint warm gold
        Color(0x00D4AF37),
      ],
    );
    canvas.drawRect(
      glowRect,
      Paint()..shader = glowGradient.createShader(glowRect),
    );
  }

  @override
  bool shouldRepaint(_StarfieldPainter oldDelegate) => false;
}
