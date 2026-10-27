import 'package:flutter/foundation.dart' show Uint8List;

import 'package:mytube/core/result.dart';
import 'package:mytube/data/cache/thumbnail_disk_cache.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/platform/remote_thumbnail_fetcher.dart';
import 'package:mytube/platform/thumbnail_bridge.dart';

/// Resolves and fetches preview images for library items (P7-01/P7-02/P7-03,
/// LIB-007, ARCHITECTURE §10).
///
/// Routing rules for one [SourceLocation]:
///  1. Prefer the location's stored `thumbnailUri` (a durable provider video
///     preview reference); otherwise fall back to the `sourceUri` itself.
///  2. A `thumbnailUri` that is `http(s)://` is a *poster image* and goes
///     through [RemoteThumbnailFetcher]; `content://`, `file://`, and SAF
///     `document://` references go through the native [ThumbnailBridge].
///  3. A `sourceUri` that is `http(s)://` (a stream) has no local file to
///     decode, so the bridge grabs one frame of it over HTTP
///     ([ThumbnailBridge.getNetworkThumbnail], P4-10) under the same request
///     identity the player uses ([networkHeaders]). Anything else yields no
///     thumbnail.
///
/// Thumbnails are SOFT-FAIL data: every failure path (missing grant, deleted
/// file, network error, unsupported scheme) returns `null` so the UI shows
/// its placeholder (P7-03) rather than an error dialog. Two disposable caches
/// sit in front of the fetch: a small in-memory LRU so scrolling a grid does
/// not re-decode or re-download visible tiles, and (from Phase 8) the
/// [ThumbnailDiskCache] so previews survive a restart without a network round
/// trip (CACHE-001).
///
/// Local previews are decoded at [decodeMaxSidePx] — the size a full-width
/// card actually needs — because a smaller native decode is upscaled by the
/// grid and reads as blurry.
class ThumbnailService {
  ThumbnailService({
    required VideoRepository repository,
    required ThumbnailBridge bridge,
    required RemoteThumbnailFetcher remoteFetcher,
    ThumbnailDiskCache? diskCache,
    int cacheLimit = defaultCacheLimit,
    Map<String, String> Function(SourceLocation location)? networkHeaders,
  }) : _repository = repository, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _bridge = bridge,
       // ignore: prefer_initializing_formals
       _remoteFetcher = remoteFetcher,
       // ignore: prefer_initializing_formals
       _diskCache = diskCache,
       // ignore: prefer_initializing_formals
       _cacheLimit = cacheLimit,
       // ignore: prefer_initializing_formals
       _networkHeaders = networkHeaders;

  final VideoRepository _repository;
  final ThumbnailBridge _bridge;
  final RemoteThumbnailFetcher _remoteFetcher;

  /// Optional persistent preview cache; `null` keeps thumbnails session-only
  /// (non-Android hosts, tests that do not exercise persistence).
  final ThumbnailDiskCache? _diskCache;

  final int _cacheLimit;

  /// Request headers a network frame grab must present for [location]
  /// (P4-10), so a preview is fetched under the same identity as playback.
  /// `null` means anonymous — local and future tokenless sources.
  final Map<String, String> Function(SourceLocation location)? _networkHeaders;

  /// Default number of decoded previews kept for the session — roughly a
  /// few screenfuls of grid tiles.
  static const int defaultCacheLimit = 64;

  /// Longest side requested from the native decoder for a local preview.
  ///
  /// A full-width 16:9 card is ~1100 physical px wide on a high-density
  /// phone, so anything smaller is upscaled by the grid. The bridge constant
  /// is the single source of truth (it mirrors the Kotlin default).
  static const int decodeMaxSidePx = ThumbnailBridge.defaultMaxSidePx;

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

    final key = ref.cacheKey(decodeMaxSidePx);
    final cached = _cache[key];
    if (cached != null) {
      // Touch for LRU recency.
      _cache
        ..remove(key)
        ..[key] = cached;
      return cached;
    }

    final pending = _inFlight[key];
    if (pending != null) return pending;

    Future<Uint8List?> run() async {
      // Persistent previews first: surviving a restart avoids a network fetch
      // for remote previews and a native decode for local ones.
      final persisted = await _diskCache?.read(key);
      if (persisted != null) {
        _store(key, persisted);
        return persisted;
      }
      final bytes = await _fetch(ref, location);
      _store(key, bytes);
      await _persist(key, bytes);
      return bytes;
    }

