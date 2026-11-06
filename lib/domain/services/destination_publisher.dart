import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/services/file_name_sanitizer.dart';

/// A finished, published file (ARCHITECTURE §15.7). The runner stages a
/// download under the staging directory, then a [DestinationPublisher] moves or
/// copies it to its final home and returns this handle.
///
/// Exactly one locator is filled: [filePath] for an app-storage file the app
/// can address directly, or [uri] for a MediaStore/SAF content URI. [displayName]
/// is the safe file name (never a raw title). The value type and its `toString`
/// never leak a query or credential.
class StoredFile {
  const StoredFile({
    required this.displayName,
    this.filePath,
    this.uri,
    this.sizeBytes,
  });

  final String displayName;
  final String? filePath;
  final Uri? uri;
  final int? sizeBytes;

  /// A content locator: the explicit path when present, else the URI.
  String get location => filePath ?? uri?.toString() ?? '';

  @override
  bool operator ==(Object other) =>
      other is StoredFile &&
      other.displayName == displayName &&
      other.filePath == filePath &&
      other.uri == uri &&
      other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(displayName, filePath, uri, sizeBytes);

  // SAF/MediaStore URIs can embed a token on some providers, so only the
  // scheme and display name are shown (AGENTS privacy rules).
  @override
  String toString() =>
      'StoredFile($displayName, ${filePath ?? uri?.scheme ?? "memory"}, '
      '${sizeBytes ?? "?"}B)';
}

/// Moves a finished, staged download to its chosen destination
/// (ARCHITECTURE §15.7). Implementations never overwrite an existing file,
/// never delete anything they did not create, and remove the staged file only
/// after a successful publish — a failure keeps staging so the job can retry.
abstract interface class DestinationPublisher {
  /// Publishes the file at [stagedPath] into [destination] under
  /// [displayName] (a safe name already including its extension). [sizeBytes]
  /// is the staged size, used for free-space checks; a null or unknown size
  /// skips that check. Never throws — failures come back as a typed [Err].
  Future<Result<StoredFile>> publish({
    required DownloadDestination destination,
    required String stagedPath,
    required String displayName,
    int? sizeBytes,
    String? mimeType,
  });
}

/// Staging layout helpers (§15.7): the runner always writes to
/// `<downloadsRoot>/staging/<jobId>/` before anything is published.
abstract final class StagingLayout {
  static String stagingDirectory(String downloadsRoot, String jobId) =>
      p.join(downloadsRoot, 'staging', jobId);

  /// The app-private home an [AppStorageDestination] file lands in — the
  /// downloads root itself, deliberately never under `staging/`.
  static String appStorageHome(String downloadsRoot) => downloadsRoot;
}

/// Reads available bytes at a path. Returns null when the host cannot report
/// free space, which callers treat as "unknown, proceed" rather than a failure.
typedef FreeSpaceProbe = Future<int?> Function(String path);

/// Conservative headroom so a publish never squeezes the volume to zero when
/// the exact staged size is unknown.
const int _unknownSizeHeadroom = 8 << 20; // 8 MiB

/// The [AppStorageDestination] publisher: an atomic rename inside the app's own
/// downloads root, with collision resolution and an optional free-space check.
///
/// The rename is same-volume, so it neither duplicates the bytes nor needs extra
/// space; a [freeSpaceOf] probe is still honoured (used by callers that publish
/// across volumes or want a guard). A probe reporting less room than the file
/// needs yields [LowStorageError] and keeps staging.
class AppStoragePublisher implements DestinationPublisher {
  AppStoragePublisher({required this.downloadsRoot, this.freeSpaceOf});

  final String downloadsRoot;
  final FreeSpaceProbe? freeSpaceOf;

  @override
  Future<Result<StoredFile>> publish({
    required DownloadDestination destination,
    required String stagedPath,
    required String displayName,
    int? sizeBytes,
    String? mimeType,
  }) async {
    if (destination is! AppStorageDestination) {
      // Misrouted: this publisher only owns the app-storage home. The
      // composite dispatcher is responsible for handing other destinations to
      // their own publisher.
      return Result.err(
        DestinationUnavailableError(
          diagnosticMessage:
              'AppStoragePublisher got ${destination.runtimeType}',
        ),
      );
    }

    final staged = File(stagedPath);
    if (!await staged.exists()) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'staged file missing: ${_tail(stagedPath)}',
        ),
      );
    }

    final home = StagingLayout.appStorageHome(downloadsRoot);
    final dir = Directory(home);
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
    } catch (e) {
      return Result.err(
        DestinationUnavailableError(
          diagnosticMessage: 'cannot create app storage home: $e',
        ),
      );
    }

    final size = sizeBytes ?? await _sizeOf(staged);
    final probe = freeSpaceOf;
    if (probe != null) {
      final available = await probe(home);
      if (available != null && available < (size ?? _unknownSizeHeadroom)) {
        return Result.err(
          LowStorageError(
            diagnosticMessage:
                'app storage: need ${size ?? "?"}B, $available available',
          ),
        );
      }
    }

    final taken = <String>{};
    try {
      await for (final entity in dir.list()) {
        taken.add(p.basename(entity.path));
      }
    } catch (e) {
      return Result.err(
        DestinationUnavailableError(
          diagnosticMessage: 'cannot list app storage home: $e',
        ),
      );
    }

    final name = resolveCollision(displayName, taken);
    final destPath = p.join(home, name);

    // Atomic same-volume move first; fall back to copy+delete if the platform
    // refuses a rename (e.g. a future cross-volume app storage layout).
    try {
      await staged.rename(destPath);
    } catch (_) {
      try {
        await staged.copy(destPath);
        await staged.delete();
      } catch (e) {
        // The destination is untouched and staging is kept so the job can retry.
        return Result.err(
          DestinationUnavailableError(
            diagnosticMessage: 'publish to app storage failed: $e',
          ),
        );
      }
    }

    // A successful publish consumes the staged file; tidy the job's own staging
    // directory if it is now empty (never a directory we did not create).
    await _sweepStaging(staged.parent);

    return Result.ok(
      StoredFile(displayName: name, filePath: destPath, sizeBytes: size),
    );
  }

  Future<int?> _sizeOf(File file) async {
    try {
      return await file.length();
    } catch (_) {
      return null;
    }
  }

  Future<void> _sweepStaging(Directory dir) async {
    try {
      if (!await dir.list().any((_) => true)) {
        await dir.delete();
      }
    } catch (_) {
      // Best-effort only; a leftover empty staging dir is reclaimed by the
      // startup sweep in DL4 and must never fail an otherwise-good publish.
    }
  }

  /// Only the final path component is ever surfaced in a diagnostic.
  static String _tail(String path) => p.basename(path);
}
