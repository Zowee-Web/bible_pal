import 'package:flutter/material.dart';
import '../../models/pal.dart';

/// Add PAL Dialog - v1.0 manual entry (invite codes can be added later)
/// Simple name entry for now, generates UUID as palId
class AddPalDialog extends StatefulWidget {
  const AddPalDialog({super.key});

  @override
  State<AddPalDialog> createState() => _AddPalDialogState();
}

class _AddPalDialogState extends State<AddPalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addPal() {
    if (_formKey.currentState!.validate()) {
      final pal = PAL(
        palId: 'pal_${DateTime.now().millisecondsSinceEpoch}',
        displayName: _nameController.text.trim(),
        createdAt: DateTime.now(),
      );
      Navigator.of(context).pop(pal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Add a PAL'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your friend\'s name to add them as a PAL',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g., Sarah, John, Mom',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a name';
                }
                if (value.trim().length < 2) {
                  return 'Name must be at least 2 characters';
                }
                return null;
              },
              onFieldSubmitted: (_) => _addPal(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _addPal,
          child: const Text('Add PAL'),
        ),
      ],
    );
  }
}
