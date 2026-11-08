import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/domain/models/download_preset.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/features/downloads/download_preset_notifier.dart';
import 'package:mytube/features/downloads/ui/downloads_screen.dart';

/// Settings section for the saved download configuration and the list route.
class DownloadsSettingsSection extends ConsumerWidget {
  const DownloadsSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preset = ref.watch(downloadPresetProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Downloads',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          SwitchListTile(
            title: const Text('Ask before each download'),
            subtitle: const Text(
              'Show the options sheet before every new link.',
            ),
            value: preset.askEveryTime,
            onChanged: (value) => ref
                .read(downloadPresetProvider.notifier)
                .patch((current) => current.copyWith(askEveryTime: value)),
          ),
          ListTile(
            leading: const Icon(Icons.high_quality_outlined),
            title: const Text('Quality'),
            subtitle: Text(
              preset.bestQuality ? 'Best available' : '${preset.maxHeight}p',
            ),
            trailing: DropdownButton<int>(
              value: preset.maxHeight,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Best available')),
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
                    .patch((current) => current.copyWith(maxHeight: value));
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.headphones_outlined),
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
                    .patch((current) => current.copyWith(audioFormat: value));
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Destination'),
            subtitle: Text(_destinationLabel(preset.destination)),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Destination picker coming in DL3/6.'),
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Clipboard detection'),
            subtitle: const Text('Prompt when a new clipboard link appears.'),
            value: preset.clipboardDetect,
            onChanged: (value) => ref
                .read(downloadPresetProvider.notifier)
                .patch((current) => current.copyWith(clipboardDetect: value)),
          ),
          ListTile(
            leading: const Icon(Icons.update_outlined),
            title: const Text('Check for extractor update'),
            subtitle: const Text('Keeps the download engine current.'),
            trailing: Switch(
              value: preset.autoUpdateExtractor,
              onChanged: (value) => ref
                  .read(downloadPresetProvider.notifier)
                  .patch(
                    (current) => current.copyWith(autoUpdateExtractor: value),
                  ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.list_alt_outlined),
            title: const Text('Open downloads list'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'Downloading from third-party sites can breach their terms. You are responsible and cookies can be limited by the site.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  static String _destinationLabel(DownloadDestination destination) {
    return switch (destination) {
      AppStorageDestination() => 'App storage',
      DeviceFolderDestination(:final kind) =>
        kind.name == 'music' ? 'Music' : 'Movies',
      PickedFolderDestination() => 'Picked folder',
      OneDriveDestination() => 'OneDrive (coming soon)',
    };
  }
}
