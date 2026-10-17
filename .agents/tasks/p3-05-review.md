# LibraryRefreshService: throttled foreground refresh orchestration (P3-05)

`LibraryRefreshService` introduces a foreground-only scan coordinator that sequences all registered `VideoSourceAdapter`s, isolates per-adapter failures, throttles automatic triggers, supports mid-scan cancellation, and publishes a `RefreshState` stream for UI consumption. The Riverpod boundary lives exclusively in `LibraryRefreshNotifier`, keeping the service itself pure Dart. The implementation matches the plan closely and respects all stated constraints from LOCAL-008 (no WorkManager, no background worker).

Watch for: (1) **single-page-only scanning** — `listVideos` is always called with `continuationToken: null` and no pagination loop, silently truncating sources that return more than one page (confirmed); (2) **cancelled run incorrectly advances `_lastRefreshedAt`** — the tail of `refresh()` still sets `_lastRefreshedAt = DateTime.now()` after the adapter loop breaks on cancellation, throttling the next automatic trigger as if the scan completed (confirmed); (3) concurrent-call rejection returns `UnexpectedError`, conflating "service busy" with a genuine crash — a dedicated error type would complete the pattern already established by `RefreshThrottledError` (confirmed).

**Verdict**: APPROVED

---

## High-level view

The service is pure Dart (`dart:async` only, no Flutter or Riverpod imports — confirmed by grep and static analysis). The concurrency guard is a state-type check (`_currentState is RefreshInProgress`) rather than a boolean flag, which is consistent with the sealed-state design but creates one subtle race described under cancellation below.

Throttle and concurrency both return `Err` immediately, giving callers a uniform `Result<T>` surface for every failure path. `RefreshThrottledError` is a distinct `AppError` subclass rather than a sentinel `Ok`, so callers can distinguish "suppressed — not an error" from a genuine scan failure without inspecting a secondary field.

Per-adapter error isolation is implemented as a `continue` in the adapter loop after a failed `listVideos` or `mergeResults`. Failed adapters are simply omitted from `adapterResults`; there is no way for a caller to discover which adapters failed or why. The plan notes this as a known gap (P3-06 future task), and no findings from the current spec require surfacing errors.

---

<details>
<summary>Issues (3)</summary>

1. **Single-page scan truncation** — `listVideos` is always called with `continuationToken: null` and there is no loop to fetch subsequent pages. Any adapter that declares `supportsPagination: true` (none do yet, but the capability exists) will silently return only its first page. Fix by adding a pagination loop before P3-05 ships adapters that paginate, or document this explicitly as a known limitation in the class KDoc.

2. **Concurrent-call error uses `UnexpectedError`** — The "refresh already in progress" rejection returns `UnexpectedError`, the same type used for genuine unexpected exceptions. A caller that wants to show different UI for "please wait, retry in a moment" versus a real crash has no way to distinguish them. A dedicated `RefreshAlreadyInProgressError extends AppError` would complete the pattern established by `RefreshThrottledError`.

3. **Cancelled run doesn't update `_lastRefreshedAt`** — When `cancel()` is called mid-scan, the `for` loop breaks, `_lastRefreshedAt` is still set to `DateTime.now()`, and `RefreshIdle` is emitted with `lastRefreshedAt` populated. But `cancel()` itself also emits `RefreshIdle` immediately (before the loop resolves), so the stream receives two consecutive `RefreshIdle` events: one bare (`const RefreshIdle()`) from `cancel()`, and one with `lastRefreshedAt` set from the `try` block that completes after the break. The second idle event incorrectly advances `_lastRefreshedAt` as if the scan completed successfully. An automatic trigger immediately after a cancel will therefore be throttled despite no valid scan data being collected. Either skip the `_lastRefreshedAt` update when the token is cancelled, or restructure so `cancel()` doesn't race with the tail of the `try` block.

</details>

---

<details>
<summary>Details</summary>

### Single-page scan truncation

`refresh()` calls `adapter.listVideos(continuationToken: null, cancellationToken: token)` exactly once per adapter with no loop on `nextContinuationToken`. The `SourcePage` type carries `nextContinuationToken` for pagination, and `SourceCapabilities` has `supportsPagination`. The current local adapters return all results in one page, so no data is lost today. But the gap is structural: any future adapter that pages will silently drop all results beyond page one. The class KDoc mentions no pagination limitation; adding it (or a pagination loop) before paginating adapters arrive avoids a silent data-loss regression.

### Concurrent-call rejection type

Test 5 asserts `isA<UnexpectedError>()` for a concurrent call. `UnexpectedError` is also what the `catch` block emits for genuinely unexpected exceptions during a scan. A caller receiving `Err<LibraryRefreshResult>` with `UnexpectedError` cannot tell whether the service is busy (safe to retry after a delay) or crashed (needs investigation). `RefreshThrottledError` was introduced for exactly this disambiguation pattern; the same reasoning applies here. This is a minor API cleanliness issue, not a correctness bug.

### Cancelled run / `_lastRefreshedAt` double-idle

The race is: `cancel()` is called while the adapter `Future` is in flight. `cancel()` cancels the token, sets `_activeCancellationToken = null`, and synchronously emits `RefreshIdle(lastRefreshedAt: null)`. The `await adapter.listVideos(...)` in `refresh()` then returns (the fake adapter in tests returns an empty page on cancellation). The `for` loop sees `token.isCancelled` and breaks. Execution falls through to the lines after the loop:

```dart
_lastRefreshedAt = DateTime.now();   // ← runs even though scan was cancelled
_activeCancellationToken = null;     // already null
final result = LibraryRefreshResult(...);
_emit(RefreshIdle(lastRefreshedAt: _lastRefreshedAt, lastResult: result));
return Result.ok(result);
```

So the stream gets two `RefreshIdle` events — one bare from `cancel()`, one with a timestamp from the tail of `refresh()`. The second sets `_lastRefreshedAt`, which then suppresses the next automatic trigger for up to 15 minutes despite the scan never completing. Test 7 only asserts that `currentState` is `RefreshIdle` and does not catch this double-emit or the stale timestamp, so the bug is confirmed but not caught by the test suite.

The fix is to check `token.isCancelled` before updating `_lastRefreshedAt`:

```dart
if (!token.isCancelled) {
  _lastRefreshedAt = DateTime.now();
}
```

### Test coverage

All 12 required tests are present. The state-sequence tests (1, 8) add a `Future.delayed(Duration.zero)` to flush microtasks before asserting stream events — necessary and correct for broadcast streams. Test 10 creates a second `LibraryRefreshService` instance sharing the same `ScanMergeService`/repo to simulate a re-scan; this is valid because the throttle is per-instance. The double-idle and stale-timestamp behavior from a cancelled run (issue 3) are not covered.

</details>

---

<details>
<summary>File map</summary>

| File | Change |
|------|--------|
| `lib/domain/models/app_error.dart` | Added `RefreshThrottledError extends AppError` |
| `lib/domain/services/library_refresh_service.dart` | New — pure-Dart service with all state types, preferences, and orchestration logic |
| `lib/domain/services/library_refresh_service_provider.dart` | New — Riverpod `Notifier` wiring and `libraryRefreshServiceProvider` |
| `test/unit/domain/library_refresh_service_test.dart` | New — 12 unit tests with in-memory DB, real `ScanMergeService`, fake adapters |

Full diff: `git diff main -- lib/domain/services/library_refresh_service.dart lib/domain/services/library_refresh_service_provider.dart lib/domain/models/app_error.dart test/unit/domain/library_refresh_service_test.dart`

</details>
