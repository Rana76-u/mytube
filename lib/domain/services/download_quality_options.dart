import 'package:flutter/foundation.dart' show immutable;

import 'package:mytube/core/util/format_bytes.dart';
import 'package:mytube/domain/models/download_preset.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/services/format_selector.dart';

/// One quality row in the download options sheet (DL6.2, DLK-012/014/015).
@immutable
class DownloadQualityOption {
  const DownloadQualityOption({
    required this.maxHeight,
    required this.label,
    this.estimatedBytes,
    this.codecMayNotPlay = false,
  });

  /// `0` is "Best available"; otherwise a height cap in pixels.
  final int maxHeight;
  final String label;
  final int? estimatedBytes;
  final bool codecMayNotPlay;

  /// Estimated size, or "Size unknown" — never presented as exact (DLK-014).
  String get sizeLabel =>
      estimatedBytes == null ? 'Size unknown' : '~${formatBytes(estimatedBytes!)}';

  @override
  bool operator ==(Object other) =>
      other is DownloadQualityOption &&
      other.maxHeight == maxHeight &&
      other.label == label &&
      other.estimatedBytes == estimatedBytes &&
      other.codecMayNotPlay == codecMayNotPlay;

  @override
  int get hashCode =>
      Object.hash(maxHeight, label, estimatedBytes, codecMayNotPlay);
}

/// Builds the quality list: Best available first, then unique heights from
/// [info]. When [info] is missing, falls back to the preset height caps.
List<DownloadQualityOption> downloadQualityOptions({
  WebMediaInfo? info,
  FormatSelector selector = const FormatSelector(),
}) {
  if (info == null) {
    return [
      for (final height in DownloadPreset.heightCaps)
        DownloadQualityOption(
          maxHeight: height,
          label: height == 0 ? 'Best available' : '${height}p',
        ),
    ];
  }

  final heights =
      info.playableFormats
          .where((f) => f.hasVideo && f.height != null)
          .map((f) => f.height!)
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));

  return [
    _optionFor(info, 0, selector),
    for (final height in heights) _optionFor(info, height, selector),
  ];
}

DownloadQualityOption _optionFor(
  WebMediaInfo info,
  int cap,
  FormatSelector selector,
) {
  final label = cap == 0 ? 'Best available' : '${cap}p';
  try {
    final selection = selector.select(
      info,
      DownloadPreset(maxHeight: cap),
    );
    return DownloadQualityOption(
      maxHeight: cap,
      label: label,
      estimatedBytes: selection.estimatedBytes,
      codecMayNotPlay: selection.hasNote(FormatSelectionNote.codecMayNotPlay),
    );
  } catch (_) {
    return DownloadQualityOption(maxHeight: cap, label: label);
  }
}

/// Human destination name. OneDrive stays labelled unavailable until Phase 9.
String downloadDestinationLabel(DownloadDestination destination) {
  return switch (destination) {
    AppStorageDestination() => 'App storage',
    DeviceFolderDestination(:final kind) => switch (kind) {
      DeviceFolderKind.movies => 'Device folder (Movies/MyTube)',
      DeviceFolderKind.music => 'Device folder (Music/MyTube)',
    },
    PickedFolderDestination() => 'Picked folder',
    OneDriveDestination() => 'OneDrive (connect first)',
  };
}
