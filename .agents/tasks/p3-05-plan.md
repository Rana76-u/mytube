# Implementation Plan — P3-05: Throttled Foreground Refresh and Manual Refresh

## Context from codebase exploration

- **Build/test commands**: `flutter analyze`, `flutter test`, `dart format .`
- **Test pattern**: `AppDatabase.inMemory()` + `DriftVideoRepository` + real service, no Flutter test binding needed for pure-Dart services (matches `scan_merge_service_test.dart`)
- **Provider pattern**: `Provider<T>` for plain services (see `scan_merge_service_provider.dart`); `StateNotifierProvider` for stateful notifiers (established pattern from P1-02 `ThemeModeNotifier`)
- **Result pattern**: `sealed class Result<T>` with `Ok<T>` and `Err<T>` — all public methods return `Result<T>` or `void`
- **AppError**: `UnexpectedError` is the right variant for unexpected/concurrent-call errors; add new `RefreshThrottledError` for throttle suppression
- **No Flutter imports** in `LibraryRefreshService` — same constraint as `ScanMergeService`; the Riverpod wiring lives exclusively in `_provider.dart`
- **FakeVideoSourceAdapter** must be defined in the test file (matches `FakeMediaStoreBridge`/`FakeSafBridge` pattern in `local_media_adapter_test.dart`)
- **`ProviderType`** lives in `video_repository.dart` — import it from there, not from source_adapter
- **`StreamController`** must be closed in `dispose()` — `close_sinks` lint is enabled
- **`cancel_subscriptions`** lint is enabled — the notifier's stream subscription must be cancelled on dispose

---

## Design decisions

1. **`RefreshThrottledError` as new `AppError` subclass** — throttle suppression returns `Err(RefreshThrottledError(...))` rather than a silent `Ok`. This keeps the `Result<T>` contract uniform and lets callers distinguish throttle from a real error. Added to `app_error.dart`.

2. **`RefreshState` as a sealed class, not an enum** — `RefreshFailed` needs to carry the `AppError`; sealed class is the natural fit in Dart 3.

3. **`LibraryRefreshPreferences` as a plain `const`-constructible value class** — no persistence, just a configuration object passed to the service constructor, consistent with how `ScanMergeService` takes `VideoRepository`.

4. **`_lastRefreshedAt` is in-memory only** — explicitly documented in the service KDoc as a known limitation (P3-05 spec). No DB column needed; throttle resets on app restart.

5. **Single `CancellationToken` per run** — created once at the start of `refresh()`, stored as `_activeToken`, cancelled by `cancel()`. Adapter errors are caught per-adapter and recorded, but do not abort the whole run.

6. **`LibraryRefreshNotifier` extends `StateNotifier<RefreshState>`** — mirrors the existing `ThemeModeNotifier` pattern; subscribes to `LibraryRefreshService.refreshState` stream and updates Riverpod state; disposes service in `dispose()`.

7. **`libraryRefreshServiceProvider` returns `LibraryRefreshNotifier`** — `StateNotifierProvider<LibraryRefreshNotifier, RefreshState>` gives downstream widgets both the state and the ability to call `notifier.refresh()`/`notifier.cancel()`.

---

## Implementation Plan

- [ ] 1. Add `RefreshThrottledError` to `app_error.dart`.
      The throttle path in `LibraryRefreshService` needs a distinct error variant so callers can distinguish "throttled" from an unexpected failure. `RefreshThrottledError extends AppError` with a sensible `userMessage` and a `diagnosticMessage` that includes `lastRefreshedAt`.
      Files: `lib/domain/models/app_error.dart`
      Verify: `flutter analyze lib/domain/models/app_error.dart` — no issues.

