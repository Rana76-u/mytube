import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/theme/theme_mode_notifier.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/util/format_bytes.dart';
import 'package:mytube/domain/models/cache_limit.dart';
import 'package:mytube/domain/services/cache_controller.dart';
import 'package:mytube/domain/services/library_refresh_service.dart';
import 'package:mytube/domain/services/library_refresh_service_provider.dart';
import 'package:mytube/domain/services/scan_settings_notifier.dart';

/// Settings tab — providers, folders, playback preferences, downloads, cache,
/// library controls, and theme selection (NAV-005, SET-001, SET-002).
///
/// Currently hosts the appearance (theme mode) section plus the scan-location
/// section (SET-002 source/folder management): the whole-device MediaStore
/// toggle and the explicit SAF folders the local scan may use.
/// All reads/writes go through [ThemeModeNotifier] and [ScanSettingsNotifier];
/// this widget never touches the database or the platform bridge directly. Each
/// scan-location change is applied immediately via
/// `LibraryRefreshNotifier.rescanAndDeindex()` — invoked from these handlers
/// rather than inside the scan-settings notifier to avoid a circular provider
/// dependency — while a busy indicator runs.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// True while a scope change is being applied: the rescan runs first, then
  /// the de-index sweep, which finishes after the refresh state is idle again.
  bool _busy = false;

  /// Counts whole seconds since the action started so the progress row shows
  /// movement even while a scan takes minutes. Driven by the ticker rather
  /// than a wall clock, which keeps it deterministic in widget tests.
  int _elapsedSeconds = 0;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Starts the progress row and the once-a-second elapsed label.
  void _startBusy() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
    if (!mounted) return;
    setState(() {
      _busy = true;
      _elapsedSeconds = 0;
    });
  }

  /// Clears the progress row. Safe to call after this screen is unmounted.
  void _stopBusy() {
    _ticker?.cancel();
    _ticker = null;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _elapsedSeconds = 0;
    });
  }

  /// Runs one scan-location action, showing the progress row while the
  /// library rescans (errors surface as snackbars via the callers).
  Future<void> _apply(Future<void> Function() action) async {
    _startBusy();
    try {
      await action();
    } finally {
      _stopBusy();
    }
  }

  /// Applies the latest scan-location change: full rescan with the new
  /// scope, then de-index of local entries the scan proved absent.
  Future<void> _rescanAndDeindex() =>
      ref.read(libraryRefreshServiceProvider.notifier).rescanAndDeindex();

  /// Asks the running scan to stop. The sweep still runs afterwards, but a
  /// cancelled merge never marks rows missing, so cancelling de-indexes
  /// nothing beyond what earlier completed scans already proved absent.
  void _cancelScan() {
    ref.read(libraryRefreshServiceProvider.notifier).cancel();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(scanSettingsProvider);
    // Live phase of the running scan (adapter + adapter progress) so the
    // user can tell a slow scan from a stuck one.
    final refreshState = ref.watch(libraryRefreshServiceProvider);
    return ListView(
      children: [
        const _AppearanceSection(),
        const _SettingsSectionHeader('Video scanning'),
        SwitchListTile(
          title: const Text('Scan entire device'),
          subtitle: const Text(
            'Include every video indexed on the device. When off, only '
            'the folders below are scanned.',
          ),
          value: settings.scanEntireDevice,
          onChanged: _busy
              ? null
              : (value) => _apply(() async {
                  await ref
                      .read(scanSettingsProvider.notifier)
                      .setScanEntireDevice(value);
                  await _rescanAndDeindex();
                }),
        ),
        const Divider(height: 1),
        const _SettingsSectionHeader('Scan folders'),
        if (settings.folderUris.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('No folders added yet.'),
          )
        else
          for (final uri in settings.folderUris)
            _FolderTile(
              uri: uri,
              busy: _busy,
              onBusy: (busy) => busy ? _startBusy() : _stopBusy(),
            ),
        ListTile(
          leading: const Icon(Icons.create_new_folder_outlined),
          title: const Text('Add folder'),
          enabled: !_busy,
          onTap: () => _addFolder(),
        ),
        if (_busy)
          _ProgressPanel(
            state: refreshState,
            elapsedSeconds: _elapsedSeconds,
            onCancel: refreshState is RefreshInProgress ? _cancelScan : null,
          )
        else
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'Changing scan locations immediately rescans the library and '
              'removes videos outside the selected locations from the '
              'library. Original files are never modified.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        const Divider(height: 1),
        const _CacheSection(),
      ],
    );
  }

  /// Opens the system folder picker through the notifier seam and reports
  /// the outcome (cancel = silent, error = snackbar with user-safe text).
  /// A successful pick rescans so the folder's videos appear immediately.
  Future<void> _addFolder() async {
    final result = await _runPicker();
    if (!mounted) return;
    switch (result) {
      case Ok(value: null):
        return; // User cancelled the picker.
      case Ok():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Folder added to scan locations.')),
        );
      case Err(:final error):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    }
  }

  Future<Result<String?>> _runPicker() async {
    _startBusy();
    try {
      final picked = await ref.read(scanSettingsProvider.notifier).addFolder();
      // Only a real pick changes the scan scope; cancel/error skip the rescan.
      if (picked case Ok(value: final uri) when uri != null) {
        await _rescanAndDeindex();
      }
      return picked;
    } finally {
      _stopBusy();
    }
  }
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

