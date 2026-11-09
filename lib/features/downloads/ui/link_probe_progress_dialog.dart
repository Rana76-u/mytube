import 'package:flutter/material.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/web_media.dart';

/// Visible, cancellable state while the extractor fetches link metadata.
class LinkProbeProgressDialog extends StatefulWidget {
  const LinkProbeProgressDialog({
    super.key,
    required this.host,
    required this.probe,
    required this.onCancel,
  });

  final String host;
  final Future<Result<WebMediaInfo>> probe;
  final VoidCallback onCancel;

  @override
  State<LinkProbeProgressDialog> createState() =>
      _LinkProbeProgressDialogState();
}

class _LinkProbeProgressDialogState extends State<LinkProbeProgressDialog> {
  @override
  void initState() {
    super.initState();
    _finishProbe();
  }

  Future<void> _finishProbe() async {
    Result<WebMediaInfo> result;
    try {
      result = await widget.probe;
    } on Object catch (error) {
      result = Result.err(
        UnexpectedError(
          diagnosticMessage: 'link probe threw ${error.runtimeType}',
        ),
      );
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('link_probe_progress_dialog'),
    title: const Text('Checking link'),
    content: Row(
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            'Getting video details from ${widget.host}. '
            'This is not the download yet.',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
    ],
  );
}