- [ ] 2. Create `lib/domain/services/library_refresh_service.dart`.
      Implement all contracts from the spec in dependency order:

      a. **Value / enum types** (top of file, no imports from Flutter):
         - `LibraryRefreshPreferences({Duration minimumRefreshInterval = const Duration(minutes: 15)})`
         - `enum RefreshTrigger { manual, automatic }`
         - `sealed class RefreshState` with three subclasses:
           - `final class RefreshIdle extends RefreshState`
           - `final class RefreshInProgress extends RefreshState`
           - `final class RefreshFailed extends RefreshState { final AppError error; }`
         - `class LibraryRefreshResult` with:
           - `final Map<ProviderType, ScanMergeResult> adapterResults`
           - `final DateTime completedAt`
           - `int get totalAdded` — sum of `adapterResults.values.map((r) => r.added)`
           - `int get totalUpdated` — sum of `adapterResults.values.map((r) => r.updated)`
           - `int get totalMarkedMissing` — sum of `adapterResults.values.map((r) => r.markedMissing)`

      b. **`LibraryRefreshService` class** (no Flutter imports):
         - Fields: `List<VideoSourceAdapter> _adapters`, `ScanMergeService _scanMergeService`, `LibraryRefreshPreferences _preferences`, `bool _isRefreshing = false`, `DateTime? _lastRefreshedAt`, `CancellationToken? _activeToken`, `StreamController<RefreshState> _stateController = StreamController.broadcast()`
         - `Stream<RefreshState> get refreshState => _stateController.stream`
         - `bool get isRefreshing => _isRefreshing`
         - `refresh({required RefreshTrigger trigger}) → Future<Result<LibraryRefreshResult>>`:
           1. If `_isRefreshing` → return `Err(UnexpectedError(diagnosticMessage: 'Refresh already in progress'))`.
           2. If `trigger == RefreshTrigger.automatic && _lastRefreshedAt != null && DateTime.now().difference(_lastRefreshedAt!) < _preferences.minimumRefreshInterval` → return `Err(RefreshThrottledError(...))`.
           3. `_isRefreshing = true`; emit `RefreshInProgress` to stream.
           4. Create `_activeToken = CancellationToken()`.
           5. Iterate `_adapters`:
              - Call `adapter.listVideos(cancellationToken: _activeToken)`.
              - On `Err` from `listVideos` → record per-adapter error, continue to next adapter.
              - On `Ok(SourcePage)` → call `_scanMergeService.mergeResults(providerType: adapter.sourceType, scannedVideos: page.videos, cancellationToken: _activeToken)`.
              - On `Err` from `mergeResults` → record per-adapter error, continue.
              - On `Ok(ScanMergeResult)` → store in `adapterResults[adapter.sourceType]`.
              - If `_activeToken.isCancelled` → break loop early.
           6. `_isRefreshing = false`; `_lastRefreshedAt = DateTime.now()`; emit `RefreshIdle`.
           7. Return `Ok(LibraryRefreshResult(adapterResults: adapterResults, completedAt: _lastRefreshedAt!))`.
         - `cancel() → void`: if `_isRefreshing`, call `_activeToken?.cancel()`, set `_isRefreshing = false`, emit `RefreshIdle`.
         - `dispose() → void`: call `cancel()`, close `_stateController` (guarded: only if not already closed).

      Files: `lib/domain/services/library_refresh_service.dart`
      Verify: `flutter analyze lib/domain/services/library_refresh_service.dart` — no issues.

- [ ] 3. Create `lib/domain/services/library_refresh_service_provider.dart`.
      Wire `LibraryRefreshService` into Riverpod. No logic here — only provider wiring.

      a. `class LibraryRefreshNotifier extends StateNotifier<RefreshState>`:
         - Constructor: creates `LibraryRefreshService(adapters: ref.read(videoSourceAdaptersProvider), scanMergeService: ref.read(scanMergeServiceProvider), preferences: const LibraryRefreshPreferences())`.
         - Subscribes to `_service.refreshState` in constructor body; stores `StreamSubscription` in a field.
         - Listener sets `state = event`.
         - `Future<Result<LibraryRefreshResult>> refresh({required RefreshTrigger trigger})` delegates to `_service.refresh(trigger: trigger)`.
         - `void cancel()` delegates to `_service.cancel()`.
         - `@override dispose()`: cancels subscription, calls `_service.dispose()`, then `super.dispose()`.

      b. `final libraryRefreshServiceProvider = StateNotifierProvider<LibraryRefreshNotifier, RefreshState>((ref) => LibraryRefreshNotifier(ref))`.
         Pass `ref` to the notifier constructor (same pattern as other Riverpod notifiers in the project that watch other providers).

      Files: `lib/domain/services/library_refresh_service_provider.dart`
      Verify: `flutter analyze lib/domain/services/library_refresh_service_provider.dart` — no issues.

