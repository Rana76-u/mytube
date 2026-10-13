import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

/// Interface for Android MediaStore video discovery (LOCAL-001, PLAT-004).
///
/// The concrete implementation is a Kotlin method-channel bridge (Phase 3,
/// P3-01).  The interface lives in [lib/platform/] so adapters and domain
/// services depend on this contract, not on the native implementation.
///
/// Widgets must never call methods on this bridge directly; use the local
/// source adapter instead.
abstract interface class MediaStoreBridge {
  /// Queries MediaStore for all accessible video items.
  ///
  /// Respects the OS permission level in effect at call time:
  /// - API 24–32: requires READ_EXTERNAL_STORAGE.
  /// - API 33: requires READ_MEDIA_VIDEO.
  /// - API 34+: READ_MEDIA_VIDEO + READ_MEDIA_VISUAL_USER_SELECTED.
  ///
  /// Returns [PermissionDeniedError] if the grant is absent rather than
  /// throwing; callers mark affected sources [AvailabilityState.permissionRevoked].
  Future<Result<List<MediaStoreVideo>>> queryVideos();

  /// Returns the current permission status without triggering a system dialog.
  Future<MediaStorePermissionStatus> checkPermission();

  /// Requests the appropriate video-read permission for the current API level.
  ///
  /// Returns the resulting [MediaStorePermissionStatus].
  Future<MediaStorePermissionStatus> requestPermission();
}

// ---------------------------------------------------------------------------
// Supporting value types
// ---------------------------------------------------------------------------

/// Metadata for a single MediaStore video row.
class MediaStoreVideo {
  const MediaStoreVideo({
    required this.mediaStoreId,
    required this.contentUri,
    required this.displayName,
    this.durationMs,
    this.widthPx,
    this.heightPx,
    this.mimeType,
    this.sizeBytes,
    this.dateAddedSeconds,
    this.dateModifiedSeconds,
    this.availability = AvailabilityState.available,
  });

  /// MediaStore [MediaStore.Video.Media._ID] — stable within a device.
  final String mediaStoreId;

  /// `content://media/external/video/media/<id>` — used for playback and
  /// thumbnail requests.  Never persisted as the durable source identity on
  /// its own; always paired with [mediaStoreId].
  final String contentUri;

  final String displayName;
  final int? durationMs;
  final int? widthPx;
  final int? heightPx;
  final String? mimeType;
  final int? sizeBytes;

  /// Unix timestamp (seconds) from [MediaStore.MediaColumns.DATE_ADDED].
  final int? dateAddedSeconds;

  /// Unix timestamp (seconds) from [MediaStore.MediaColumns.DATE_MODIFIED].
  final int? dateModifiedSeconds;

  final AvailabilityState availability;
}

/// Current state of the MediaStore video-read permission.
enum MediaStorePermissionStatus {
  /// Full access granted.
  granted,

  /// API 34+ partial access (READ_MEDIA_VISUAL_USER_SELECTED); the user
  /// selected specific items rather than granting broad access.
  partiallyGranted,

  /// Permission has been denied; can still request again unless permanently
  /// denied.
  denied,

  /// Permanently denied (user chose "Don't ask again"); must open Settings.
  permanentlyDenied,
}

// Keep the unused import lint quiet until Phase 3 implementations arrive.
// ignore: unused_element
ProviderType _unusedProviderRef() => ProviderType.localMediaStore;
