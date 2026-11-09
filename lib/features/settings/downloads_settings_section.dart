import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/download_preset.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/services/download_quality_options.dart';
import 'package:mytube/features/downloads/download_preset_notifier.dart';
import 'package:mytube/features/downloads/ui/downloads_screen.dart';
import 'package:mytube/platform/extractor/extractor_providers.dart';
import 'package:mytube/platform/extractor/media_extractor.dart';

/// Settings section for the saved download configuration and the list route
/// (DL6.4, ARCHITECTURE §15.9).
///
/// Uses [ConsumerStatefulWidget] so it can load the extractor status once in
/// [initState] and hold the update-in-progress flag without rebuilding the
/// whole widget tree on each tick.
class DownloadsSettingsSection extends ConsumerStatefulWidget {
  const DownloadsSettingsSection({super.key});

  @override
  ConsumerState<DownloadsSettingsSection> createState() =>
      _DownloadsSettingsSectionState();
}

class _DownloadsSettingsSectionState
    extends ConsumerState<DownloadsSettingsSection> {
  ExtractorStatus? _extractorStatus;
  bool _updateChecking = false;
  bool _updateAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadExtractorStatus();
  }

  Future<void> _loadExtractorStatus() async {
    final result = await ref.read(mediaExtractorProvider).status();
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        setState(() => _extractorStatus = value);
      case Err():
        setState(
          () => _extractorStatus = const ExtractorStatus(
            state: ExtractorState.unavailable,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final preset = ref.watch(downloadPresetProvider);
    final isAudio = preset.kind == DownloadMediaKind.audio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Top-level label (kept for the settings screen context) ──────
        const _SectionHeader('Downloads'),

        // ── Download defaults ───────────────────────────────────────────
        const _SectionHeader('Download defaults'),
        _askBeforeDownloadTile(preset),
        _typeTile(preset),
        if (!isAudio) _qualityTile(preset),
        if (!isAudio) _containerTile(preset),
        if (!isAudio) _compatModeTile(preset),
        _audioFormatTile(preset),
        _audioBitrateTile(preset),

        const Divider(height: 1),

        // ── Destination ──────────────────────────────────────────────────
        const _SectionHeader('Destination'),
        _destinationTile(preset, context),
        _embedMetadataTile(preset),
        _concurrencyTile(preset),

        const Divider(height: 1),

        // ── Advanced ─────────────────────────────────────────────────────
        const _SectionHeader('Advanced'),
        _clipboardDetectTile(preset),

        const Divider(height: 1),

        // ── Extractor ────────────────────────────────────────────────────
        const _SectionHeader('Extractor'),
        _extractorVersionTile(context),
        _autoUpdateExtractorTile(preset),

        const Divider(height: 1),

        // ── Responsibility notice (DLK-063) ───────────────────────────
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Downloading from third-party sites can breach their terms. You '
            'are responsible. Using your own account cookies can get that '
            'account limited by the site.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        ),

        // ── Open downloads list ──────────────────────────────────────────
        ListTile(
          leading: const Icon(Icons.list_alt_outlined),
          title: const Text('Open downloads list'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()),
          ),
        ),
      ],
    );
  }

  // ── Individual control builders ─────────────────────────────────────────

  Widget _askBeforeDownloadTile(DownloadPreset preset) {
    return SwitchListTile(
      title: const Text('Ask before each download'),
      subtitle: const Text('Show the options sheet before every new link.'),
      value: preset.askEveryTime,
      onChanged: (value) => ref
          .read(downloadPresetProvider.notifier)
          .patch((p) => p.copyWith(askEveryTime: value)),
    );
  }

  Widget _typeTile(DownloadPreset preset) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Expanded(child: Text('Type')),
          SegmentedButton<DownloadMediaKind>(
            segments: const [
              ButtonSegment(
                value: DownloadMediaKind.video,
                label: Text('Video'),
                icon: Icon(Icons.videocam_outlined),
              ),
              ButtonSegment(
                value: DownloadMediaKind.audio,
                label: Text('Audio'),
                icon: Icon(Icons.headphones_outlined),
              ),
            ],
            selected: {preset.kind},
            onSelectionChanged: (selection) => ref
                .read(downloadPresetProvider.notifier)
                .patch((p) => p.copyWith(kind: selection.first)),
          ),
        ],
      ),
    );
  }

  Widget _qualityTile(DownloadPreset preset) {
    return ListTile(
      title: const Text('Quality'),
      subtitle: Text(
        preset.bestQuality ? 'Best available' : '${preset.maxHeight}p',
      ),
      trailing: DropdownButton<int>(
        value: preset.maxHeight,
        items: const [
          DropdownMenuItem(value: 0, child: Text('Best')),
          DropdownMenuItem(value: 360, child: Text('360p')),
          DropdownMenuItem(value: 480, child: Text('480p')),
          DropdownMenuItem(value: 720, child: Text('720p')),
          DropdownMenuItem(value: 1080, child: Text('1080p')),
          DropdownMenuItem(value: 1440, child: Text('1440p')),
          DropdownMenuItem(value: 2160, child: Text('2160p')),
        ],
        onChanged: (value) {
          if (value == null) return;
          ref
              .read(downloadPresetProvider.notifier)
              .patch((p) => p.copyWith(maxHeight: value));
        },
      ),
    );
  }

  Widget _containerTile(DownloadPreset preset) {
    return ListTile(
      title: const Text('Container'),
      trailing: DropdownButton<ContainerPreference>(
        value: preset.container,
        items: const [
          DropdownMenuItem(value: ContainerPreference.mp4, child: Text('MP4')),
          DropdownMenuItem(value: ContainerPreference.mkv, child: Text('MKV')),
          DropdownMenuItem(
            value: ContainerPreference.any,
            child: Text('Any/WebM'),
          ),
        ],
        onChanged: (value) {
          if (value == null) return;
          ref
              .read(downloadPresetProvider.notifier)
              .patch((p) => p.copyWith(container: value));
        },
      ),
    );
  }

  Widget _compatModeTile(DownloadPreset preset) {
    return SwitchListTile(
      title: const Text('Compatibility mode'),
      subtitle: const Text('Prefer H.264+AAC for maximum device compatibility'),
      value: preset.compatMode,
      onChanged: (value) => ref
          .read(downloadPresetProvider.notifier)
          .patch((p) => p.copyWith(compatMode: value)),
    );
  }

  Widget _audioFormatTile(DownloadPreset preset) {
    return ListTile(
      title: const Text('Audio format'),
      trailing: DropdownButton<AudioFormat>(
        value: preset.audioFormat,
        items: AudioFormat.values
            .map(
              (format) => DropdownMenuItem(
                value: format,
                child: Text(format.name.toUpperCase()),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          ref
              .read(downloadPresetProvider.notifier)
              .patch((p) => p.copyWith(audioFormat: value));
        },
      ),
    );
  }

  Widget _audioBitrateTile(DownloadPreset preset) {
    const bitrateOptions = [0, 64, 128, 192, 256, 320];
    final currentValue = bitrateOptions.contains(preset.audioBitrateKbps)
        ? preset.audioBitrateKbps
        : 0;
    return ListTile(
      title: const Text('Audio bitrate'),
      trailing: DropdownButton<int>(
        value: currentValue,
        items: bitrateOptions
            .map(
              (k) => DropdownMenuItem(
                value: k,
                child: Text(k == 0 ? 'Best quality' : '$k kbps'),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          ref
              .read(downloadPresetProvider.notifier)
              .patch((p) => p.copyWith(audioBitrateKbps: value));
        },
      ),
    );
  }

  Widget _destinationTile(DownloadPreset preset, BuildContext context) {
    final destination = preset.destination;
    return ListTile(
      title: const Text('Destination'),
      subtitle: Text(downloadDestinationLabel(destination)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<String>(
            value: _destinationKey(destination),
            items: const [
              DropdownMenuItem(value: 'deviceMovies', child: Text('Movies')),
              DropdownMenuItem(value: 'deviceMusic', child: Text('Music')),
              DropdownMenuItem(value: 'appStorage', child: Text('App storage')),
              DropdownMenuItem(value: 'picked', child: Text('Picked folder')),
              DropdownMenuItem(
                value: 'onedrive',
                enabled: false,
                child: Text('OneDrive (connect first)'),
              ),
            ],
            onChanged: (value) => _selectDestination(value, context),
          ),
          if (destination is PickedFolderDestination)
            IconButton(
              tooltip: 'Change picked folder',
              onPressed: () => _pickDestinationFolder(context),
              icon: const Icon(Icons.folder_open_outlined),
            ),
        ],
      ),
    );
  }

  Future<void> _selectDestination(String? value, BuildContext context) async {
    if (value == null) return;
    switch (value) {
      case 'deviceMovies':
        await ref
            .read(downloadPresetProvider.notifier)
            .patch(
              (p) => p.copyWith(
                destination: const DeviceFolderDestination(
                  DeviceFolderKind.movies,
                ),
              ),
            );
      case 'deviceMusic':
        await ref
            .read(downloadPresetProvider.notifier)
            .patch(
              (p) => p.copyWith(
                destination: const DeviceFolderDestination(
                  DeviceFolderKind.music,
                ),
              ),
            );
      case 'appStorage':
        await ref
            .read(downloadPresetProvider.notifier)
            .patch(
              (p) => p.copyWith(destination: const AppStorageDestination()),
            );
      case 'picked':
        await _pickDestinationFolder(context);
    }
  }

  Future<void> _pickDestinationFolder(BuildContext context) async {
    final result = await ref
        .read(downloadPresetProvider.notifier)
        .pickDestinationFolder();
    if (!context.mounted) return;
    if (result case Err(:final error)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    }
  }

  Widget _concurrencyTile(DownloadPreset preset) {
    return ListTile(
      title: const Text('Concurrency'),
      subtitle: Text('${preset.maxConcurrent} simultaneous downloads'),
      trailing: DropdownButton<int>(
        value: preset.maxConcurrent.clamp(1, 5),
        items: const [
          DropdownMenuItem(value: 1, child: Text('1')),
          DropdownMenuItem(value: 2, child: Text('2')),
          DropdownMenuItem(value: 3, child: Text('3')),
          DropdownMenuItem(value: 4, child: Text('4')),
          DropdownMenuItem(value: 5, child: Text('5')),
        ],
        onChanged: (value) {
          if (value == null) return;
          ref
              .read(downloadPresetProvider.notifier)
              .patch((p) => p.copyWith(maxConcurrent: value));
        },
      ),
    );
  }

  Widget _embedMetadataTile(DownloadPreset preset) {
    return SwitchListTile(
      title: const Text('Embed metadata'),
      subtitle: const Text('Add title and thumbnail where supported.'),
      value: preset.embedMetadata,
      onChanged: (value) => ref
          .read(downloadPresetProvider.notifier)
          .patch((p) => p.copyWith(embedMetadata: value)),
    );
  }

  Widget _clipboardDetectTile(DownloadPreset preset) {
    return SwitchListTile(
      title: const Text('Clipboard detection'),
      subtitle: const Text('Prompt when a new clipboard link appears.'),
      value: preset.clipboardDetect,
      onChanged: (value) => ref
          .read(downloadPresetProvider.notifier)
          .patch((p) => p.copyWith(clipboardDetect: value)),
    );
  }

  Widget _extractorVersionTile(BuildContext context) {
    final status = _extractorStatus;
    final String versionLabel;
    if (status == null) {
      versionLabel = 'Checking\u2026';
    } else if (status.isUnavailable) {
      versionLabel = 'Unavailable';
    } else {
      versionLabel = status.version ?? 'Checking\u2026';
    }

    final Widget trailingWidget;
    if (_updateChecking) {
      trailingWidget = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else {
      trailingWidget = TextButton(
        onPressed: () => _handleExtractorAction(context),
        child: Text(_updateAvailable ? 'Install update' : 'Check for update'),
      );
    }

    return ListTile(
      title: const Text('Extractor version'),
      subtitle: Text(versionLabel),
      trailing: trailingWidget,
    );
  }

  Future<void> _handleExtractorAction(BuildContext context) async {
    setState(() => _updateChecking = true);
    try {
      if (_updateAvailable) {
        // Apply the update
        final result = await ref.read(mediaExtractorProvider).update();
        if (!context.mounted) return;
        switch (result) {
          case Ok(:final value):
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Updated to ${value.latestVersion ?? value.currentVersion}',
                ),
              ),
            );
            setState(() {
              _updateAvailable = false;
              _extractorStatus = ExtractorStatus(
                state: ExtractorState.ready,
                version: value.latestVersion ?? value.currentVersion,
              );
            });
          case Err(:final error):
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.userMessage)));
        }
      } else {
        // Check for update
        final result = await ref.read(mediaExtractorProvider).checkForUpdate();
        if (!context.mounted) return;
        switch (result) {
          case Ok(:final value) when value.isUpToDate:
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Up to date')));
          case Ok(:final value) when value.hasUpdate:
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Update available — tap to install'),
              ),
            );
            setState(() => _updateAvailable = true);
          case Ok(:final value):
            // Applied or failed status from check — treat as up-to-date
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  value.failure?.userMessage ?? 'Check failed. Try again.',
                ),
              ),
            );
          case Err(:final error):
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.userMessage)));
        }
      }
    } finally {
      if (mounted) setState(() => _updateChecking = false);
    }
  }

  Widget _autoUpdateExtractorTile(DownloadPreset preset) {
    return SwitchListTile(
      title: const Text('Auto-update extractor'),
      subtitle: const Text('Automatic weekly check (Wi-Fi only)'),
      value: preset.autoUpdateExtractor,
      onChanged: (value) => ref
          .read(downloadPresetProvider.notifier)
          .patch((p) => p.copyWith(autoUpdateExtractor: value)),
    );
  }

  static String _destinationKey(DownloadDestination destination) =>
      switch (destination) {
        AppStorageDestination() => 'appStorage',
        DeviceFolderDestination(:final kind) =>
          kind == DeviceFolderKind.music ? 'deviceMusic' : 'deviceMovies',
        PickedFolderDestination() => 'picked',
        OneDriveDestination() => 'onedrive',
      };
}

/// Private section header that matches [_SettingsSectionHeader] in
/// `settings_screen.dart`.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

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
