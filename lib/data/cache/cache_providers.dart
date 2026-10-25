import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/data/cache/disk_cache_store.dart';
import 'package:mytube/data/cache/thumbnail_disk_cache.dart';
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/database/tables/app_preferences_table.dart';
import 'package:mytube/domain/models/cache_limit.dart';
import 'package:mytube/platform/platform_providers.dart';

/// The thumbnail disk cache (P8-01/P8-04).
///
/// The backing directory is resolved lazily on the first thumbnail request, so
/// app startup and widget tests never pay for a platform lookup: resolution
/// failures (no plugin, unusable roots) leave the cache disabled and thumbnails
/// fall back to memory + soft-fail.
///
/// The budget is read from the same preference the Settings screen writes, so
/// automatic trimming follows a changed limit without rebuilding the provider.
/// A missing or corrupt row falls back to the default budget rather than
/// leaving the cache unbounded (CACHE-004).
final thumbnailDiskCacheProvider = Provider<ThumbnailDiskCache>((ref) {
  return ThumbnailDiskCache(
    resolveStore: () async {
      final roots = await ref.read(storagePathsProvider).resolve();
      return switch (roots) {
        Ok(:final value) => FileDiskCacheStore(root: value.cacheRoot),
        Err() => null,
      };
    },
    resolveBudget: () async {
      try {
        final stored = await ref
            .read(databaseProvider)
            .appPreferencesDao
            .getInt(AppPreferenceKeys.cacheLimitBytes, defaultValue: 0);
        return CacheLimit.sanitize(stored).bytes;
      } catch (_) {
        // Preferences unavailable: keep the cache bounded by the default.
        return CacheLimit.defaultLimit.bytes;
      }
    },
  );
});
