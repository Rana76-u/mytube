import 'package:flutter/foundation.dart' show Uint8List;

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/platform/remote_thumbnail_fetcher.dart';
import 'package:mytube/platform/thumbnail_bridge.dart';

/// Resolves and fetches preview images for library items (P7-01/P7-02/P7-03,
/// LIB-007, ARCHITECTURE §10).
///
/// Routing rules for one [SourceLocation]:
///  1. Prefer the location's stored `thumbnailUri` (a durable provider/local
///     preview reference); fall back to the `sourceUri` itself, which the
///     native bridge can decode for local content.
///  2. `http(s)://` references go through [RemoteThumbnailFetcher];
///     `content://`, `file://`, and SAF `document://` references go through
///     the native [ThumbnailBridge]. Anything else yields no thumbnail.
///
/// Thumbnails are SOFT-FAIL data: every failure path (missing grant, deleted
/// file, network error, unsupported scheme) returns `null` so the UI shows
/// its placeholder (P7-03) rather than an error dialog. The service also
/// keeps a small in-memory LRU so scrolling a grid does not re-decode or
/// re-download visible tiles. A disk cache is deliberately deferred to the
/// Phase 8 cache work (ARCHITECTURE §10) — in-memory only never touches
/// downloads and cannot grow unbounded.
class ThumbnailService {
  ThumbnailService({
    required VideoRepository repository,
    required ThumbnailBridge bridge,
    required RemoteThumbnailFetcher remoteFetcher,
    int cacheLimit = defaultCacheLimit,
  }) : _repository = repository, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _bridge = bridge,
       // ignore: prefer_initializing_formals
       _remoteFetcher = remoteFetcher,
       // ignore: prefer_initializing_formals
       _cacheLimit = cacheLimit;

  final VideoRepository _repository;
  final ThumbnailBridge _bridge;
  final RemoteThumbnailFetcher _remoteFetcher;
  final int _cacheLimit;

  /// Default number of decoded previews kept for the session — roughly a
  /// few screenfuls of grid tiles.
  static const int defaultCacheLimit = 64;

  /// key → bytes, ordered oldest→newest; re-inserted on every hit (LRU).
  final _cache = <String, Uint8List>{};

  /// In-flight fetches per key so two widgets asking for the same tile at
  /// once share one decode/download.
  final _inFlight = <String, Future<Uint8List?>>{};

  /// Returns the best thumbnail for the logical item [videoItemId], or `null`
  /// when none can be produced.
  ///
  /// Location preference mirrors playback: the user-selected primary that is
  /// available first, then any available location, then the primary, then the
  /// first attached location (P7-05/P7-06 ordering from the repository).
  Future<Uint8List?> thumbnailForVideo(String videoItemId) async {
    final locationsResult = await _repository.getSourceLocationsForVideo(
      VideoItemId(videoItemId),
    );
    final List<SourceLocation> locations;
    switch (locationsResult) {
      case Ok(:final value):
        locations = value;
      case Err():
        return null;
    }
    if (locations.isEmpty) return null;

    final location = _pickLocation(locations);
    return thumbnailForLocation(location);
  }

  /// Returns the thumbnail for one [location], or `null` on any failure.
  Future<Uint8List?> thumbnailForLocation(SourceLocation location) async {
    final ref = _resolveRef(location);
    if (ref == null) return null;

    final cached = _cache[ref.key];
    if (cached != null) {
      // Touch for LRU recency.
      _cache
        ..remove(ref.key)
        ..[ref.key] = cached;
      return cached;
    }

    final pending = _inFlight[ref.key];
    if (pending != null) return pending;

    Future<Uint8List?> run() async {
      final bytes = await _fetch(ref);
      _store(ref.key, bytes);
      return bytes;
    }

    final fetch = run();
    _inFlight[ref.key] = fetch;
    try {
      return await fetch;
    } finally {
      // removeWhere (not remove) so the discarded Future value does not read
      // as an unawaited future.
      _inFlight.removeWhere((key, _) => key == ref.key);
    }
  }

  /// Clears the in-memory cache (exposed for tests and low-memory handling).
  void clearCache() {
    _cache.clear();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<Uint8List?> _fetch(_ThumbnailRef ref) async {
    if (ref.isRemote) {
      final uri = Uri.tryParse(ref.key);
      if (uri == null) return null;
      final result = await _remoteFetcher.fetch(uri);
      return switch (result) {
        Ok(:final value) => value,
        Err() => null,
      };
    }
    final result = await _bridge.getThumbnail(ref.key);
    return switch (result) {
      Ok(:final value) => value,
      Err() => null,
    };
  }

  void _store(String key, Uint8List? bytes) {
    if (bytes == null) return;
    _cache[key] = bytes;
    while (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Picks which location to render from — primary+available first
  /// (P7-06), never showing a thumbnail from a source the user did not
  /// choose while their pick is usable.
  static SourceLocation _pickLocation(List<SourceLocation> locations) {
    for (final location in locations) {
      if (location.isPrimary &&
          location.availability == AvailabilityState.available) {
        return location;
      }
    }
    for (final location in locations) {
      if (location.availability == AvailabilityState.available) {
        return location;
      }
    }
    for (final location in locations) {
      if (location.isPrimary) return location;
    }
    return locations.first;
  }

  /// Decides which durable reference can produce a thumbnail for [location],
  /// or `null` when the scheme is not thumbnail-able (e.g. a bare provider
  /// id we do not know how to decode yet).
  static _ThumbnailRef? _resolveRef(SourceLocation location) {
    final stored = location.thumbnailUri;
    if (stored != null && stored.isNotEmpty) {
      return _ThumbnailRef.of(stored);
    }
    // Local content URIs double as thumbnail references for the native
    // bridge. Remote source URIs do NOT — downloading video bytes is not a
    // thumbnail strategy, so URL rows without a stored preview yield none.
    return _ThumbnailRef.ofLocalOnly(location.sourceUri);
  }
}

/// A resolved thumbnail reference: the durable key plus where to fetch it.
class _ThumbnailRef {
  const _ThumbnailRef._(this.key, this.isRemote);

  final String key;
  final bool isRemote;

  static _ThumbnailRef? of(String uri) {
    final lowered = uri.toLowerCase();
    if (lowered.startsWith('http://') || lowered.startsWith('https://')) {
      return _ThumbnailRef._(uri, true);
    }
    return ofLocalOnly(uri);
  }

  static _ThumbnailRef? ofLocalOnly(String uri) {
    final lowered = uri.toLowerCase();
    if (lowered.startsWith('content://') ||
        lowered.startsWith('file://') ||
        lowered.startsWith('document://')) {
      return _ThumbnailRef._(uri, false);
    }
    return null;
  }
}
