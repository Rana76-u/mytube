import 'package:flutter/material.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/core/ui/pressable.dart';
import 'package:mytube/domain/models/download_preset.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/services/download_list_presentation.dart';
import 'package:mytube/domain/services/download_quality_options.dart';

/// Result of confirming the options sheet.
class DownloadOptionsResult {
  const DownloadOptionsResult({
    required this.preset,
    required this.saveForNextTime,
  });

  final DownloadPreset preset;
  final bool saveForNextTime;
}

/// Options sheet for a web-link download (DL6.2, DESIGN.md §5).
class DownloadOptionsSheet extends StatefulWidget {
  const DownloadOptionsSheet({
    super.key,
    this.title = 'Title',
    this.uploader,
    this.duration,
    this.thumbnailUrl,
    this.info,
    this.initialPreset,
    this.onDownload,
    this.onPresetChanged,
    this.onPickFolder,
  });

  final String title;
  final String? uploader;
  final Duration? duration;
  final String? thumbnailUrl;
  final WebMediaInfo? info;
  final DownloadPreset? initialPreset;
  final ValueChanged<DownloadOptionsResult>? onDownload;
  final ValueChanged<DownloadPreset>? onPresetChanged;

  /// Opens the SAF picker; return a tree URI or null if cancelled.
  final Future<Uri?> Function()? onPickFolder;

  @override
  State<DownloadOptionsSheet> createState() => _DownloadOptionsSheetState();
}

class _DownloadOptionsSheetState extends State<DownloadOptionsSheet> {
  late DownloadPreset _preset = widget.initialPreset ?? DownloadPreset.defaults;
  bool _savePreference = false;

  WebMediaInfo? get _info => widget.info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final durationText = widget.duration == null
        ? 'Unknown length'
        : formatDurationClock(widget.duration!);
    final uploader = widget.uploader ?? 'Unknown uploader';
    final qualityOptions = downloadQualityOptions(info: _info);

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              children: [
                _Header(
                  title: widget.title,
                  subtitle: '$uploader • $durationText',
                  thumbnailUrl: widget.thumbnailUrl,
                  duration: widget.duration,
                ),
                const SizedBox(height: AppSpacing.lg),
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
                  selected: {_preset.kind},
                  onSelectionChanged: (selection) {
                    _update(_preset.copyWith(kind: selection.first));
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_preset.kind == DownloadMediaKind.video)
                  _qualitySection(theme, qualityOptions)
                else
                  _audioSection(),
                const SizedBox(height: AppSpacing.lg),
                _destinationRow(),
                CheckboxListTile(
                  value: _savePreference,
                  onChanged: (value) =>
                      setState(() => _savePreference = value ?? false),
                  title: const Text('Use these settings next time'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: PressableScale(
                haptic: PressHaptic.light,
                child: SizedBox(
                  width: double.infinity,
                  height: AppSizes.minTapTarget,
                  child: FilledButton.icon(
                    onPressed: () {
                      final result = DownloadOptionsResult(
                        preset: _preset,
                        saveForNextTime: _savePreference,
                      );
                      final callback = widget.onDownload;
                      if (callback != null) {
                        callback(result);
                      } else {
                        Navigator.of(context).pop(result);
                      }
                    },
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Download'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _update(DownloadPreset next) {
    setState(() => _preset = next);
    widget.onPresetChanged?.call(next);
  }

  Widget _qualitySection(
    ThemeData theme,
    List<DownloadQualityOption> options,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quality', style: theme.textTheme.titleSmall),
        for (final option in options)
          RadioListTile<int>(
            value: option.maxHeight,
            groupValue: _preset.maxHeight,
            title: Text(option.label),
            subtitle: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: option.sizeLabel),
                  if (option.codecMayNotPlay)
                    TextSpan(
                      text: '\nMay not play on this device',
                      style: TextStyle(color: theme.colorScheme.secondary),
                    ),
                ],
              ),
            ),
            onChanged: (value) {
              if (value == null) return;
              _update(_preset.copyWith(maxHeight: value));
            },
          ),
      ],
    );
  }

  Widget _audioSection() {
    const bitrateOptions = [0, 64, 128, 192, 256, 320];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Audio output', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<AudioFormat>(
          value: _preset.audioFormat,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            labelText: 'Format',
          ),
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
            _update(_preset.copyWith(audioFormat: value));
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<int>(
          value: bitrateOptions.contains(_preset.audioBitrateKbps)
              ? _preset.audioBitrateKbps
              : 0,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            labelText: 'Bitrate',
          ),
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
            _update(_preset.copyWith(audioBitrateKbps: value));
          },
        ),
      ],
    );
  }

  Widget _destinationRow() {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Destination'),
      subtitle: Text(downloadDestinationLabel(_preset.destination)),
      trailing: DropdownButton<String>(
        value: _kindOf(_preset.destination),
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
        onChanged: (value) async {
          if (value == null) return;
          switch (value) {
            case 'deviceMovies':
              _update(
                _preset.copyWith(
                  destination: const DeviceFolderDestination(
                    DeviceFolderKind.movies,
                  ),
                ),
              );
            case 'deviceMusic':
              _update(
                _preset.copyWith(
                  destination: const DeviceFolderDestination(
                    DeviceFolderKind.music,
                  ),
                ),
              );
            case 'appStorage':
              _update(
                _preset.copyWith(destination: const AppStorageDestination()),
              );
            case 'picked':
              final uri = await widget.onPickFolder?.call();
              if (uri == null) return;
              _update(
                _preset.copyWith(destination: PickedFolderDestination(uri)),
              );
          }
        },
      ),
    );
  }

  static String _kindOf(DownloadDestination destination) =>
      switch (destination) {
        AppStorageDestination() => 'appStorage',
        DeviceFolderDestination(:final kind) =>
          kind == DeviceFolderKind.music ? 'deviceMusic' : 'deviceMovies',
        PickedFolderDestination() => 'picked',
        OneDriveDestination() => 'onedrive',
      };
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    this.thumbnailUrl,
    this.duration,
  });

  final String title;
  final String subtitle;
  final String? thumbnailUrl;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: _Thumb(url: thumbnailUrl),
              ),
              if (duration != null)
                Positioned(
                  right: AppSpacing.sm,
                  bottom: AppSpacing.sm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.inverseSurface.withValues(
                        alpha: 0.82,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.badge),
                    ),
                    child: Text(
                      formatDurationClock(duration!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onInverseSurface,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.videocam_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

Future<DownloadOptionsResult?> showDownloadOptionsSheet(
  BuildContext context, {
  String title = 'Title',
  String? uploader,
  Duration? duration,
  String? thumbnailUrl,
  WebMediaInfo? info,
  DownloadPreset? initialPreset,
  ValueChanged<DownloadOptionsResult>? onDownload,
  ValueChanged<DownloadPreset>? onPresetChanged,
  Future<Uri?> Function()? onPickFolder,
}) {
  return showModalBottomSheet<DownloadOptionsResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
    ),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: DownloadOptionsSheet(
        title: title,
        uploader: uploader,
        duration: duration,
        thumbnailUrl: thumbnailUrl,
        info: info,
        initialPreset: initialPreset,
        onDownload: onDownload,
        onPresetChanged: onPresetChanged,
        onPickFolder: onPickFolder,
      ),
    ),
  );
}
