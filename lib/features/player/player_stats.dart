import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/core/util/duration_format.dart';
import 'package:mytube/core/util/format_bytes.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/library/video_item_card.dart'
    show VideoItemCard;
import 'package:mytube/features/player/player_item_details.dart';
import 'package:mytube/features/player/player_settings_rows.dart';
import 'package:mytube/features/player/playback_controls.dart' show formatSpeed;
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';

/// "Stats for nerds" — only facts this app actually holds (VP4.6, design §7).
///
/// The design's list names codec, fps, bitrate and dropped frames. The
/// `video_player` engine reports none of them and the schema does not store
/// them, so this page states that instead of inventing numbers: a stat that
/// cannot be measured is worse than a missing one, because the user cannot tell
/// which is which.
///
/// The pure helpers below are separately testable so the formatting rules (live
/// engine size wins over the scanned dimensions, an unknown duration is not
/// printed as `0:00`) do not need a widget tree.

/// The picture's size, preferring what the engine reports for the media that is
/// playing over what the scan recorded for the library entry.
String? statsResolution({Size? live, int? widthPx, int? heightPx}) {
  if (live != null && !live.isEmpty) {
    return '${live.width.round()}×${live.height.round()}';
  }
  if (widthPx == null || heightPx == null) return null;
  if (widthPx <= 0 || heightPx <= 0) return null;
  return '$widthPx×$heightPx';
}

/// The same size reduced to a ratio, `16:9` / `4:3` / `5:3`.
String? statsAspect({Size? live, int? widthPx, int? heightPx}) {
  final width = _dimension(live?.width, widthPx);
  final height = _dimension(live?.height, heightPx);
  if (width == null || height == null) return null;
  final common = _gcd(width, height);
  return '${width ~/ common}:${height ~/ common}';
}

/// `0:12 / 1:02:03`, or null while the duration is unknown.
String? statsPosition(Duration position, Duration duration) {
  if (duration <= Duration.zero) return null;
  return '${formatDuration(position)} / ${formatDuration(duration)}';
}

/// How much of the timeline is downloaded, as a whole percentage.
String? statsBuffered(Duration buffered, Duration duration) {
  if (duration <= Duration.zero) return null;
  final fraction = (buffered.inMilliseconds / duration.inMilliseconds).clamp(
    0.0,
    1.0,
  );
  return '${(fraction * 100).round()} %';
}

int? _dimension(double? fromLive, int? fromScan) {
  final value = fromLive != null && fromLive > 0 ? fromLive.round() : fromScan;
  if (value == null || value <= 0) return null;
  return value;
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

class PlayerStatsPage extends ConsumerWidget {
  const PlayerStatsPage({super.key, required this.item, required this.onBack});

  /// The video being played: its scanned dimensions and its source rows.
  final VideoItemSummary item;

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    // The details provider is already warm (the metadata panel read it when the
    // page built), so the stats page rides the same round trip.
    final details = ref.watch(playerItemDetailsProvider(item.id)).value;
    final location = details?.primary;
    final sizeBytes = details?.sizeBytes;

    return ValueListenableBuilder<PlaybackState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        final live = state.videoSize;
        final duration = state.duration > Duration.zero
            ? state.duration
            : (item.durationMs == null
                  ? Duration.zero
                  : Duration(milliseconds: item.durationMs!));
        return Column(
          key: const ValueKey('player_settings_page_stats'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsPageHeader(title: 'Stats for nerds', onBack: onBack),
            SettingsStatRow(
              id: 'resolution',
              label: 'Resolution',
              value: statsResolution(
                live: live,
                widthPx: item.widthPx,
                heightPx: item.heightPx,
              ),
            ),
            SettingsStatRow(
              id: 'aspect',
              label: 'Aspect ratio',
              value: statsAspect(
                live: live,
                widthPx: item.widthPx,
                heightPx: item.heightPx,
              ),
            ),
            SettingsStatRow(
              id: 'duration',
              label: 'Duration',
              value: duration > Duration.zero ? formatDuration(duration) : null,
            ),
            SettingsStatRow(
              id: 'position',
              label: 'Position',
              value: statsPosition(state.position, duration),
            ),
            SettingsStatRow(
              id: 'buffered',
              label: 'Buffered',
              value: statsBuffered(state.buffered, duration),
            ),
            SettingsStatRow(
              id: 'speed',
              label: 'Playback speed',
              value: formatSpeed(state.speed),
            ),
            SettingsStatRow(
              id: 'source',
              label: 'Source',
              value: item.primaryProvider == null
                  ? null
                  : VideoItemCard.providerLabel(item.primaryProvider!),
            ),
            SettingsStatRow(
              id: 'file',
              label: 'File',
              value: location == null
                  ? null
                  : describeSourceLocation(location).fileName,
            ),
            SettingsStatRow(
              id: 'size',
              label: 'File size',
              value: (sizeBytes == null || sizeBytes <= 0)
                  ? null
                  : formatBytes(sizeBytes),
            ),
            SettingsStatRow(
              id: 'availability',
              label: 'Availability',
              value: location == null
                  ? null
                  : availabilityLabel(location.availability),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Text(
                'Codec, fps and bitrate are not reported by this engine.',
                key: const ValueKey('player_settings_not_reported'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
