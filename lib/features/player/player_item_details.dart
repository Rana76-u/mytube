import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/util/duration_format.dart';
import 'package:mytube/core/util/format_bytes.dart';
import 'package:mytube/core/util/relative_time.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/library/video_item_card.dart'
    show VideoItemCard;

/// What the player's description card knows beyond the item summary (VP3.3).
///
/// The summary carries title, duration, dimensions, favourite and progress; the
/// file name, size, path label and availability only exist on the source rows,
/// and the tags on the tag link table. Both are read once per item instead of
/// per widget, so the card and the meta line share one round trip.
class PlayerItemDetails {
  const PlayerItemDetails({
    this.locations = const <SourceLocation>[],
    this.tags = const <LibraryTag>[],
  });

  /// Every source location, primary first (the repository's own order).
  final List<SourceLocation> locations;

  /// The tags assigned to the item, by name.
  final List<LibraryTag> tags;

  /// The location the card describes: the primary one when the user picked it,
  /// else the first the repository returned (it orders primary first).
  SourceLocation? get primary {
    if (locations.isEmpty) return null;
    for (final location in locations) {
      if (location.isPrimary) return location;
    }
    return locations.first;
  }

  /// Size of that location, when the provider reported one.
  int? get sizeBytes => primary?.sizeBytes;
}

/// Source locations plus tags for one item (VP3.3).
///
/// Fail-soft by design: a source or tag read that fails simply leaves those
/// fields off the card. The page is already playing the video, so there is
/// nothing for the user to retry — and a half-empty card is not an error state.
final playerItemDetailsProvider =
    FutureProvider.family<PlayerItemDetails, VideoItemId>((ref, id) async {
      final repository = ref.watch(videoRepositoryProvider);
      final locations = switch (await repository.getSourceLocationsForVideo(
        id,
      )) {
        Ok(:final value) => value,
        Err() => const <SourceLocation>[],
      };
      final tags = switch (await repository.getTagsForVideo(id)) {
        Ok(:final value) => value,
        Err() => const <LibraryTag>[],
      };
      return PlayerItemDetails(locations: locations, tags: tags);
    });

/// The `date · source · resolution · size · duration` line under the title
/// (design §4, VP3.3).
///
/// Every optional part is dropped when unknown rather than printed as "null" or
/// "0:00" — a freshly indexed item genuinely has no duration yet. [now] is
/// injectable so the relative date is testable without a clock.
String playerMetaLine(VideoItemSummary item, {int? sizeBytes, DateTime? now}) {
  final parts = <String>[formatRelativeDate(item.createdAt, now: now)];

  final provider = item.primaryProvider;
  if (provider != null) parts.add(VideoItemCard.providerLabel(provider));

  final resolution = resolutionLabel(item.widthPx, item.heightPx);
  if (resolution.isNotEmpty) parts.add(resolution);

  if (sizeBytes != null && sizeBytes > 0) parts.add(formatBytes(sizeBytes));

  final durationMs = item.durationMs;
  if (durationMs != null && durationMs > 0) {
    parts.add(formatDuration(Duration(milliseconds: durationMs)));
  }

  return parts.join(' · ');
}

/// `1920×1080`, or an empty string when either dimension is unknown.
String resolutionLabel(int? widthPx, int? heightPx) {
  if (widthPx == null || heightPx == null) return '';
  if (widthPx <= 0 || heightPx <= 0) return '';
  return '$widthPx×$heightPx';
}

/// The file name and the human location of one source row.
///
/// Built from [SourceLocation.sourceUri] with `Uri.pathSegments`, which drops
/// the query string and fragment: a pre-signed or tokenised URL must never show
/// its signature in the UI (AGENTS privacy rules), so only the host is ever
/// printed for a direct URL.
({String fileName, String locationLabel}) describeSourceLocation(
  SourceLocation location,
) {
  final uri = Uri.tryParse(location.sourceUri);
  final segments =
      uri?.pathSegments.where((segment) => segment.isNotEmpty).toList() ??
      const <String>[];

  final displayName = location.displayName?.trim();
  final fileName = (displayName != null && displayName.isNotEmpty)
      ? displayName
      : (segments.isNotEmpty ? segments.last : 'Unknown file');

  final locationLabel = switch (location.providerType) {
    ProviderType.localMediaStore => 'This device',
    // The folder that holds the file, which is what the user picked in SAF.
    ProviderType.selectedFolder =>
      segments.length > 1 ? segments[segments.length - 2] : 'Selected folder',
    ProviderType.directUrl =>
      (uri?.host.isNotEmpty ?? false) ? uri!.host : 'Direct link',
    ProviderType.oneDrive => 'OneDrive',
    ProviderType.googleDrive => 'Google Drive',
    ProviderType.cloudflareR2 => 'Cloudflare R2',
  };

  return (fileName: fileName, locationLabel: locationLabel);
}

/// A user-safe sentence for a source's reachability (AVAIL-001).
String availabilityLabel(AvailabilityState state) => switch (state) {
  AvailabilityState.available => 'Available',
  AvailabilityState.offline => 'Offline (may still play)',
  AvailabilityState.missing => 'File missing',
  AvailabilityState.expiredLink => 'Link expired',
  AvailabilityState.reconnectRequired => 'Reconnect the account',
  AvailabilityState.permissionRevoked => 'Access revoked',
  AvailabilityState.unsupported => 'Unsupported format',
  AvailabilityState.unknown => 'Not checked yet',
};
