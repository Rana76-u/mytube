import 'dart:async';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Warms a small window of adjacent Reels sources ahead of the swipe, and drops
/// that work the moment it goes stale (P6-04, PLAY-008, ARCHITECTURE §8).
///
/// Reels only ever needs the current reel plus the next one or two warmed, so a
/// swipe can start instantly from a cached [PlayableSource] instead of paying
/// the resolve cost on the gesture. Everything else is noise: rapid swipes must
/// not fan out into a queue of resolutions for reels the user skipped past.
///
/// Staleness is handled with a generation counter. [invalidate] bumps it so a
/// resolution that finishes after the user navigated away is discarded rather
/// than cached, and [clear] empties the cache when the tab is left. The cache is
/// FIFO-bounded to [maxCache] entries so preloading can never grow memory or
/// network usage without limit.
///
/// The preloader resolves sources only — it never touches the player. Playback
/// still goes through [PlaybackController]; a cached source simply lets the
/// screen hand the next reel over without re-resolving. The optional [onWarmed]
/// callback lets the host notice a fresh landing (e.g. to prewarm the next
/// reel's engine through `PlaybackController.prewarm`, P7-11) — the preloader
/// itself still never opens a player.
class ReelsSourcePreloader {
  ReelsSourcePreloader({
    required PlaybackSourceResolver resolver,
    this.maxCache = 3,
    this.onWarmed,
  }) : _resolver = resolver; // ignore: prefer_initializing_formals

  final PlaybackSourceResolver _resolver;

  /// The most resolved sources kept warm; older entries are evicted FIFO.
  final int maxCache;

  /// Called after a preload lands fresh (current generation) and is cached,
  /// with the item it belongs to and its resolved source. Never called for a
  /// stale or failed resolution.
  final void Function(VideoItemSummary item, PlayableSource source)? onWarmed;

  int _generation = 0;
  final Map<String, PlayableSource> _cache = <String, PlayableSource>{};
  final Set<String> _inFlight = <String>{};

  /// The number of currently-cached sources (bounded by [maxCache]).
  int get cachedCount => _cache.length;

  /// Removes and returns a previously-preloaded source for [item], or `null`
  /// when nothing warm exists (the caller then resolves on the playback path).
  PlayableSource? take(VideoItemSummary item) => _cache.remove(item.id.value);

  /// Returns a previously-preloaded source for [item] **without** removing it,
  /// or `null` when nothing warm exists. Lets a host re-warm an engine (for
  /// example after the app resumes from background, P13-05) while leaving the
  /// cache intact for the upcoming swipe.
  PlayableSource? peek(VideoItemSummary item) => _cache[item.id.value];

  /// Starts warming [item] in the background. A no-op when it is already cached
  /// or already being resolved, so repeated settles never double up work.
  void preload(VideoItemSummary item) {
    final id = item.id.value;
    if (_cache.containsKey(id)) return;
    if (!_inFlight.add(id)) return; // already resolving
    final generation = _generation;
    unawaited(_resolve(id, generation, item));
  }

  /// Marks any in-flight preloads stale so their results are discarded when they
  /// land. Already-completed entries stay (a just-swiped reel can consume one),
  /// but nothing new from before this call is added to the cache.
  void invalidate() => _generation++;

  /// Invalidates in-flight work and empties the cache — leaving the tab.
  void clear() {
    invalidate();
    _cache.clear();
  }

  Future<void> _resolve(
    String id,
    int generation,
    VideoItemSummary item,
  ) async {
    try {
      final result = await _resolver.resolveForItem(item);
      // Navigation happened while we resolved: this source is for a reel the
      // user already swiped past, so drop it instead of caching (PLAY-008).
      if (generation != _generation) return;
      if (result case Ok(:final value)) {
        _cache[id] = value;
        while (_cache.length > maxCache) {
          _cache.remove(_cache.keys.first);
        }
        onWarmed?.call(item, value);
      }
    } finally {
      _inFlight.remove(id);
    }
  }
}
