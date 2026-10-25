import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';

/// The two app-owned storage roots, kept deliberately far apart
/// (ARCHITECTURE §10, P8-01).
///
/// * [cacheRoot] — disposable data only (thumbnails, remote previews). The OS
///   may delete it at any time and the app may clear it wholesale (CACHE-005).
/// * [downloadsRoot] — explicit, user-requested app-managed copies. Never
///   touched by cache measurement, eviction, or Clear Cache (CACHE-006,
///   DL-001); Phase 12 will write here.
///
/// Everything the app writes into disposable storage goes through
/// [cacheRoot]; nothing outside it is ever eligible for eviction, so an
/// original video, an offline download, or a library file can never be
/// deleted by cache cleanup even if a future path bug points at the wrong
/// place ([isSeparated] is checked when the roots are resolved).
class StorageRoots {
  StorageRoots({required String cacheRoot, required String downloadsRoot})
    : cacheRoot = p.normalize(cacheRoot),
      downloadsRoot = p.normalize(downloadsRoot);

  /// Root of all disposable cache data.
  final String cacheRoot;

  /// Root of app-managed offline downloads (unused until Phase 12).
  final String downloadsRoot;

  /// True when neither root lives inside the other, so cache cleanup can
  /// never reach a download and a download can never shadow a cache entry.
  bool get isSeparated =>
      !_isWithinOrEqual(cacheRoot, downloadsRoot) &&
      !_isWithinOrEqual(downloadsRoot, cacheRoot);

  /// True when [path] is [cacheRoot] itself or a descendant of it.
  bool isInCache(String path) => _isWithinOrEqual(path, cacheRoot);

  /// True when [path] is [downloadsRoot] itself or a descendant of it.
  bool isInDownloads(String path) => _isWithinOrEqual(path, downloadsRoot);

  /// True when [child] is [parent] or lives underneath it.
  static bool _isWithinOrEqual(String child, String parent) {
    final normalized = p.normalize(child);
    if (p.equals(normalized, parent)) return true;
    return p.isWithin(parent, normalized);
  }

  @override
  String toString() =>
      'StorageRoots(cache: $cacheRoot, downloads: $downloadsRoot)';
}

/// Resolves the app's storage roots for the current host (P8-01).
///
/// The concrete implementation asks the platform for the OS cache directory
/// and the app-private support directory; tests and non-Android hosts override
/// the provider with a fake.
abstract interface class StoragePaths {
  /// Returns the resolved roots, or an [Err] when the platform cannot provide
  /// usable, separated directories. Never throws.
  Future<Result<StorageRoots>> resolve();
}

/// [StoragePaths] backed by `path_provider` (P8-01).
///
/// Cache lives under the OS temporary/cache directory — the OS may reclaim it
/// — while downloads live under the app support directory, which the OS does
/// not treat as disposable. Both are app-private; the separation is structural
/// rather than by naming convention alone, and is verified before use.
///
/// The directory lookups are injectable so tests can simulate an unusable or
/// overlapping layout without a device.
class PathProviderStoragePaths implements StoragePaths {
  PathProviderStoragePaths({
    Future<Directory> Function()? cacheDirectory,
    Future<Directory> Function()? supportDirectory,
  }) : _cacheDirectory = cacheDirectory ?? getTemporaryDirectory,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _cacheDirectory;
  final Future<Directory> Function() _supportDirectory;

  /// Subdirectory created inside the OS cache directory.
  static const String cacheFolderName = 'mytube_cache';

  /// Subdirectory created inside the app support directory.
  static const String downloadsFolderName = 'mytube_downloads';

  @override
  Future<Result<StorageRoots>> resolve() async {
    try {
      final cacheDir = await _cacheDirectory();
      final supportDir = await _supportDirectory();
      final roots = StorageRoots(
        cacheRoot: p.join(cacheDir.path, cacheFolderName),
        downloadsRoot: p.join(supportDir.path, downloadsFolderName),
      );
      if (!roots.isSeparated) {
        // Structural refusal: a shared/overlapping layout would let cache
        // cleanup delete downloads, so cache stays disabled instead.
        return Result.err(
          UnexpectedError(
            diagnosticMessage: 'storage roots overlap, cache disabled: $roots',
          ),
        );
      }
      return Result.ok(roots);
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'storage root resolution failed: $e',
          cause: e,
        ),
      );
    }
  }
}
