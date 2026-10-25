import 'package:flutter/foundation.dart' show debugPrint;

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

/// Bridges live playback position to durable watch progress and last-played
/// time (P5-08, LIB-002).
///
/// The repository already stores a `(watchProgressMs, lastPlayedAt)` pair per
/// video item (P2-04); this service decides *when* to persist it so that the
/// future player screen can simply forward every position tick without
/// hammering SQLite. Saves are throttled per item, the newest position is
/// always kept in memory, and an explicit [flush] is offered for pause/stop/
/// app-lifecycle boundaries.
///
/// ### Invariants
/// - Progress persistence is best-effort: a failed save is logged via
///   [debugPrint] and never throws to the caller, so a disk hiccup can't break
///   playback.
/// - The very first reported position for an item saves immediately, so even a
///   brief watch marks the item as played (drives the watched filter and
///   last-played sort, LIB-004/LIB-005).
/// - Subsequent saves are rate-limited to at most one per [throttle] window per
///   item, measured from the last successful write.
/// - Never mutates the original media; it writes only the app's own metadata.
class WatchProgressService {
  WatchProgressService({
    required VideoRepository repository,
    Duration throttle = const Duration(seconds: 5),
    DateTime Function() clock = DateTime.now,
  }) : _repository = repository, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _throttle = throttle,
       // ignore: prefer_initializing_formals
       _clock = clock;

  final VideoRepository _repository;
  final Duration _throttle;
  final DateTime Function() _clock;

  /// Per-item working state: the latest seen position and the timestamp of the
  /// last successful write (null until the first save).
  final Map<String, _ProgressState> _states = {};

  /// The stored position to resume from, or `null` when the item has never been
  /// played, sits at the very start, or the read failed.
  ///
  /// Callers treat `null` as "start from the beginning".
  Future<Duration?> resumePosition(VideoItemId id) async {
    final result = await _repository.getProgress(id);
    return switch (result) {
      Ok(:final value) =>
        (value == null || value.progressMs <= 0)
            ? null
            : Duration(milliseconds: value.progressMs),
      Err(:final error) => _resumeFailure(error),
    };
  }

  /// Records a live [position] for [id] and marks the item played.
  ///
  /// The newest position is always remembered; a write reaches the repository
  /// only on the first report for the item or once [throttle] has elapsed since
  /// the last successful write. Returns `true` when this call performed a save.
  Future<bool> reportPosition({
    required VideoItemId id,
    required Duration position,
  }) async {
    final state = _states.putIfAbsent(id.value, _ProgressState.new);
    state.lastPositionMs = position.inMilliseconds;
    // Remember that the newest position has not reached storage, so flushAll
    // (app-background boundary, P13-05) can tell a pending tick from an item
    // that is already saved exactly.
    state.dirty = true;

    final now = _clock();
    final lastSaved = state.lastSavedAt;
    if (lastSaved != null && now.difference(lastSaved) < _throttle) {
      return false; // Within the throttle window — keep it pending for flush().
    }
    return _write(id, state, now);
  }

  /// Forces the newest pending position for [id] to persist, ignoring the
  /// throttle window. Call this on pause, stop, or app lifecycle boundaries so
  /// the final position survives even for a short watch.
  Future<bool> flush(VideoItemId id) async {
    final state = _states[id.value];
    if (state == null) return false;
    return _write(id, state, _clock());
  }

  /// Whether any tracked item holds a position that has not been written since
  /// it was last reported. Lets a lifecycle observer skip [flushAll] entirely
  /// (no database round-trips) when nothing was watched.
  bool get hasPending => _states.values.any((s) => s.dirty);

  /// Flushes every tracked item, for the app-background lifecycle boundary
  /// (P13-05): background audio (P13-02) keeps a screen alive while playing,
  /// so the OS can reclaim the process with position writes still sitting
  /// inside their throttle window. Returns the number of items written.
  Future<int> flushAll() async {
    var written = 0;
    // Snapshot the ids: each await below hands control back, and a concurrent
    // report/forget could mutate the map mid-flush.
    for (final id in _states.keys.toList()) {
      final state = _states[id];
      if (state == null || !state.dirty) continue;
      if (await flush(VideoItemId(id))) written++;
    }
    return written;
  }

  /// Drops the in-memory state for [id] without saving — used when playback of
  /// an item ends and its progress is no longer relevant (e.g. the user seeks
  /// away or the screen disposes).
  void forget(VideoItemId id) => _states.remove(id.value);

  Future<bool> _write(VideoItemId id, _ProgressState state, DateTime at) async {
    final result = await _repository.saveProgress(
      id: id,
      progressMs: state.lastPositionMs,
      playedAt: at.millisecondsSinceEpoch,
    );
    switch (result) {
      case Ok():
        state.lastSavedAt = at;
        // The write persisted exactly `lastPositionMs`, so nothing reported so
        // far is pending any more; a later report re-dirties the state.
        state.dirty = false;
        return true;
      case Err(:final error):
        debugPrint(
          'WatchProgressService.saveProgress failed: ${error.diagnosticMessage}',
        );
        return false;
    }
  }

  Duration? _resumeFailure(AppError error) {
    debugPrint(
      'WatchProgressService.getProgress failed: ${error.diagnosticMessage}',
    );
    return null;
  }
}

class _ProgressState {
  int lastPositionMs = 0;
  DateTime? lastSavedAt;

  /// True while [lastPositionMs] has not been written to storage yet. Set by
  /// `reportPosition`, cleared by a successful `_write` of that same position.
  bool dirty = false;
}
