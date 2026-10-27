import 'dart:async';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/scan_merge_service.dart';
import 'package:mytube/platform/media_store_bridge.dart';
import 'package:mytube/sources/source_adapter.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Tunable parameters for [LibraryRefreshService].
///
/// All fields have sensible defaults so callers only need to override what
/// they care about.
class LibraryRefreshPreferences {
  const LibraryRefreshPreferences({
    this.minimumRefreshInterval = const Duration(minutes: 15),
  });

  /// How soon an automatic refresh may run after the previous one.
  ///
  /// Manual refreshes always bypass this guard.
  final Duration minimumRefreshInterval;
}

// ---------------------------------------------------------------------------
// Trigger
// ---------------------------------------------------------------------------

/// What caused a [LibraryRefreshService.refresh] call.
enum RefreshTrigger {
  /// The user explicitly requested a refresh (e.g. pull-to-refresh).
  manual,

  /// The system or app lifecycle triggered the refresh automatically.
  ///
  /// Automatic refreshes are throttled by
  /// [LibraryRefreshPreferences.minimumRefreshInterval].
  automatic,
}

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------

/// Aggregated outcome of one complete refresh run.
class LibraryRefreshResult {
  const LibraryRefreshResult({
    required this.adapterResults,
    required this.completedAt,
    this.wasCancelled = false,
  });

  /// Per-provider merge results.  Only adapters that succeeded are included.
  final Map<ProviderType, ScanMergeResult> adapterResults;

  /// When the refresh finished (local wall clock).
  final DateTime completedAt;

  /// True when the run stopped early because [LibraryRefreshService.cancel]
  /// was called.
  ///
  /// The partial [adapterResults] are still reported, but a cancelled run only
  /// observed part of the library: it proves nothing about the rows it never
  /// reached, so callers must not treat the library as fully resynced (see
  /// `LibraryRefreshNotifier.rescanAndDeindex`, which skips the de-index
  /// sweep for such runs).
  final bool wasCancelled;

  /// Total new VideoItem + SourceLocation pairs inserted across all providers.
  int get totalAdded => adapterResults.values.fold(0, (s, r) => s + r.added);

  /// Total existing SourceLocation rows whose metadata was refreshed.
  int get totalUpdated =>
      adapterResults.values.fold(0, (s, r) => s + r.updated);

  /// Total SourceLocation rows not seen in this scan and now marked missing.
  int get totalMarkedMissing =>
      adapterResults.values.fold(0, (s, r) => s + r.markedMissing);
}

// ---------------------------------------------------------------------------
// State hierarchy
// ---------------------------------------------------------------------------

/// Observable state of [LibraryRefreshService].
///
/// Pattern-match on the concrete subclass to drive UI.
sealed class RefreshState {
  const RefreshState();
}

/// The service is idle — no scan is running.
class RefreshIdle extends RefreshState {
  const RefreshIdle({this.lastRefreshedAt, this.lastResult});

  /// When the most recent successful refresh completed.  Null on first launch.
  final DateTime? lastRefreshedAt;

  /// The result of the most recent successful refresh, if any.
  final LibraryRefreshResult? lastResult;
}

/// A scan is currently running.
class RefreshInProgress extends RefreshState {
  const RefreshInProgress({
    required this.startedAt,
    required this.triggeredBy,
    this.currentAdapter,
    this.completedAdapters = 0,
    this.totalAdapters = 0,
  });

  /// When this refresh run started.
  final DateTime startedAt;

  /// What caused this refresh.
  final RefreshTrigger triggeredBy;

  /// The [ProviderType.name] of the adapter currently being scanned.
  final String? currentAdapter;

  /// How many adapters have finished (successfully or with an error).
  final int completedAdapters;

  /// Total number of adapters that will be visited.
  final int totalAdapters;
}

/// The most recent refresh attempt failed unexpectedly.
///
/// Per-adapter errors do **not** produce this state — they are isolated and
/// the run continues.  [RefreshFailed] is only emitted for unrecoverable
/// exceptions that abort the whole run.
class RefreshFailed extends RefreshState {
  const RefreshFailed({required this.error, required this.failedAt});

  /// The error that caused the failure.
  final AppError error;

