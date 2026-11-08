import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/domain/services/link_extraction.dart';

/// Paste-a-link sheet (DL5.3 / DLK-070). Validates an http(s) URL and returns
/// it; the caller owns the download flow.
class DownloadFromLinkSheet extends StatefulWidget {
  const DownloadFromLinkSheet({super.key, this.initialText});

  final String? initialText;

  @override
  State<DownloadFromLinkSheet> createState() => _DownloadFromLinkSheetState();
}

class _DownloadFromLinkSheetState extends State<DownloadFromLinkSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = WebLink.parse(_controller.text.trim());
    if (parsed == null) {
      setState(() => _error = 'Paste an http:// or https:// link.');
      return;
    }
    Navigator.of(context).pop(parsed.url.toString());
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    setState(() {
      _controller.text = text.trim();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Download from link', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: const ValueKey('download_from_link_field'),
              controller: _controller,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              autofocus: true,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Link',
                hintText: 'https://…',
                border: const OutlineInputBorder(),
                errorText: _error,
                suffixIcon: IconButton(
                  key: const ValueKey('download_from_link_paste'),
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste),
                  onPressed: _paste,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: AppSizes.minTapTarget,
              child: FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> showDownloadFromLinkSheet(
  BuildContext context, {
  String? initialText,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
    ),
    builder: (_) => DownloadFromLinkSheet(initialText: initialText),
  );
}
