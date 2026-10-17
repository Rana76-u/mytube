# P3-07 & P3-08 Implementation Report

_Generated after implementation — all checks passed._

---

## What was implemented

### P3-07 — Preserve user-owned metadata during rescans

**Fix 1: DAO insert semantic change (`VideoItemsDao`)**

Changed `upsertItem` (which used `insertOnConflictUpdate`) to
`insertItemOrIgnore` (which uses `InsertMode.insertOrIgnore`). When
`insertVideoItem` is called with the ID of an existing row, the call is now
a strict no-op — the existing row is left completely untouched. This closes
the latent title-overwrite bug identified in the scope investigation (Gap 1).

The new method docstring explicitly states: _"Inserts a new video item row. If
a row with the same `id` already exists, this is a no-op — user-owned fields
(title, isFavourite, watchProgressMs, lastPlayedAt) are never overwritten."_

**Fix 2: Repository caller update (`DriftVideoRepository`)**

Updated `insertVideoItem` to call `_dao.insertItemOrIgnore(...)` instead of the
removed `_dao.upsertItem(...)`.

### P3-08 — Test indexing and verify on Android devices

**6 new unit tests** added to three existing test files:

| # | Test name | File | Gap closed |
|---|---|---|---|
| 1 | `watchProgressMs is not overwritten by re-scan` | `scan_merge_service_test.dart` | Gap 2 |
| 2 | `lastPlayedAt is not overwritten by re-scan` | `scan_merge_service_test.dart` | Gap 3 |
| 3 | `insertVideoItem called twice with same id does not overwrite user fields` | `scan_merge_service_test.dart` | Gap 6 / Fix 1 contract |
| 4 | `tags and collection memberships survive a rescan` | `scan_merge_service_test.dart` | Gap 5 |
| 5 | `user metadata survives a full LibraryRefreshService refresh cycle` | `library_refresh_service_test.dart` | End-to-end pipeline |
| 6 | `insertVideoItem with duplicate id is a no-op for existing user fields` | `drift_video_repository_test.dart` | Repository-level contract |

**Device testing checklist** created at `docs/device_testing_p3.md` covering:
- Target device: CPH2719 (Android 16, API 36)
- API level permission matrix (24–32, 33, 34+)
- 7 manual test scenarios
- Automation boundary statement
- Integration test deferral note

---

## Files created or modified

| File | Action |
|---|---|
| `lib/data/database/daos/video_items_dao.dart` | Modified — `upsertItem` → `insertItemOrIgnore` with `InsertMode.insertOrIgnore` |
| `lib/data/repositories/drift_video_repository.dart` | Modified — caller updated to `_dao.insertItemOrIgnore(...)` |
| `test/unit/domain/scan_merge_service_test.dart` | Modified — 4 new tests added (tests 13–16) |
| `test/unit/domain/library_refresh_service_test.dart` | Modified — 1 new test added (test 13); `Value` import added |
| `test/unit/database/drift_video_repository_test.dart` | Modified — 1 new test added; `Value` import added |
| `docs/device_testing_p3.md` | Created — manual testing checklist for Phase 3 device verification |
| `.agents/tasks/p3-07-p3-08-report.md` | Created — this report |
| `TASKS.md` | Updated — P3-07 and P3-08 marked complete |

Generated files updated automatically by build_runner:
- `lib/data/database/daos/video_items_dao.g.dart`
- (Other `.g.dart` files re-emitted as unchanged)

---

## Commands executed and their results

### 1. Code generation
```
dart run build_runner build --delete-conflicting-outputs
```
Result: `Built with build_runner/aot in 7s with warnings; wrote 85 outputs.`
(Warnings are from removed `--delete-conflicting-outputs` flag in current
build_runner version — not errors.)

### 2. Formatter
```
dart format .
```
Result: `Formatted 82 files (0 changed) in 0.27 seconds.`

### 3. Static analysis
```
flutter analyze
```
Result: `No issues found! (ran in 1.5s)`

### 4. Database unit tests
```
flutter test test/unit/database/
```
Result: `All tests passed!` (62 tests)

### 5. Domain unit tests
```
flutter test test/unit/domain/
```
Result: `All tests passed!` (39 tests)

### 6. Full test suite
```
flutter test
```
Result: `All tests passed!` — **212 tests** (206 prior + 6 new)

---

## Known limitations and unresolved issues

1. **Device testing not yet performed.** The 7 manual scenarios in
   `docs/device_testing_p3.md` require the physical CPH2719 device. P3-08 is
   marked done for its automated scope; device verification is a prerequisite
   for marking Phase 3 complete overall.

2. **`test/integration/` deferred.** No integration test directory was created.
   This is deliberate per DECISIONS.md §P0-01 and the scope document.

3. **`thumbnailCacheKey` field does not exist.** Confirmed out-of-scope for P3-07
   (field is not in the schema). No action needed.

4. **Title update via `VideoItems` has no dedicated `updateTitle` method.** This
   is intentional — title editing belongs to P5. The current behavior (title set
   at insert, never overwritten by scans) is correct for Phase 3.

---

## Whether the task is ready for review

**Yes.** All automated acceptance criteria are satisfied:

- [x] `insertItemOrIgnore` replaces `upsertItem`; semantics enforced at DAO level
- [x] `isFavourite`, `watchProgressMs`, `lastPlayedAt`, `title`, tags, collection memberships all tested
- [x] 6 new tests all pass
- [x] Total test count: 212 (≥ 212 required)
- [x] `flutter analyze` — no issues
- [x] `dart format .` — no changes
- [x] No secrets, no unintended deletion behaviour, no unrelated refactors
- [x] `docs/device_testing_p3.md` created
- [x] `TASKS.md` updated for P3-07 and P3-08

Remaining prerequisite before Phase 3 is fully complete: manual device testing
on CPH2719 per the checklist in `docs/device_testing_p3.md`.