  /// When the failure occurred.
  final DateTime failedAt;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Orchestrates foreground library refresh across all registered source
/// adapters (P3-05, LOCAL-008).
///
/// This class has **no Flutter or Riverpod imports**.  Provider wiring lives
/// in [LibraryRefreshNotifier] / [libraryRefreshServiceProvider].
///
/// ### Throttling
/// Automatic refreshes ([RefreshTrigger.automatic]) are suppressed when fewer
/// than [LibraryRefreshPreferences.minimumRefreshInterval] have elapsed since
/// the last successful refresh.  Manual refreshes always run.
///
/// ### Per-adapter error isolation
/// An error from one adapter's [VideoSourceAdapter.listVideos] or
/// [ScanMergeService.mergeResults] is recorded per-adapter and the run
/// continues with the remaining adapters.  The final result only includes
/// entries for adapters that succeeded.
///
/// ### Cancellation
/// Call [cancel] to stop the current scan.  The service emits
/// [RefreshIdle] immediately; the adapter's in-flight [Future] may still
/// resolve briefly in the background before it checks the token.  The
/// cancelled run then returns `Ok` with
/// [LibraryRefreshResult.wasCancelled] set and leaves the state alone, so a
/// newer run that started in the meantime keeps its token and progress.
///
/// ### Known limitation
/// [_lastRefreshedAt] is in-memory only — throttle resets on app process
/// restart (foreground-only per LOCAL-008, no WorkManager).
class LibraryRefreshService {
  LibraryRefreshService({
    required List<VideoSourceAdapter> adapters,
    required ScanMergeService mergeService,
    required LibraryRefreshPreferences preferences,
    MediaStoreBridge? mediaStore,
  }) : _adapters = adapters, // ignore: prefer_initializing_formals
       _mergeService = mergeService, // ignore: prefer_initializing_formals
       _preferences = preferences, // ignore: prefer_initializing_formals
       // Optional seam: when absent (e.g. tests exercising merge-only paths)
       // the MediaStore permission gate is skipped.
       // ignore: prefer_initializing_formals
       _mediaStore = mediaStore;

  final List<VideoSourceAdapter> _adapters;
  final ScanMergeService _mergeService;
  final LibraryRefreshPreferences _preferences;
  final MediaStoreBridge? _mediaStore;

  final StreamController<RefreshState> _stateController =
      StreamController<RefreshState>.broadcast();

  RefreshState _currentState = const RefreshIdle();

  // TODO(P3-05): persist _lastRefreshedAt via AppPreferences for
  // cross-restart throttling.
  DateTime? _lastRefreshedAt;

  CancellationToken? _activeCancellationToken;

  // ── Public surface ────────────────────────────────────────────────────────

  /// Stream of state transitions.  Replay the current state by reading
  /// [currentState] synchronously.
  Stream<RefreshState> get refreshState => _stateController.stream;

  /// The latest emitted [RefreshState].
  RefreshState get currentState => _currentState;

