import 'package:uuid/uuid.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/models/download_preset.dart'
    show DownloadMediaKind;
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/repositories/download_repository.dart'
    show DownloadRecord;
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/destination_publisher.dart'
    show StoredFile;

/// Turns a finished extractor download into a library entry
/// (DL4.4, ARCHITECTURE §15.4 — "Library registration").
///
/// It is the seam between the download pipeline and the video library: given a
/// completed [DownloadRecord], the [StoredFile] the publisher returned and the
/// [DownloadDestination] the file was written to, it applies the §15.4 table —
///
///  * Video to a device folder / picked folder → one logical item whose PRIMARY
///    source is the stored file (`localMediaStore` / `selectedFolder`) with a
///    `webLink` second source carrying the canonical page URL.
///  * Video to app storage → one logical item with a `webLink` source only; the
///    app-private copy is tracked by the download record (ADR-019), so it never
///    becomes a scanned local source.
///  * Audio → no library item at all; the download record is the only entry.
///  * A link already in the library (matched by canonical URL) → REUSE that
///    item and add sources, never a duplicate.
///
/// Invariants (§15.4, AGENTS data integrity):
///  * User metadata (favourites, tags, collections, progress, history) is never
///    touched — a reused item keeps its id, and inserts only create
///    source rows / a brand-new item.
///  * A source is added at most once: an existing row with the same
///    (providerType, sourceUri) is not re-inserted, so a later scan of the same
///    file matches the existing source URI and creates nothing new (proven with
///    the real [ScanMergeService] in tests).
///  * The `webLink` durable identity is the canonical page URL
///    ([DownloadRecord.sourceUri]) — never a stream or signed URL.
///
/// No Flutter, Riverpod or Drift imports: it depends only on the [VideoRepository]
/// contract so it can be tested against the real in-memory repository.
class DownloadLibraryRegistrar {
  DownloadLibraryRegistrar({required VideoRepository repository})
    // ignore: prefer_initializing_formals
    : _repository = repository;

  final VideoRepository _repository;
  static const _uuid = Uuid();