- [ ] 4. Create `test/unit/domain/library_refresh_service_test.dart`.
      12 tests using `AppDatabase.inMemory()` + `DriftVideoRepository` + real `ScanMergeService` + `FakeVideoSourceAdapter` (defined at top of the test file).

      **`FakeVideoSourceAdapter`** fields:
      - `ProviderType sourceType` (constructor param)
      - `Result<SourcePage> listResult` (settable)
      - `Duration? listDelay` (simulates slow scan)
      - `bool listCalled = false`
      Methods: implement all `VideoSourceAdapter` methods; `listVideos` checks cancellation first, waits `listDelay` if set, then returns `listResult`.

      **Helper `_video(String sourceId)`**: returns `SourceVideo(sourceId: sourceId, sourceType: ProviderType.localMediaStore, displayName: sourceId)`.

      **Test structure** — each test has `setUp` creating `db`, `repo`, `scanMergeService`, and (per test) the adapter(s) and service:

      1. **Empty adapters → Ok with empty results and correct state sequence**
         Create service with `adapters: []`. Collect states from stream. Call `refresh(trigger: manual)`. Assert `result` is `Ok`, `adapterResults` is empty. Assert collected states contain `RefreshInProgress` then `RefreshIdle`.

      2. **Single adapter 2 videos → totalAdded == 2**
         Adapter returns `Ok(SourcePage(videos: [_video('a'), _video('b')]))`. Assert `result.value.totalAdded == 2`.

      3. **Throttle suppresses automatic — manual then automatic within interval**
         `preferences: LibraryRefreshPreferences(minimumRefreshInterval: Duration(hours: 1))`. First call `refresh(manual)` → Ok. Immediately call `refresh(automatic)` → result is `Err<LibraryRefreshResult>` and `error is RefreshThrottledError`.

      4. **Manual ignores throttle — manual then manual again → new scan runs**
         Same setup. First `refresh(manual)`. Then `refresh(manual)` again → result is `Ok`; `adapterResults` is populated (adapter's `listCalled` is true both times, or `totalAdded` > 0 for second call).

      5. **Concurrent refresh rejected — start slow refresh, second call returns Err**
         `listDelay = Duration(milliseconds: 100)`. Start first `refresh(manual)` without awaiting. Immediately call second `refresh(manual)`. Second returns `Err` with `error is UnexpectedError`. Await first → `Ok`.

      6. **Adapter error is isolated — one errors, one succeeds**
         Two adapters: adapter A returns `Err(UnexpectedError(...))`, adapter B returns `Ok(SourcePage(videos: [_video('x')]))`. Result is `Ok`; `adapterResults` has only adapter B's key; `state` is `RefreshIdle`.

      7. **Cancellation during delayed adapter → state returns to RefreshIdle**
         Adapter has `listDelay = Duration(milliseconds: 200)`. Start `refresh(manual)` without awaiting. After short delay call `cancel()`. Await refresh future. Assert final `state` (last emitted) is `RefreshIdle`. Assert `result` is `Ok` (cancel is not an error, just short-circuits).

      8. **State sequence — [RefreshInProgress, RefreshIdle] for normal run**
         Collect all states emitted during a refresh. Assert sequence is exactly `[RefreshInProgress, RefreshIdle]`.

      9. **Multiple adapters (2) each returning 1 video → totalAdded == 2, adapterResults has 2 keys**
         Two adapters with different `sourceType`. Each returns 1 video. Assert `totalAdded == 2`, `adapterResults.length == 2`.

      10. **Re-scan marks missing — 2 videos first scan, 1 video second scan → totalMarkedMissing == 1**
          First `refresh` with 2 videos. Change adapter to return only 1. Second `refresh`. Assert `result.value.totalMarkedMissing == 1`.

      11. **`LibraryRefreshResult` totals aggregate correctly**
          Two adapters: adapter A merges 2 added, adapter B merges 1 added. Assert `totalAdded == 3`, `totalUpdated == 0`, `totalMarkedMissing == 0`.

      12. **`dispose()` closes stream — no further events after dispose**
          Add a listener to the stream. Call `dispose()`. Assert the stream is closed (listener's `onDone` is called, or adding a new listener/listen throws, or collecting further events yields none). Practical approach: await stream `toList()` after `dispose()` to confirm it completes.

      Files: `test/unit/domain/library_refresh_service_test.dart`
      Verify: `flutter test test/unit/domain/library_refresh_service_test.dart --reporter=compact` — all 12 tests pass.

- [ ] 5. Run full quality checks.
      Run all checks the project requires per AGENTS.md:

      ```
      dart format lib/domain/models/app_error.dart lib/domain/services/library_refresh_service.dart lib/domain/services/library_refresh_service_provider.dart test/unit/domain/library_refresh_service_test.dart
      flutter analyze
      flutter test
      ```

      Confirm: no format diffs, no analyzer warnings, all tests pass (pre-existing + 12 new).
      Files: none (quality check only)
      Verify: `flutter test` exits 0; `flutter analyze` exits 0 with no issues.

- [ ] 6. Update `TASKS.md`.
      Mark P3-05 `Done` with a summary matching the definition-of-done checklist: what was implemented, which files, test counts, limitations noted (in-memory throttle, no WorkManager).
      Files: `TASKS.md`
      Verify: manual review — entry matches actual completed work; no other tasks modified.

---

## Dependency order

| Step | Depends on |
|------|-----------|
| 1    | — |
| 2    | 1 (uses `RefreshThrottledError`) |
| 3    | 2 (uses `LibraryRefreshService`, `RefreshState`, `RefreshTrigger`, `LibraryRefreshResult`) |
| 4    | 2 (tests `LibraryRefreshService` directly, not the provider) |
| 5    | 2, 3, 4 |
| 6    | 5 |

---

## Known limitations (document in TASKS.md and KDoc)

- `_lastRefreshedAt` is in-memory only; throttle resets on app process restart (LOCAL-008 — foreground only, no WorkManager).
- Adapter errors during a run are silently swallowed into a per-adapter error map rather than surfaced in `LibraryRefreshResult`. A future task (P3-06) can expose these as `adapterErrors`.
- `cancel()` does not wait for the in-flight adapter call to return; callers receive `RefreshIdle` immediately but the adapter's `Future` may still be resolving in the background before it checks `isCancelled`.