    final fetch = run();
    _inFlight[key] = fetch;
    try {
      return await fetch;
    } finally {
      // removeWhere (not remove) so the discarded Future value does not read
      // as an unawaited future.
      _inFlight.removeWhere((entryKey, _) => entryKey == key);
    }
  }

  /// Clears the in-memory cache (exposed for tests and low-memory handling).
  void clearCache() {
    _cache.clear();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Best-effort disk persistence; a disposable cache never fails the caller.
  Future<void> _persist(String key, Uint8List? bytes) async {
    if (bytes == null || _diskCache == null) return;
    await _diskCache.write(key, bytes);
  }

  Future<Uint8List?> _fetch(_ThumbnailRef ref, SourceLocation location) async {
    switch (ref.kind) {
      case _ThumbnailKind.poster:
        final uri = Uri.tryParse(ref.key);
        if (uri == null) return null;
        return _bytesOrNull(await _remoteFetcher.fetch(uri));
      case _ThumbnailKind.local:
        return _bytesOrNull(
          await _bridge.getThumbnail(ref.key, maxSidePx: decodeMaxSidePx),
        );
      case _ThumbnailKind.frame:
        return _bytesOrNull(
          await _bridge.getNetworkThumbnail(
            ref.key,
            headers: _networkHeaders?.call(location) ?? const {},
            maxSidePx: decodeMaxSidePx,
          ),
        );
    }
  }

  /// Soft-fail: a preview that could not be produced is simply absent.
  static Uint8List? _bytesOrNull(Result<Uint8List> result) => switch (result) {
    Ok(:final value) => value,
    Err() => null,
  };

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
    return _ThumbnailRef.ofSourceUri(location.sourceUri);
  }
}

/// How a preview reference is turned into bytes.
enum _ThumbnailKind {
  /// A local `content://`, `file://`, or `document://` reference the native
  /// bridge decodes from disk.
  local,

  /// A URL of a *preview image* the app downloads (a provider's poster).
  poster,

  /// A playback URL whose frame the native bridge grabs over HTTP (P4-10).
  frame,
}

/// A resolved thumbnail reference: the durable key plus how to fetch it.
class _ThumbnailRef {
  const _ThumbnailRef._(this.key, this.kind);

  final String key;
  final _ThumbnailKind kind;

  /// Key for the in-memory and on-disk preview caches.
  ///
  /// A preview this app produced (local decode or network frame) is an image
  /// whose decode size is part of its identity: changing the tier must not
  /// keep serving previews encoded at the old size for the life of the
  /// install. A poster is the provider's own image, so its key stays the
  /// plain URL (which is also how earlier releases cached it).
  String cacheKey(int maxSidePx) => switch (kind) {
    _ThumbnailKind.poster => key,
    _ThumbnailKind.local => '$key@${maxSidePx}px',
    // `#frame` keeps a decoded frame from colliding with a poster that
    // happens to be stored under the same URL.
    _ThumbnailKind.frame => '$key@${maxSidePx}px#frame',
  };

  /// A stored `thumbnailUri`: a poster image URL, or a local reference.
  static _ThumbnailRef? of(String uri) {
    if (_isHttp(uri)) return _ThumbnailRef._(uri, _ThumbnailKind.poster);
    return ofLocalOnly(uri);
  }

  static _ThumbnailRef? ofLocalOnly(String uri) {
    final lowered = uri.toLowerCase();
    if (lowered.startsWith('content://') ||
        lowered.startsWith('file://') ||
        lowered.startsWith('document://')) {
      return _ThumbnailRef._(uri, _ThumbnailKind.local);
    }
    return null;
  }

  /// A location's playback reference, used when no preview is stored.
  ///
  /// A local URI doubles as a decodable frame reference. An http(s) URL does
  /// not — but it is not unusable either: the bridge can grab a single frame
  /// of the stream, which is what a stream-only item needs (P4-10). Anything
  /// else (a bare provider id) yields nothing.
  static _ThumbnailRef? ofSourceUri(String uri) {
    final local = ofLocalOnly(uri);
    if (local != null) return local;
    if (_isHttp(uri)) return _ThumbnailRef._(uri, _ThumbnailKind.frame);
    return null;
  }

  static bool _isHttp(String uri) {
    final lowered = uri.toLowerCase();
    return lowered.startsWith('http://') || lowered.startsWith('https://');
  }
}
