import 'package:flutter/material.dart';

import '../theme/living_sky.dart';

/// Shared InputDecoration builder for the "glass" text inputs used in
/// Bible PAL — the Mood (Study page) text field and the PALs Paths
/// search field (SPEC Feature 48 page 2: "Bottom-anchored search input
/// matching the Mood page input style").
///
/// This helper is the single source of truth for:
/// - Container shape: rounded rect with 24px radius
/// - Border: 1.5px `palette.cardBorder` (enabled), 1.5px
///   `palette.warmHighlight @ 50%` (focused)
/// - Fill: `palette.cardColor`
/// - Content padding: 20px horizontal, 16px vertical
/// - Hint style: `palette.foreground.tertiaryText` with adjustable
///   alpha (lets the Mood input's cycling-hint animation modulate
///   opacity without rebuilding the decoration structure)
///
/// Callers provide the hint text and optional prefix/suffix icons.
/// Text style (color, font size, height) is set on the TextField itself,
/// not the decoration — callers keep that control.
InputDecoration glassInputDecoration({
  required SkyPalette palette,
  required String hintText,
  double hintAlpha = 1.0,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(
      color: palette.foreground.tertiaryText.withValues(alpha: hintAlpha),
      fontSize: 17,
      height: 1.4,
    ),
    filled: true,
    fillColor: palette.cardColor,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(color: palette.cardBorder, width: 1.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(color: palette.cardBorder, width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(
        color: palette.warmHighlight.withOpacity(0.5),
        width: 1.5,
      ),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
  );
}

/// Default text style for content inside a glass input. Matches the
/// Mood input exactly. Routes through the locked foreground palette
/// (SPEC Feature 47) so user-typed content always hits the primary
/// text color regardless of sky phase.
TextStyle glassInputTextStyle(SkyPalette palette) {
  return TextStyle(
    color: palette.foreground.primaryText,
    fontSize: 17,
    height: 1.4,
  );
}