  /// Registers [record]'s published [file] in the library.
  ///
  /// Returns the logical item id on success, or `null` in the registration for
  /// an audio-only download (which creates no item). Propagates a repository
  /// [Err] unchanged; the caller decides how a registration failure affects the
  /// download (a completed download is never reverted by it).
  Future<Result<DownloadRegistration>> register({
    required DownloadRecord record,
    required DownloadDestination destination,
    required StoredFile file,
  }) async {
    // Audio: no library item; the download record is the only entry (§15.4).
    if (record.mediaKind == DownloadMediaKind.audio) {
      return const Ok(
        DownloadRegistration(videoItemId: null, reusedExistingItem: false),
      );
    }

    final canonicalUrl = record.sourceUri;
    if (canonicalUrl.isEmpty) {
      return Result.err(
        const NotFoundError(
          diagnosticMessage: 'registrar: record has no canonical page URL',
        ),
      );
    }

    // A real local/cloud file source only exists when the published handle
    // carries a content/document URI the device scan can match. An app-storage
    // copy (a bare filePath) is tracked by the download record instead, so its
    // item is `webLink`-only (ADR-019).
    final fileProvider = _fileProviderFor(destination, file);
    final fileUri = file.uri?.toString();

    // 1. Reuse an existing item by canonical URL, else create one.
    final webLinkLocations = await _repository.getSourceLocationsByProvider(
      ProviderType.webLink,
    );
    if (webLinkLocations case Err(:final error)) {
      return Result.err(error);
    }
    final existing = (webLinkLocations as Ok<List<SourceLocation>>).value
        .where((l) => l.sourceUri == canonicalUrl)
        .toList(growable: false);

    final now = DateTime.now().millisecondsSinceEpoch;
    final title = _titleFor(record, file);

    String videoItemId;
    bool reused;
    if (existing.isNotEmpty) {
      videoItemId = existing.first.videoItemId;
      reused = true;
    } else {
      videoItemId = _uuid.v4();
      reused = false;
      final inserted = await _repository.insertVideoItem(
        VideoItemInsert(
          id: videoItemId,
          title: title,
          createdAt: now,
          updatedAt: now,
        ),
      );
      if (inserted case Err(:final error)) return Result.err(error);

      // New item: attach the `webLink` source carrying the durable page URL.
      final linkLocation = await _repository.insertSourceLocation(
        SourceLocationInsert(
          id: _uuid.v4(),
          videoItemId: videoItemId,
          providerType: ProviderType.webLink,
          sourceUri: canonicalUrl,
          displayName: title,
          sizeBytes: file.sizeBytes,
          availability: AvailabilityState.available,
          lastCheckedAt: now,
          thumbnailUri: record.thumbnailUri,
          // Without a separate file source the link is the primary location.
          isPrimary: fileProvider == null,
          createdAt: now,
          updatedAt: now,
        ),
      );
      if (linkLocation case Err(:final error)) return Result.err(error);
    }

    // 2. Attach the stored file as a source and make it primary (device /
    //    picked folder). Skipped for an app-storage copy, whose file is tracked
    //    by the download record rather than as a scanned local source.
    if (fileProvider != null && fileUri != null) {
      final locations = await _repository.getSourceLocationsForVideo(
        VideoItemId(videoItemId),
      );
      if (locations case Err(:final error)) return Result.err(error);
      final alreadyHasFile = (locations as Ok<List<SourceLocation>>).value.any(
        (l) => l.providerType == fileProvider && l.sourceUri == fileUri,
      );
      if (!alreadyHasFile) {
        final fileLocation = await _repository.insertSourceLocation(
          SourceLocationInsert(
            id: _uuid.v4(),
            videoItemId: videoItemId,
            providerType: fileProvider,
            sourceUri: fileUri,
            displayName: file.displayName,
            sizeBytes: file.sizeBytes,
            availability: AvailabilityState.available,
            lastCheckedAt: now,
            // The stored file is the item's primary playback location (§15.4).
            isPrimary: false,
            createdAt: now,
            updatedAt: now,
          ),
        );
        if (fileLocation case Err(:final error)) return Result.err(error);
        final primary = await _repository.setPrimarySourceLocation(
          videoItemId: videoItemId,
          locationId: (fileLocation as Ok<String>).value,
        );
        if (primary case Err(:final error)) return Result.err(error);
      }
    }

    return Ok(
      DownloadRegistration(
        videoItemId: videoItemId,
        reusedExistingItem: reused,
      ),
    );
  }

  /// The provider a published file belongs to for library purposes, or `null`
  /// when the file has no scannable local/cloud source (an app-storage copy).
  ///
  /// A device-folder publish that the bridge had to fall back to app storage
  /// returns a [filePath] with no [uri], so [fileProvider] stays `null` and the
  /// item is link-only — matching what a scan would actually find.
  static ProviderType? _fileProviderFor(
    DownloadDestination destination,
    StoredFile file,
  ) {
    if (file.uri == null) return null;
    return switch (destination) {
      DeviceFolderDestination() => ProviderType.localMediaStore,
      PickedFolderDestination() => ProviderType.selectedFolder,
      OneDriveDestination() => ProviderType.oneDrive,
      AppStorageDestination() => null,
    };
  }

  /// The library item's display title: the extractor's human title when the
  /// record carries one, else the published file's safe display name. Never a
  /// raw URL.
  static String _titleFor(DownloadRecord record, StoredFile file) {
    final title = record.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    return file.displayName;
  }
}

/// The outcome of one [DownloadLibraryRegistrar.register] call.
class DownloadRegistration {
  const DownloadRegistration({
    required this.videoItemId,
    required this.reusedExistingItem,
  });

  /// The logical library item the download now belongs to, or `null` when the
  /// download created no item (an audio-only track).
  final String? videoItemId;

  /// Whether an item that already existed (matched by canonical URL) was reused
  /// rather than a fresh one created.
  final bool reusedExistingItem;

  bool get hasLibraryItem => videoItemId != null;
}
