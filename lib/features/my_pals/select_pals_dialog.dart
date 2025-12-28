import 'package:flutter/material.dart';
import '../../models/pal.dart';

/// Select PALs Dialog - Multi-select for sharing stories
class SelectPalsDialog extends StatefulWidget {
  final List<PAL> pals;

  const SelectPalsDialog({
    super.key,
    required this.pals,
  });

  @override
  State<SelectPalsDialog> createState() => _SelectPalsDialogState();
}

class _SelectPalsDialogState extends State<SelectPalsDialog> {
  final Set<String> _selectedPalIds = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Share with PALs'),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.pals.isEmpty
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_add_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No PALs yet',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add a PAL first to share stories',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: widget.pals.length,
                itemBuilder: (context, index) {
                  final pal = widget.pals[index];
                  final isSelected = _selectedPalIds.contains(pal.palId);

                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (selected) {
                      setState(() {
                        if (selected == true) {
                          _selectedPalIds.add(pal.palId);
                        } else {
                          _selectedPalIds.remove(pal.palId);
                        }
                      });
                    },
                    title: Text(pal.displayName),
                    subtitle: pal.shareCount > 0
                        ? Text('${pal.shareCount} stories shared')
                        : null,
                    secondary: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        pal.displayName[0].toUpperCase(),
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedPalIds.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selectedPalIds.toList()),
          child: Text(
            _selectedPalIds.isEmpty
                ? 'Share'
                : 'Share with ${_selectedPalIds.length}',
          ),
        ),
      ],
    );
  }
}
