import 'package:flutter/material.dart';
import 'package:bible_pal/core/story_length_bucket.dart';

/// Animated radio-style selector for story length buckets.
///
/// Displays three rows (Short / Full / Long) with left-side circle indicators
/// and subtle highlight transitions. Only one option is selected at a time.
class StoryLengthRadioSelector extends StatelessWidget {
  final StoryLengthBucket selectedBucket;
  final ValueChanged<StoryLengthBucket> onBucketChanged;

  const StoryLengthRadioSelector({
    super.key,
    required this.selectedBucket,
    required this.onBucketChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final bucket in StoryLengthBucket.values)
          _LengthRadioRow(
            bucket: bucket,
            isSelected: selectedBucket == bucket,
            onTap: () => onBucketChanged(bucket),
          ),
      ],
    );
  }
}

class _LengthRadioRow extends StatelessWidget {
  final StoryLengthBucket bucket;
  final bool isSelected;
  final VoidCallback onTap;

  static const _duration = Duration(milliseconds: 150);
  static const _curve = Curves.easeOut;

  const _LengthRadioRow({
    required this.bucket,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Semantics(
        selected: isSelected,
        label: bucket.displayLabel,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: AnimatedContainer(
            duration: _duration,
            curve: _curve,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primary.withOpacity(0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary.withOpacity(0.4)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                // Animated circle indicator
                AnimatedContainer(
                  duration: _duration,
                  curve: _curve,
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: AnimatedScale(
                      scale: isSelected ? 1.0 : 0.0,
                      duration: _duration,
                      curve: _curve,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Label
                Text(
                  bucket.displayLabel,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
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
