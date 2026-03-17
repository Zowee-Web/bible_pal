import 'package:flutter/material.dart';
import 'package:bible_pal/core/story_length_bucket.dart';

/// Animated radio-style selector for story length buckets.
///
/// Displays three options (Short / Full / Long) with circle indicators
/// and subtle highlight transitions. Only one option is selected at a time.
/// Set [horizontal] to true for a compact row layout.
class StoryLengthRadioSelector extends StatelessWidget {
  final StoryLengthBucket selectedBucket;
  final ValueChanged<StoryLengthBucket> onBucketChanged;
  final bool horizontal;

  const StoryLengthRadioSelector({
    super.key,
    required this.selectedBucket,
    required this.onBucketChanged,
    this.horizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    if (horizontal) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < StoryLengthBucket.values.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _LengthChip(
              bucket: StoryLengthBucket.values[i],
              isSelected: selectedBucket == StoryLengthBucket.values[i],
              onTap: () => onBucketChanged(StoryLengthBucket.values[i]),
            ),
          ],
        ],
      );
    }
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

class _LengthChip extends StatelessWidget {
  final StoryLengthBucket bucket;
  final bool isSelected;
  final VoidCallback onTap;

  static const _duration = Duration(milliseconds: 150);
  static const _shortLabels = {
    StoryLengthBucket.short: 'Short',
    StoryLengthBucket.full: 'Full',
    StoryLengthBucket.long: 'Long',
  };

  const _LengthChip({
    required this.bucket,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      selected: isSelected,
      label: bucket.displayLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: _duration,
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primary.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
            ),
          ),
          child: Text(
            _shortLabels[bucket] ?? bucket.displayLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