  /// Starts a refresh of all registered adapters.
  ///
  /// Returns [Err] immediately when:
  /// - A refresh is already in progress (use [cancel] first).
  /// - [trigger] is [RefreshTrigger.automatic] and the throttle interval has
  ///   not elapsed ([RefreshThrottledError]).
  ///
  /// Otherwise runs all adapters and returns [Ok] with a
  /// [LibraryRefreshResult] that aggregates only the successful ones.
  Future<Result<LibraryRefreshResult>> refresh({
    required RefreshTrigger trigger,
  }) async {
    // Guard: already refreshing.
    if (_currentState is RefreshInProgress) {
      return Result.err(
        const UnexpectedError(
          userMessage: 'A refresh is already in progress.',
          diagnosticMessage:
              'LibraryRefreshService.refresh called while already in progress',
        ),
      );
    }

    // Guard: throttle for automatic triggers.
    if (trigger == RefreshTrigger.automatic &&
        _lastRefreshedAt != null &&
        DateTime.now().difference(_lastRefreshedAt!) <
            _preferences.minimumRefreshInterval) {
      return Result.err(
        RefreshThrottledError(
          diagnosticMessage:
              'Automatic refresh suppressed — interval not elapsed. '
              'Last refresh: $_lastRefreshedAt',
          lastRefreshedAt: _lastRefreshedAt,
        ),
      );
    }

    // Guard: MediaStore permission. Without it the local scan silently
    // returns zero videos, so request access before scanning (LOCAL-001,
    // AGENTS "request permissions just in time"). A granted or partially
    // granted result lets the scan proceed; denial aborts with no state
    // change so the UI can retry after the user grants access.
    final permissionError = await _ensureMediaStoreAccess();
    if (permissionError != null) return Err(permissionError);

    final startedAt = DateTime.now();
    _activeCancellationToken = CancellationToken();
    final token = _activeCancellationToken!;

    _emit(
      RefreshInProgress(
        startedAt: startedAt,
        triggeredBy: trigger,
        totalAdapters: _adapters.length,
      ),
    );

    final adapterResults = <ProviderType, ScanMergeResult>{};

    try {
      for (var i = 0; i < _adapters.length; i++) {
        if (token.isCancelled) break;

        final adapter = _adapters[i];

        _emit(
          RefreshInProgress(
            startedAt: startedAt,
            triggeredBy: trigger,
            currentAdapter: adapter.sourceType.name,
            completedAdapters: i,
            totalAdapters: _adapters.length,
          ),
        );

        // --- List videos from adapter ----------------------------------------
        final listResult = await adapter.listVideos(
          continuationToken: null,
          cancellationToken: token,
        );

        SourcePage page;
        switch (listResult) {
          case Err<SourcePage>():
            // Per-adapter error — skip this adapter and continue.
            continue;
          case Ok<SourcePage>(:final value):
            page = value;
        }

        if (token.isCancelled) break;

        // --- Merge results into DB -------------------------------------------
        final mergeResult = await _mergeService.mergeResults(
          scannedVideos: page.videos,
          providerType: adapter.sourceType,
          cancellationToken: token,
        );

        switch (mergeResult) {
          case Err<ScanMergeResult>():
            // Per-adapter merge error — skip and continue.
            continue;
          case Ok<ScanMergeResult>(:final value):
            adapterResults[adapter.sourceType] = value;
        }
      }

      // Only the run that still owns the active token may finalise the
      // service. `cancel()` already cleared the token and emitted
      // [RefreshIdle]; a newer run installs its own token. Finalising in either
      // case would report a foreign outcome and — worse — null out the newer
      // run's token so it could no longer be cancelled.
      final cancelled = token.isCancelled;
      final result = LibraryRefreshResult(
        adapterResults: adapterResults,
        completedAt: DateTime.now(),
        wasCancelled: cancelled,
      );

      if (identical(_activeCancellationToken, token)) {
        _activeCancellationToken = null;
        // A cancelled run must not reset the throttle: it did not complete.
        if (!cancelled) _lastRefreshedAt = result.completedAt;
        _emit(
          RefreshIdle(lastRefreshedAt: _lastRefreshedAt, lastResult: result),
        );
      }

      return Result.ok(result);
    } catch (e, st) {
      final error = UnexpectedError(
        diagnosticMessage: 'LibraryRefreshService.refresh threw: $e\n$st',
        cause: e,
      );
      // Same ownership rule as above: a superseded run reports its own error
      // but must not clear the newer run's token or overwrite its progress
      // state with a failure it did not cause.
      if (identical(_activeCancellationToken, token)) {
        _activeCancellationToken = null;
        _emit(RefreshFailed(error: error, failedAt: DateTime.now()));
      }
      return Result.err(error);
    }
  }

  /// Cancels any in-progress refresh.
  ///
  /// Emits [RefreshIdle] immediately.  The in-flight adapter call may still
  /// be resolving briefly in the background.
  void cancel() {
    if (_activeCancellationToken != null) {
      _activeCancellationToken!.cancel();
      _activeCancellationToken = null;
    }
    // Emit idle regardless of whether we were actually refreshing,
    // so callers can safely call cancel() without checking state first.
    _emit(const RefreshIdle());
  }

  /// Cancels any in-progress refresh and closes the state stream.
  ///
  /// After dispose, [refreshState] will complete and this service must not
  /// be used again.
  Future<void> dispose() async {
    cancel();
    if (!_stateController.isClosed) {
      await _stateController.close();
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Checks — and if necessary requests — the MediaStore read permission.
  ///
  /// Returns `null` when the scan may proceed (granted / partially granted,
  /// or when no bridge seam was supplied) and a [PermissionDeniedError] when
  /// access was refused. The permission request itself may show the system
  /// dialog; permanently-denied states resolve immediately without one.
  Future<AppError?> _ensureMediaStoreAccess() async {
    final bridge = _mediaStore;
    if (bridge == null) return null;

    var status = await bridge.checkPermission();
    if (status != MediaStorePermissionStatus.granted &&
        status != MediaStorePermissionStatus.partiallyGranted) {
      status = await bridge.requestPermission();
    }
    if (status == MediaStorePermissionStatus.granted ||
        status == MediaStorePermissionStatus.partiallyGranted) {
      return null;
    }
    return const PermissionDeniedError(
      diagnosticMessage:
          'LibraryRefreshService.refresh aborted — MediaStore access not granted',
    );
  }

  void _emit(RefreshState state) {
    _currentState = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }
}
