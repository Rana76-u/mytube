import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/sources/google_drive/google_drive_providers.dart';

/// Google Drive connection controls; credentials stay in the native sign-in
/// SDK and never enter widget state, preferences, or diagnostics.
class GoogleDriveSettingsSection extends ConsumerStatefulWidget {
  const GoogleDriveSettingsSection({super.key});

  @override
  ConsumerState<GoogleDriveSettingsSection> createState() =>
      _GoogleDriveSettingsSectionState();
}

class _GoogleDriveSettingsSectionState
    extends ConsumerState<GoogleDriveSettingsSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(googleDriveConnectionProvider);
    final (subtitle, connected, error) = switch (connection) {
      AsyncData(value: Ok(value: true)) => (
        'Connected. Your local library entries stay when you disconnect.',
        true,
        null,
      ),
      AsyncData(value: Ok(value: false)) => (
        'Sign in with Google to browse your Google Drive videos.',
        false,
        null,
      ),
      AsyncData(value: Err(error: final error)) => (
        error.userMessage,
        false,
        error,
      ),
      AsyncError(:final error) => (
        'Could not check the Google Drive connection.',
        false,
        UnexpectedError(
          userMessage:
              'Could not check the Google Drive connection. Try again.',
          diagnosticMessage:
              'Google Drive connection status provider failed '
              '(${error.runtimeType})',
        ),
      ),
      _ => ('Checking connection…', false, null),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: const Text('Google Drive'),
          subtitle: Text(subtitle),
          trailing: connection.isLoading || _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : error != null
              ? IconButton(
                  tooltip: 'Retry connection check',
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                )
              : connected
              ? TextButton(
                  onPressed: _disconnect,
                  child: const Text('Disconnect'),
                )
              : FilledButton(onPressed: _connect, child: const Text('Connect')),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'Google Drive access covers all files in the connected account. '
            'Videos can be renamed from Manage sources; deleting originals '
            'is permanent and requires a separate confirmation.',
          ),
        ),
        if (connected)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Disconnecting removes this app’s access only. It does not '
              'delete Drive files or local library data.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    final result = await ref.read(googleDriveAuthServiceProvider).connect();
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(googleDriveConnectionProvider);
    switch (result) {
      case Err(:final error):
        _showMessage(error.userMessage);
      case Ok(value: false):
        break;
      case Ok(value: true):
        _showMessage(
          'Google Drive connected. Refresh the library to list videos.',
        );
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    final result = await ref.read(googleDriveAuthServiceProvider).disconnect();
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(googleDriveConnectionProvider);
    final message = switch (result) {
      Ok() => 'Google Drive disconnected. Library entries were kept.',
      Err(:final error) => error.userMessage,
    };
    _showMessage(message);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _retry() => ref.invalidate(googleDriveConnectionProvider);
}
