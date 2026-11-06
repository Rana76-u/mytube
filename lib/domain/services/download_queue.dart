/// A pure scheduler for download jobs (ARCHITECTURE §15.8, DL1.5).
///
/// It owns only ordering and concurrency — no I/O, no timers, no platform
/// channels — so the whole policy is unit-testable with plain ids. The runner
/// wraps this: it calls [enqueue] when a job is created, [complete]/[cancel]
/// when the engine reports a terminal event, and reads [running] to know what
/// to actually drive. Promotion (starting the next queued job when a slot
/// frees) is the queue's job, not the caller's.
///
/// The type parameter is the job's stable id; equality is by value.
class DownloadQueue<T> {
  DownloadQueue({this.maxConcurrent = 3, int? maxQueued})
    : assert(maxConcurrent >= 1, 'maxConcurrent must be at least 1'),
      maxQueued = maxQueued ?? 50;

  /// How many jobs may run at once (mirrors `DownloadPreset.maxConcurrent`).
  final int maxConcurrent;

  /// Upper bound on jobs waiting in the queue (not counting the running ones).
  /// A new [enqueue] beyond this is rejected so a burst cannot grow unbounded.
  final int maxQueued;

  final List<T> _queued = [];
  final List<T> _running = [];
  final Set<T> _paused = {};

  /// Jobs waiting for a slot, in first-in-first-out order.
  List<T> get queued => List<T>.unmodifiable(_queued);

  /// Jobs currently occupying a slot.
  List<T> get running => List<T>.unmodifiable(_running);

  /// Jobs the user paused; they hold no slot and are not promoted.
  Set<T> get paused => Set<T>.unmodifiable(_paused);

  int get runningCount => _running.length;
  int get queuedCount => _queued.length;

  bool isRunning(T job) => _running.contains(job);
  bool isQueued(T job) => _queued.contains(job);
  bool isPaused(T job) => _paused.contains(job);

  /// True when the job is tracked in any active state.
  bool isActive(T job) => isRunning(job) || isQueued(job) || isPaused(job);

  /// Adds [job] to the queue and promotes it if a slot is free.
  ///
  /// Returns `false` when the job is already tracked (idempotent) or when the
  /// queue is at [maxQueued] (so a caller learns the job was refused).
  bool enqueue(T job) {
    if (isActive(job)) return false;
    if (_queued.length >= maxQueued) return false;
    _queued.add(job);
    _promote();
    return true;
  }

  /// Marks [job] finished, frees its slot and promotes the next queued job.
  void complete(T job) {
    _removeEverywhere(job);
    _promote();
  }

  /// Cancels [job] from any state, freeing a slot if it was running.
  void cancel(T job) {
    _removeEverywhere(job);
    _promote();
  }

  /// Pauses [job], taking it out of the running set (or the queue) so another
  /// job can move up. The paused job keeps its progress externally.
  void pause(T job) {
    if (!isActive(job)) return;
    _queued.remove(job);
    _running.remove(job);
    _paused.add(job);
    _promote();
  }

  /// Re-queues a paused job at the tail; it starts immediately if a slot is
  /// free. Returns `false` when the job was not paused.
  bool resume(T job) {
    if (!_paused.remove(job)) return false;
    _queued.add(job);
    _promote();
    return true;
  }

  /// Moves queued jobs into free slots, oldest first, up to [maxConcurrent].
  void _promote() {
    while (_running.length < maxConcurrent && _queued.isNotEmpty) {
      _running.add(_queued.removeAt(0));
    }
  }

  void _removeEverywhere(T job) {
    _queued.remove(job);
    _running.remove(job);
    _paused.remove(job);
  }
}
