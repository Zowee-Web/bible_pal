import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/living_sky.dart';

/// Show a modal 4-digit PIN pad (SPEC Feature 51.6). Returns the entered
/// 4-digit string, or null if the grown-up cancels. No system keyboard — a
/// custom pad keeps it kid-proof. Auto-submits on the 4th digit.
///
/// [errorText] shows a one-line message under the dots (e.g. after a wrong
/// PIN); the caller re-invokes with it set to retry.
Future<String?> showPinPad(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? errorText,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PinPadSheet(
      title: title,
      subtitle: subtitle,
      errorText: errorText,
    ),
  );
}

class _PinPadSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String? errorText;

  const _PinPadSheet({required this.title, this.subtitle, this.errorText});

  @override
  State<_PinPadSheet> createState() => _PinPadSheetState();
}

class _PinPadSheetState extends State<_PinPadSheet> {
  String _entry = '';

  void _tap(String digit) {
    if (_entry.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() => _entry += digit);
    if (_entry.length == 4) {
      // Let the 4th dot paint before returning.
      final pin = _entry;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(pin);
      });
    }
  }

  void _backspace() {
    if (_entry.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    final fg = palette.foreground;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        decoration: BoxDecoration(
          color: palette.gradientColors.last,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: fg.subtleBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: fg.primaryText,
              ),
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: fg.secondaryText),
              ),
            ],
            const SizedBox(height: 20),
            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < _entry.length;
                return Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? palette.warmHighlight : Colors.transparent,
                    border: Border.all(color: palette.warmHighlight, width: 2),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 18,
              child: widget.errorText != null
                  ? Text(
                      widget.errorText!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFE57373),
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            // Number pad
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [for (final d in row) _key(d, palette)],
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _spacer(),
                _key('0', palette),
                _key(
                  '⌫',
                  palette,
                  onTap: _backspace,
                  isAction: true,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: fg.tertiaryText),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spacer() => const SizedBox(width: 72, height: 72);

  Widget _key(
    String label,
    SkyPalette palette, {
    VoidCallback? onTap,
    bool isAction = false,
  }) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: 72,
        height: 72,
        child: Material(
          color: isAction
              ? Colors.transparent
              : palette.foreground.subtleSurface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap ?? () => _tap(label),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: isAction ? 24 : 26,
                  fontWeight: FontWeight.w500,
                  color: palette.foreground.primaryText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
