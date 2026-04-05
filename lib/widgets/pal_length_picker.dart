import 'package:flutter/material.dart';
import 'package:bible_pal/core/story_length_bucket.dart';

/// PAL-style conversational length picker.
/// Shows "I have a story for you." with three tappable length options.
/// Returns the selected StoryLengthBucket, or null if dismissed.
Future<StoryLengthBucket?> showPalLengthPicker(
  BuildContext context, {
  StoryLengthBucket? savedPreference,
}) {
  return showModalBottomSheet<StoryLengthBucket>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _PalLengthPickerSheet(savedPreference: savedPreference),
  );
}

class _PalLengthPickerSheet extends StatelessWidget {
  final StoryLengthBucket? savedPreference;

  const _PalLengthPickerSheet({this.savedPreference});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 16 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // PAL message
          Text(
            'I have a story for you.',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 20),

          // Length options
          for (final bucket in StoryLengthBucket.values) ...[
            _LengthOption(
              bucket: bucket,
              isPreferred: bucket == savedPreference,
              onTap: () => Navigator.of(context).pop(bucket),
            ),
            if (bucket != StoryLengthBucket.long) const SizedBox(height: 8),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _LengthOption extends StatelessWidget {
  final StoryLengthBucket bucket;
  final bool isPreferred;
  final VoidCallback onTap;

  const _LengthOption({
    required this.bucket,
    required this.isPreferred,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: isPreferred
          ? theme.colorScheme.primary.withOpacity(0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPreferred
                  ? theme.colorScheme.primary.withOpacity(0.4)
                  : theme.colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bucket.displayLabel,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight:
                            isPreferred ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bucket.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
