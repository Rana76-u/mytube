import 'package:flutter/material.dart';

/// Prompts for a single line of text in a dialog and returns it, or `null` if
/// cancelled. Used by the Saved screens to name and rename collections
/// (P5-07).
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  String label = 'Name',
  String? initial,
  String confirmLabel = 'Save',
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _TextPromptDialog(
      title: title,
      label: label,
      initial: initial,
      confirmLabel: confirmLabel,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.confirmLabel,
  });

  final String title;
  final String label;
  final String? initial;
  final String confirmLabel;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('text_prompt_field'),
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('text_prompt_confirm'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
