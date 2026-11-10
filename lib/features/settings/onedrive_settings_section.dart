import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/sources/onedrive/onedrive_providers.dart';

/// OneDrive connection controls; provider credentials never enter widget
/// state, preferences, or diagnostics.
class OneDriveSettingsSection extends ConsumerStatefulWidget {
  const OneDriveSettingsSection({super.key});

  @override
  ConsumerState<OneDriveSettingsSection> createState() =>
      _OneDriveSettingsSectionState();
}

class _OneDriveSettingsSectionState
    extends ConsumerState<OneDriveSettingsSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(oneDriveConnectionProvider);
    final (subtitle, connected, error) = switch (connection) {
      AsyncData(value: Ok(value: true)) => (
        'Connected. Your local library entries stay when you disconnect.',
        true,
        null,
      ),
      AsyncData(value: Ok(value: false)) => (
        'Sign in with Microsoft to browse your OneDrive videos.',
        false,
        null,
      ),
      AsyncData(value: Err(error: final error)) => (
        error.userMessage,
        false,
        error,
      ),
      AsyncError(:final error) => (
        'Could not check the OneDrive connection.',
        false,
        UnexpectedError(
          userMessage: 'Could not check the OneDrive connection. Try again.',
          diagnosticMessage:
              'OneDrive connection status provider failed '
              '(${error.runtimeType})',
        ),
      ),
      _ => ('Checking connection…', false, null),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _OneDriveHeader(),
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: const Text('OneDrive'),
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
        if (connected)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Disconnecting removes this app’s access only. It does not '
              'delete OneDrive files or local library data.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    final result = await ref.read(oneDriveAuthServiceProvider).connect();
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(oneDriveConnectionProvider);
    final message = switch (result) {
      Err(:final error) => error.userMessage,
      Ok() => await _connectedMessage(),
    };
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _disconnect() async {
    await _run(
      ref.read(oneDriveAuthServiceProvider).disconnect,
      successMessage: 'OneDrive disconnected. Library entries were kept.',
    );
  }

  Future<String?> _connectedMessage() async {
    final state = await ref.read(oneDriveAuthServiceProvider).isConnected();
    return switch (state) {
      Ok(value: true) =>
        'OneDrive connected. Refresh the library to list videos.',
      Ok() => null,
      Err(:final error) => error.userMessage,
    };
  }

  Future<void> _run(
    Future<Result<void>> Function() action, {
    required String successMessage,
  }) async {
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(oneDriveConnectionProvider);
    final message = switch (result) {
      Ok() => successMessage,
      Err(:final error) => error.userMessage,
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _retry() => ref.invalidate(oneDriveConnectionProvider);
}

class _OneDriveHeader extends StatelessWidget {
  const _OneDriveHeader();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      'Cloud providers',
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
