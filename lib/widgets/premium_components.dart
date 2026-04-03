import 'package:flutter/material.dart';
import '../theme/living_sky.dart';

// ---------------------------------------------------------------------------
// PrimaryGlowButton — gradient fill, glow shadow, scale on press
// ---------------------------------------------------------------------------

/// Primary action button with phase-aware gradient fill and glow shadow.
class PrimaryGlowButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  const PrimaryGlowButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.padding,
    this.borderRadius = 24,
  });

  @override
  State<PrimaryGlowButton> createState() => _PrimaryGlowButtonState();
}

class _PrimaryGlowButtonState extends State<PrimaryGlowButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 120),
      vsync: this,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    final glow = palette.glowIntensity;

    return GestureDetector(
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onPressed();
      },
      onTapCancel: () => _scaleController.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: child,
          );
        },
        child: Container(
          padding: widget.padding ??
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.orbGlowColor,
                palette.orbGlowColor.withOpacity(0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: [
              BoxShadow(
                color: palette.orbGlowColor.withOpacity(0.3 * glow),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: palette.textColor,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// GlassButton — frosted glass secondary action
// ---------------------------------------------------------------------------

/// Secondary action button with glass/frosted styling.
class GlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;
  final EdgeInsetsGeometry? padding;

  const GlassButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.padding,
  });

  /// Convenience constructor for icon + label buttons.
  factory GlassButton.icon({
    Key? key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return GlassButton(
      key: key,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scale;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 120),
      vsync: this,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());

    return GestureDetector(
      onTapDown: (_) {
        _scaleController.forward();
        setState(() => _pressed = true);
      },
      onTapUp: (_) {
        _scaleController.reverse();
        setState(() => _pressed = false);
        widget.onPressed();
      },
      onTapCancel: () {
        _scaleController.reverse();
        setState(() => _pressed = false);
      },
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: widget.padding ??
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _pressed
                ? palette.orbGlowColor.withOpacity(0.25)
                : palette.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _pressed ? palette.orbGlowColor.withOpacity(0.6) : palette.cardBorder,
              width: 1,
            ),
          ),
          child: DefaultTextStyle(
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: palette.textColor,
            ),
            child: IconTheme(
              data: IconThemeData(color: palette.textColor, size: 16),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// GlassTile — square/rectangular glass card for nav buttons
// ---------------------------------------------------------------------------

/// Navigation tile with glass surface and icon glow.
class GlassTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const GlassTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<GlassTile> createState() => _GlassTileState();
}

class _GlassTileState extends State<GlassTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scale;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 120),
      vsync: this,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    final glow = palette.glowIntensity;

    return GestureDetector(
      onTapDown: (_) {
        _scaleController.forward();
        setState(() => _pressed = true);
      },
      onTapUp: (_) {
        _scaleController.reverse();
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () {
        _scaleController.reverse();
        setState(() => _pressed = false);
      },
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _pressed
                ? palette.orbGlowColor.withOpacity(0.25)
                : palette.cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _pressed ? palette.orbGlowColor.withOpacity(0.6) : palette.cardBorder,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon with subtle glow
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: palette.orbGlowColor.withOpacity(0.2 * glow),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(widget.icon, size: 26, color: palette.orbGlowColor),
              ),
              const SizedBox(height: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.textColor,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// GlassCapsule — pill-shaped glass container for inputs and panels
// ---------------------------------------------------------------------------

/// Pill-shaped glass container with optional glow border.
class GlassCapsule extends StatelessWidget {
  final Widget child;
  final bool glowBorder;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  const GlassCapsule({
    super.key,
    required this.child,
    this.glowBorder = false,
    this.padding,
    this.borderRadius = 24,
  });

  @override
  Widget build(BuildContext context) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    final glow = palette.glowIntensity;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.cardColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: glowBorder
              ? palette.orbGlowColor.withOpacity(0.4 * glow)
              : palette.cardBorder,
          width: glowBorder ? 1.5 : 1,
        ),
        boxShadow: glowBorder
            ? [
                BoxShadow(
                  color: palette.orbGlowColor.withOpacity(0.15 * glow),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// GlowingOrbButton — circular play/action button styled like the PAL orb
// ---------------------------------------------------------------------------

/// Circular action button with radial gradient and glow shadow.
/// Used for the Player screen play/pause control.
class GlowingOrbButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final VoidCallback onPressed;

  const GlowingOrbButton({
    super.key,
    required this.icon,
    this.size = 80,
    required this.onPressed,
  });

  @override
  State<GlowingOrbButton> createState() => _GlowingOrbButtonState();
}

class _GlowingOrbButtonState extends State<GlowingOrbButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 120),
      vsync: this,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    final glow = palette.glowIntensity;

    return GestureDetector(
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onPressed();
      },
      onTapCancel: () => _scaleController.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: child,
          );
        },
        child: Container(
          width: widget.size,
          height: widget.size,
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
                color: palette.orbGlowColor.withOpacity(0.35 * glow),
                blurRadius: 24,
                spreadRadius: 4,
              ),
              BoxShadow(
                color: palette.orbGlowColor.withOpacity(0.15 * glow),
                blurRadius: 48,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Icon(
            widget.icon,
            size: widget.size * 0.45,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