/// Appearance section — dark / light / follow-system (SET-001).
///
/// The choice is persisted by [ThemeModeNotifier] through the typed
/// preferences DAO, so it survives a restart. This widget only reads the
/// current mode and forwards changes; it never touches storage itself. A
/// dropdown (rather than a segmented control) matches the Cache-limit row and
/// stays within the tile on narrow screens and at large text scales.
class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SettingsSectionHeader('Appearance'),
        ListTile(
          leading: const Icon(Icons.brightness_6_outlined),
          title: const Text('Theme'),
          subtitle: const Text(
            'Dark is the default. Follow device uses your system setting.',
          ),
          trailing: DropdownButton<ThemeMode>(
            key: const ValueKey('settings_theme_mode'),
            value: mode,
            isDense: true,
            items: const [
              DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
            ],
            onChanged: (selected) {
              if (selected == null) return;
              ref.read(themeModeNotifierProvider.notifier).setMode(selected);
            },
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

/// Storage & cache section (CACHE-003/CACHE-004/CACHE-005,
/// P8-02/P8-03/P8-05): how much disposable data the app currently holds, the
/// budget it may occupy, and a scoped way to delete it.
///
/// All cache work goes through [cacheControllerProvider]; this widget never
/// touches the file system or the preferences DAO, and the section states
/// plainly that cached data is separate from downloads and originals
/// (CACHE-006).
class _CacheSection extends ConsumerWidget {
  const _CacheSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(cacheControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SettingsSectionHeader('Storage & cache'),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Cache size'),
          subtitle: Text(_subtitle(cache)),
          trailing: cache.measuring
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Measure cache again',
                  onPressed: () =>
                      ref.read(cacheControllerProvider.notifier).refreshUsage(),
                ),
        ),
        ListTile(
          leading: const Icon(Icons.data_usage_outlined),
          title: const Text('Cache limit'),
          subtitle: const Text('Cached previews are trimmed automatically.'),
          trailing: DropdownButton<CacheLimit>(
            value: cache.limit,
            isDense: true,
            // A persisted value outside the presets is still selectable, so
            // the dropdown never throws on a value it did not offer.
            items: [
              for (final limit in _limitOptions(cache.limit))
                DropdownMenuItem(value: limit, child: Text(limit.label)),
            ],
            onChanged: (limit) {
              if (limit == null) return;
              ref.read(cacheControllerProvider.notifier).setLimit(limit);
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            'Cache holds thumbnails and other temporary data. It is safe to '
            'clear and never contains your downloads or original videos.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('Clear cache'),
          subtitle: const Text(
            'Cached previews only — your downloads and original videos stay.',
          ),
          // Clearing an empty cache is a no-op the user cannot see the result
          // of, so the action only offers itself once something is stored.
          enabled: !cache.measuring && !cache.usage.isEmpty,
          onTap: () => _confirmClear(context, ref),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Confirms, then deletes the disposable cache (CACHE-005/CACHE-006).
  ///
  /// The dialog spells out the scope before anything is removed, and the
  /// outcome is reported as freed bytes or a user-safe error — never as a
  /// silent success when the deletion actually failed.
  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear cache?'),
        content: const Text(
          'Cached previews will be deleted and fetched again when needed. '
          'Your downloads, library, and original videos are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('cache_clear_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref
        .read(cacheControllerProvider.notifier)
        .clearCache();
    if (!context.mounted) return;
    final message = switch (result) {
      Ok(:final value) when value > 0 =>
        'Cache cleared — '
            '${formatBytes(value)} freed.',
      Ok() => 'Nothing to clear.',
      Err(:final error) => error.userMessage,
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// The offered budgets, plus [current] when it is not one of them.
  static List<CacheLimit> _limitOptions(CacheLimit current) {
    final options = [...CacheLimit.presets];
    if (!options.contains(current)) options.add(current);
    options.sort((a, b) => a.bytes.compareTo(b.bytes));
    return options;
  }

  /// `Measuring…` until the first result arrives; otherwise the size and the
  /// number of cached previews, or an explicit empty state.
  static String _subtitle(CacheState cache) {
    if (cache.measuring) return 'Measuring…';
    final entries = cache.usage.entryCount;
    if (entries == 0) return 'Nothing cached yet.';
    final noun = entries == 1 ? 'preview' : 'previews';
    return '${formatBytes(cache.usage.bytes)} · $entries cached $noun';
  }
}

/// One persisted SAF folder row with a remove action that releases the
/// read grant via the notifier and rescans the library.
class _FolderTile extends ConsumerStatefulWidget {
  const _FolderTile({
    required this.uri,
    required this.busy,
    required this.onBusy,
  });

  final String uri;

  /// Whether another scan-location action is already running — gates this
  /// row's remove button while the parent waits on a rescan.
  final bool busy;

  /// Reports this row's own in-flight removal to the parent so the other
  /// controls lock during the rescan.
  final ValueChanged<bool> onBusy;

  @override
  ConsumerState<_FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends ConsumerState<_FolderTile> {
  bool _removing = false;

  Future<void> _remove() async {
    // The parent's busy callback must survive this tile being unmounted: a
    // successful removal takes the tile out of the list mid-flow, so reading
    // `widget` after the await would be too late to release the progress row.
    final onBusy = widget.onBusy;
    setState(() => _removing = true);
    onBusy(true);
    try {
      final result = await ref
          .read(scanSettingsProvider.notifier)
          .removeFolder(widget.uri);
      // A successful release shrinks the scan scope — apply it immediately.
      if (result.isOk) {
        await ref
            .read(libraryRefreshServiceProvider.notifier)
            .rescanAndDeindex();
      }
      if (!mounted) return;
      if (result case Err(:final error)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      }
    } finally {
      onBusy(false);
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: Text(safFolderDisplayName(widget.uri)),
      subtitle: Text(widget.uri, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: _removing
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove folder',
              onPressed: widget.busy ? null : _remove,
            ),
    );
  }
}

/// Progress row shown while a scan-location change is being applied.
///
/// The scanning phase is driven by [RefreshState] (which source is being
/// scanned and how many adapters are done); the de-index sweep that follows
/// has no progress signal, so it shows an indeterminate bar. The elapsed
/// label keeps ticking in both phases, which is what distinguishes a slow
/// scan from a stuck one.
class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({
    required this.state,
    required this.elapsedSeconds,
    this.onCancel,
  });

  final RefreshState state;
  final int elapsedSeconds;
  final VoidCallback? onCancel;

  /// Friendly names for the provider keys reported by the refresh service.
  static const _targets = {
    'localMediaStore': 'device videos',
    'selectedFolder': 'selected folders',
    'directUrl': 'links',
    'oneDrive': 'OneDrive',
    'googleDrive': 'Google Drive',
    'cloudflareR2': 'Cloudflare R2',
  };

  @override
  Widget build(BuildContext context) {
    final progress = switch (state) {
      RefreshInProgress(:final completedAdapters, :final totalAdapters)
          when totalAdapters > 0 =>
        completedAdapters / totalAdapters,
      _ => null,
    };
    final phase = switch (state) {
      RefreshInProgress(
        :final currentAdapter,
        :final completedAdapters,
        :final totalAdapters,
      )
          when totalAdapters > 0 =>
        'Scanning ${_targets[currentAdapter] ?? currentAdapter ?? 'library'}'
            ' (${completedAdapters + 1} of $totalAdapters)…',
      RefreshInProgress() => 'Scanning library…',
      _ => 'Updating library…',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text('$phase  ·  ${elapsedSeconds}s')),
              if (onCancel != null)
                TextButton(onPressed: onCancel, child: const Text('Cancel')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Section header used by the settings list.
class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
