import 'dart:math' as math;

import 'package:flutter/foundation.dart' show Uint8List;

import 'package:mytube/core/result.dart';
import 'package:mytube/data/cache/cache_usage.dart';
import 'package:mytube/data/cache/disk_cache_store.dart';

/// Disk-backed store for decoded preview images (CACHE-001, P8-01/P8-04).
///
/// Sits between [ThumbnailService]'s in-memory LRU and the network/decoder, so
/// previews survive a restart without being re-downloaded or re-decoded.
///
/// Three properties keep this safe to use from UI-driven code:
/// * **The store is resolved lazily and may be absent.** The platform storage
///   roots are an async lookup and are unavailable on non-Android test hosts,
///   so resolution is deferred to the first thumbnail request and a missing or
///   failing store simply disables persistence — the in-memory cache and the
///   soft-fail placeholder still behave exactly as before (CACHE-002).
/// * **Every failure is swallowed.** A cache is disposable: a read error is a
///   miss, a write error is a no-op. Nothing here ever turns into a UI error.
/// * **Trimming is amortised, never on the UI path.** Writes only trigger a
///   budget check once enough new bytes have landed (see
///   [_minCheckInterval]); the exact budget is re-read at that point so a
///   changed Settings value applies without rebuilding this object.
class ThumbnailDiskCache {
  ThumbnailDiskCache({
    required Future<DiskCacheStore?> Function() resolveStore,
    Future<int?> Function()? resolveBudget,
  }) : _resolveStore = resolveStore, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _resolveBudget = resolveBudget;

  /// Resolves the backing store, or `null` when persistence is unavailable.
  final Future<DiskCacheStore?> Function() _resolveStore;

  /// Reports the byte budget the cache must stay inside, or `null` when
  /// automatic trimming is not configured (tests, non-Android hosts).
  final Future<int?> Function()? _resolveBudget;

  /// Memoised resolution: the roots do not change for the process lifetime.
  Future<DiskCacheStore?>? _store;

  /// Bytes written since the last automatic trim check, so a write does not
  /// turn into a directory scan.
  int _bytesSinceCheck = 0;

  /// The budget seen by the most recent check; used to widen the interval so
  /// a large budget is not scanned every megabyte.
  int? _lastBudget;

  /// Never look at the filesystem more often than this, even when the budget
  /// is small: a scan per thumbnail would cost more than the cache saves.
  static const int _minCheckInterval = 256 * 1024;

  /// Returns the bytes cached for [key], or `null` on miss/unavailability.
  Future<Uint8List?> read(String key) async {
    final store = await _storeOrNull();
    if (store == null) return null;
    final result = await store.read(key);
    return switch (result) {
      Ok(:final value) => value,
      Err() => null,
    };
  }

  /// Persists [bytes] for [key]. Best-effort: failures are ignored.
  Future<void> write(String key, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    final store = await _storeOrNull();
    if (store == null) return;
    await store.write(key, bytes);
    await _trimIfDue(store, bytes.length);
  }

  /// Deletes least-recently-used previews until the cache fits in [maxBytes]
  /// and returns the bytes freed.
  ///
  /// Best-effort by design: `0` when the cache is unavailable, when
  /// [maxBytes] is not a usable budget (a non-positive value must never turn
  /// into "delete everything"), or when eviction fails. Only files this cache
  /// created are considered, so downloads and originals are out of reach
  /// (ARCHITECTURE §10, CACHE-006).
  Future<int> enforceBudget(int maxBytes) async {
    if (maxBytes <= 0) return 0;
    final store = await _storeOrNull();
    if (store == null) return 0;
    _bytesSinceCheck = 0;
    _lastBudget = maxBytes;
    final result = await store.evictToBudget(maxBytes);
    return switch (result) {
      Ok(:final value) => value,
      Err() => 0,
    };
  }

  /// Current size of the persisted previews; [CacheUsage.empty] when cache
  /// persistence is unavailable, so Settings can render a truthful zero.
  Future<CacheUsage> usage() async {
    final store = await _storeOrNull();
    if (store == null) return CacheUsage.empty;
    final result = await store.usage();
    return switch (result) {
      Ok(:final value) => value,
      Err() => CacheUsage.empty,
    };
  }

  /// Deletes every persisted preview and returns the bytes freed.
  Future<Result<int>> clear() async {
    final store = await _storeOrNull();
    if (store == null) return Result.ok(0);
    _bytesSinceCheck = 0;
    return store.clear();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Trims once [written] new bytes have accumulated past the check interval.
  Future<void> _trimIfDue(DiskCacheStore store, int written) async {
    _bytesSinceCheck += written;
    final known = _lastBudget;
    final interval = known == null
        ? _minCheckInterval
        : math.max(known ~/ 16, _minCheckInterval);
    if (_bytesSinceCheck < interval) return;

    final budget = await _budgetOrNull();
    if (budget == null || budget <= 0) return;
    await enforceBudget(budget);
  }

  Future<int?> _budgetOrNull() async {
    final resolve = _resolveBudget;
    if (resolve == null) return null;
    try {
      return await resolve();
    } catch (_) {
      return null;
    }
  }

  Future<DiskCacheStore?> _storeOrNull() => _store ??= _resolveSafely();

  Future<DiskCacheStore?> _resolveSafely() async {
    try {
      return await _resolveStore();
    } catch (_) {
      return null;
    }
  }
}
