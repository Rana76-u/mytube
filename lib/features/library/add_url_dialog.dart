import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/services/direct_url_service.dart';
import 'package:mytube/domain/services/direct_url_service_provider.dart';
import 'package:mytube/sources/direct_url/direct_url_validation.dart';

/// Dialog for entering ONE direct video URL at a time (P4-01, URL-001).
///
/// Validation runs locally first (URL-002), then the server is probed with a
/// hard timeout (P4-02). Definitive rejections (404, expired link, non-video
/// content) keep the dialog open with a clear message; transient probe
/// failures still add the URL so the entry is not lost (URL-003 fallback).
///
/// The dialog pops with a [DirectUrlEntryResult] on success; the caller owns
/// list refresh and feedback.
class AddUrlDialog extends ConsumerStatefulWidget {
  const AddUrlDialog({super.key});

  @override
  ConsumerState<AddUrlDialog> createState() => _AddUrlDialogState();
}

class _AddUrlDialogState extends ConsumerState<AddUrlDialog> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final rawUrl = _controller.text;

    // Instant, offline scheme/syntax feedback (URL-002) before any probing.
    if (validateDirectUrl(rawUrl) case Err(:final error)) {
      setState(() => _errorMessage = error.userMessage);
      return;
    }

    setState(() {
      _errorMessage = null;
      _submitting = true;
    });

    final result = await ref.read(directUrlServiceProvider).addUrl(rawUrl);

    if (!mounted) return;
    switch (result) {
      case Ok<DirectUrlEntryResult>(:final value):
        Navigator.of(context).pop(value);
      case Err<DirectUrlEntryResult>(:final error):
        setState(() {
          _submitting = false;
          _errorMessage = error.userMessage;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Keep the in-flight entry visible while probing; system back must not
      // orphan a submit that is about to mutate the library (URL-001).
      canPop: !_submitting,
      child: AlertDialog(
        title: const Text('Add video URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              enabled: !_submitting,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: _submitting ? null : (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Direct video URL',
                hintText: 'https://example.com/video.mp4',
                border: OutlineInputBorder(),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_submitting) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
