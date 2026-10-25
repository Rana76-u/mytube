import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/data/cache/cache_providers.dart';
import 'package:mytube/data/cache/cache_usage.dart';
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/database/tables/app_preferences_table.dart';
import 'package:mytube/domain/models/cache_limit.dart';

/// Snapshot of the app's disposable cache for the Settings screen
/// (CACHE-003/CACHE-004, P8-02/P8-03).
///
/// Value-equal so a re-measure that finds the same size does not rebuild the
/// row (Riverpod only notifies on a changed state).
class CacheState {
  const CacheState({
    this.usage = CacheUsage.empty,
    this.limit = CacheLimit.defaultLimit,
    this.measuring = true,
  });

  /// What the cache currently holds.
  final CacheUsage usage;

  /// How much the cache is allowed to hold before cleanup trims it.
  final CacheLimit limit;

  /// True while the first (or a requested) measurement is still running, so
  /// the row can show progress instead of a misleading `0 B`.
  final bool measuring;

  /// True when the cache has outgrown [limit] and cleanup is due.
  bool get overLimit => limit.isExceededBy(usage);

  CacheState copyWith({
    CacheUsage? usage,
    CacheLimit? limit,
    bool? measuring,
  }) => CacheState(
    usage: usage ?? this.usage,
    limit: limit ?? this.limit,
    measuring: measuring ?? this.measuring,
  );

  @override
  bool operator ==(Object other) =>
      other is CacheState &&
      other.usage == usage &&
      other.limit == limit &&
      other.measuring == measuring;

  @override
  int get hashCode => Object.hash(usage, limit, measuring);

  @override
  String toString() =>
      'CacheState($usage, limit: $limit, measuring: $measuring)';
}

/// Owns the measured cache size and the cache limit shown in Settings
/// (P8-02/P8-03).
///
/// Widgets read this notifier instead of touching the cache store, the file
/// system, or the preferences DAO directly (AGENTS layering rules). Measuring
/// is on-demand and best-effort: the store reports `CacheUsage.empty` when
/// cache persistence is unavailable, so the row degrades to `0 B` rather than
/// an error. The limit is persisted through the typed preferences DAO and
/// survives restarts; an unreadable or corrupt value falls back to
/// [CacheLimit.defaultLimit] instead of leaving the cache unbounded.
class CacheController extends Notifier<CacheState> {
  var _alive = true;

  /// The restore pass currently running, if any. Overlapping callers (the
  /// deferred build pass plus an explicit request) share one pass, so a slow
  /// load can never publish a stale limit over a newer choice.
  Future<void>? _inFlight;

  @override
  CacheState build() {
    ref.onDispose(() => _alive = false);
    // Deferred so no provider mutation happens during the build pass.
    Future<void>.microtask(load);
    return const CacheState();
  }

  /// Restores the persisted limit, then measures what the cache holds.
  ///
  /// The limit is read first so the first published state already knows the
  /// budget, and an eviction pass (P8-04) never starts against a default the
  /// user did not choose. [build] runs this deferred; tests and post-cleanup
  /// callers may await it directly.
  Future<void> load() {
    final running = _inFlight;
    if (running != null) return running;
    final pass = _loadOnce();
    _inFlight = pass;
    pass.whenComplete(() {
      if (identical(_inFlight, pass)) _inFlight = null;
    }).ignore();
    return pass;
  }

  Future<void> _loadOnce() async {
    final limit = await _readLimit();
    if (!_alive) return;
    state = state.copyWith(limit: limit);
    await refreshUsage();
    await _enforceBudget();
  }

  /// Re-measures the cache and publishes the result.
  Future<void> refreshUsage() async {
    if (!_alive) return;
    state = state.copyWith(measuring: true);
    final usage = await ref.read(thumbnailDiskCacheProvider).usage();
    if (!_alive) return;
    state = state.copyWith(usage: usage, measuring: false);
  }

  /// Applies a new cache limit for this session and persists it.
  ///
  /// The in-memory value is authoritative even if the write fails (same
  /// convention as the scan-scope toggle). Trimming runs immediately
  /// afterwards, so lowering the limit takes effect without waiting for the
  /// next thumbnail write (CACHE-004).
  Future<void> setLimit(CacheLimit limit) async {
    state = state.copyWith(limit: limit);
    try {
      await ref
          .read(databaseProvider)
          .appPreferencesDao
          .setInt(AppPreferenceKeys.cacheLimitBytes, limit.bytes);
    } catch (_) {
      // Persistence unavailable — the session-level limit still applies.
    }
    await _enforceBudget();
  }

  /// Deletes every cached preview and republishes the size (CACHE-005).
  ///
  /// Scoped to this app's cache store: only files it created inside the cache
  /// root are removed, so downloads, original videos, and library metadata
  /// are never touched (ARCHITECTURE §10, CACHE-006). Returns the bytes freed,
  /// or the [AppError] the UI should report; a failed clear leaves the
  /// measured size as it was rather than claiming the cache is empty.
  ///
  /// Previews already decoded into [ThumbnailService]'s session cache stay in
  /// memory (they die with the process and are not counted in the reported
  /// size), so clearing does not force every visible tile to re-fetch.
  Future<Result<int>> clearCache() async {
    final result = await ref.read(thumbnailDiskCacheProvider).clear();
    if (!_alive) return result;
    if (result.isOk) await refreshUsage();
    return result;
  }

  /// Trims the cache back inside the budget when it has outgrown it, then
  /// republishes the smaller size so Settings shows what is actually stored.
  ///
  /// Eviction is confined to entries this app's cache created; downloads,
  /// originals, and library metadata are unreachable from here (CACHE-006).
  /// A failed trim leaves the size as measured — the row still tells the
  /// truth, and the next write pass retries.
  Future<void> _enforceBudget() async {
    if (!_alive || !state.overLimit) return;
    final freed = await ref
        .read(thumbnailDiskCacheProvider)
        .enforceBudget(state.limit.bytes);
    if (!_alive || freed <= 0) return;
    await refreshUsage();
  }

  /// Reads the stored limit, tolerating a missing database or a bad value.
  Future<CacheLimit> _readLimit() async {
    try {
      final stored = await ref
          .read(databaseProvider)
          .appPreferencesDao
          .getInt(AppPreferenceKeys.cacheLimitBytes, defaultValue: 0);
      return CacheLimit.sanitize(stored);
    } catch (_) {
      // Database unavailable (startup failure or unsupported host): keep the
      // default budget rather than blocking the screen.
      return CacheLimit.defaultLimit;
    }
  }
}

/// Provider for the [CacheController] (P8-02).
final cacheControllerProvider = NotifierProvider<CacheController, CacheState>(
  CacheController.new,
);
