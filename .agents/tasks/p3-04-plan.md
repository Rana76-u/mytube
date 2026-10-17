# Implementation Plan — P3-04: Merge Overlapping Scan Results

## Exploration findings

- **Current test count**: 169 passing. Target after this task: 181+ (12 new tests).
- **`uuid` package**: NOT in `pubspec.yaml`. Must be added (`uuid: ^4.5.1`, MIT, pure Dart, no transitive deps).
- **`videoRepositoryProvider`**: defined in `lib/data/repositories/repository_providers.dart` (not a separate `video_repository_provider.dart` file).
- **`AppDatabase.inMemory()`**: exists in `lib/data/database/app_database.dart` — uses `NativeDatabase.memory()`.
- **`domain/services/` directory**: does not yet exist; must be created.
- **`SourceLocationsDao`**: missing `getByProviderType` and `updateMetadata` methods — both must be added.
- **`VideoRepository` interface**: missing source-location and insert methods — must be extended.
- **`DriftVideoRepository`**: only wraps `VideoItemsDao`; must also hold `SourceLocationsDao` and implement new methods.
- **`SourceLocation` domain type**: not yet defined in `video_repository.dart`; must be added there (no Drift imports allowed in domain).
- **`VideoItemInsert` / `SourceLocationInsert`**: not yet defined; go in `video_repository.dart`.
- **`SourceLocationsDao` generated file** (`source_locations_dao.g.dart`): adding methods to the DAO requires regenerating it — run `dart run build_runner build --delete-conflicting-outputs`.
- **`AvailabilityState` serialization**: stored as enum `.name` (e.g. `"available"`) per `source_locations_table.dart` comment. Deserialize with `AvailabilityState.values.byName(str)`.
- **`ProviderType` serialization**: same pattern — stored as `.name`, deserialize with `ProviderType.values.byName(str)`.
- **Test pattern for DB**: `setUp(() { db = AppDatabase.inMemory(); })` + `tearDown(() async { await db.close(); })` — used consistently across all database tests.
- **`DriftVideoRepository` constructor**: takes `AppDatabase`, not just a DAO — can be changed to also accept `db.sourceLocationsDao`.
- **No Flutter imports in domain services**: `ScanMergeService` and its provider file import only `package:mytube/*` and `package:flutter_riverpod` (the provider file only).

---

## Plan

- [ ] 1. Add `uuid: ^4.5.1` to `pubspec.yaml` and run `flutter pub get`.
      The UUID package is needed by `ScanMergeService` to generate stable IDs for new `VideoItem` and `SourceLocation` rows. It is MIT-licensed, pure Dart, and is the standard Flutter ecosystem choice.
      Files: `pubspec.yaml`
      Verify: `flutter pub get` exits 0 and `uuid` appears in `pubspec.lock`.

- [ ] 2. Add domain value types and new abstract methods to `VideoRepository`.
      Add `SourceLocation`, `VideoItemInsert`, and `SourceLocationInsert` classes to `video_repository.dart` (pure Dart, no Drift imports). Then extend the `VideoRepository` abstract interface with five new method signatures:
      ```
      Future<Result<List<SourceLocation>>> getSourceLocationsByProvider(ProviderType providerType);
      Future<Result<String>> insertVideoItem(VideoItemInsert item);
      Future<Result<String>> insertSourceLocation(SourceLocationInsert location);
      Future<Result<void>> updateSourceLocationAvailability(String id, AvailabilityState availability, DateTime lastCheckedAt);
      Future<Result<void>> updateSourceLocationMetadata(String id, {String? displayName, int? durationMs, AvailabilityState? availability, DateTime? lastCheckedAt});
      ```
      Notes on `VideoItemInsert`: fields are `id`, `title`, `durationMs`, `widthPx`, `heightPx`, `createdAt`, `updatedAt` (no `mimeType`/`sizeBytes` — those go on `SourceLocationInsert`).
      Notes on `SourceLocationInsert`: fields are `id`, `videoItemId`, `providerType`, `sourceUri`, `displayName`, `mimeType`, `sizeBytes`, `availability`, `lastCheckedAt`, `createdAt`, `updatedAt`. `sourceUri` maps to the `sourceId` column in Drift.
      Notes on `SourceLocation` (domain read model): `id`, `videoItemId`, `providerType`, `sourceUri` (maps from Drift `sourceId`), `displayName`, `availability`, `lastCheckedAt`.
      Files: `lib/domain/repositories/video_repository.dart`
      Verify: `flutter analyze` reports no new errors.

- [ ] 3. Add `getByProviderType` and `updateMetadata` to `SourceLocationsDao`, then regenerate Drift code.
      Add two new DAO methods:
      ```dart
      Future<List<SourceLocation>> getByProviderType(String providerType) =>
          (select(sourceLocations)..where((t) => t.providerType.equals(providerType))).get();

      Future<void> updateMetadata({
        required String id,
        String? displayName,
        int? durationMs,   // NOTE: durationMs is NOT on source_locations table — omit from this DAO method; see note below
        String? availability,
        int? lastCheckedAt,
      }) {
        final now = DateTime.now().millisecondsSinceEpoch;
        return (update(sourceLocations)..where((t) => t.id.equals(id))).write(
          SourceLocationsCompanion(
            displayName: displayName != null ? Value(displayName) : const Value.absent(),
            availability: availability != null ? Value(availability) : const Value.absent(),
            lastCheckedAt: lastCheckedAt != null ? Value(lastCheckedAt) : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
      }
      ```
      **Important**: `durationMs` is NOT a column on `source_locations` — it is on `video_items`. The `VideoRepository.updateSourceLocationMetadata` interface signature accepts `durationMs` for API symmetry but the DAO method does NOT write it to `source_locations`. The `DriftVideoRepository` implementation must ignore `durationMs` in this call (it does not update `video_items.durationMs` either — user-owned metadata is never overwritten by scans).
      After editing the DAO, run: `dart run build_runner build --delete-conflicting-outputs`
      Files: `lib/data/database/daos/source_locations_dao.dart`, `lib/data/database/daos/source_locations_dao.g.dart` (generated)
      Verify: `dart run build_runner build --delete-conflicting-outputs` exits 0 with no errors; `flutter analyze` clean.

- [ ] 4. Extend `DriftVideoRepository` to implement the five new interface methods.
      Change the constructor to accept `AppDatabase` (already does) and add `_sourceLocationsDao` from `db.sourceLocationsDao`. Implement:
      - `getSourceLocationsByProvider`: calls `_sourceLocationsDao.getByProviderType(providerType.name)`, maps each Drift `SourceLocation` row to the domain `SourceLocation` (use `AvailabilityState.values.byName(row.availability)` for deserialization; map `row.sourceId` → `sourceUri`).
      - `insertVideoItem`: calls `_videoItemsDao.upsertItem(VideoItemsCompanion.insert(...))`, returns `Ok(item.id)`.
      - `insertSourceLocation`: calls `_sourceLocationsDao.upsertLocation(SourceLocationsCompanion.insert(...))`, maps `location.sourceUri` → `sourceId`, `location.providerType.name` → `providerType`, `location.availability.name` → `availability`; returns `Ok(location.id)`.
      - `updateSourceLocationAvailability`: calls `_sourceLocationsDao.updateAvailability(id: id, availability: availability.name, checkedAt: lastCheckedAt.millisecondsSinceEpoch)`.
      - `updateSourceLocationMetadata`: calls `_sourceLocationsDao.updateMetadata(id: id, displayName: displayName, availability: availability?.name, lastCheckedAt: lastCheckedAt)`. `durationMs` is silently dropped (not a source_locations column).
      Wrap each in try/catch returning `UnexpectedError` on failure.
      Files: `lib/data/repositories/drift_video_repository.dart`
      Verify: `flutter analyze` reports no errors; existing `drift_video_repository_test.dart` still passes.

- [ ] 5. Create `lib/domain/services/scan_merge_service.dart` with `ScanMergeService` and `ScanMergeResult`.
      Implement the algorithm exactly as specified:
      1. `getSourceLocationsByProvider(providerType)` → build `existingBySourceUri` map.
      2. For each scanned video (check cancellation every 50 items): if URI exists → `updateSourceLocationMetadata`; else → `insertVideoItem` + `insertSourceLocation`.
      3. After loop: for unseen URIs → `updateSourceLocationAvailability(..., AvailabilityState.missing, DateTime.now())`.
      4. Return `Ok(ScanMergeResult(...))`.
      Key rules:
      - Generate UUIDs with `Uuid().v4()` from the `uuid` package (import `package:uuid/uuid.dart`).
      - No Flutter imports, no Riverpod imports.
      - `availability` for new inserts: if `video.availability == AvailabilityState.unknown` use `AvailabilityState.available`, otherwise use `video.availability`.
      - Never delete rows; never touch `isFavourite`, `watchProgressMs`, `lastPlayedAt`.
      - All public methods return `Result<T>`.
      Files: `lib/domain/services/scan_merge_service.dart` (new file, new directory `lib/domain/services/`)
      Verify: `flutter analyze` reports no errors.

- [ ] 6. Create `lib/domain/services/scan_merge_service_provider.dart` with the Riverpod provider.
      ```dart
      import 'package:flutter_riverpod/flutter_riverpod.dart';
      import 'package:mytube/data/repositories/repository_providers.dart';
      import 'package:mytube/domain/services/scan_merge_service.dart';

      final scanMergeServiceProvider = Provider<ScanMergeService>((ref) {
        return ScanMergeService(repository: ref.watch(videoRepositoryProvider));
      });
      ```
      Files: `lib/domain/services/scan_merge_service_provider.dart` (new file)
      Verify: `flutter analyze` reports no errors.

- [ ] 7. Create `test/unit/domain/scan_merge_service_test.dart` with 12 tests.
      Use `AppDatabase.inMemory()` + `DriftVideoRepository(db)` — no mocks. Structure:
      ```
      group('ScanMergeService (P3-04)', () {
        late AppDatabase db;
        late DriftVideoRepository repo;
        late ScanMergeService service;
        setUp(() {
          db = AppDatabase.inMemory();
          repo = DriftVideoRepository(db);
          service = ScanMergeService(repository: repo);
        });
        tearDown(() async { await repo.dispose(); await db.close(); });
        ...
      });
      ```
      The 12 tests to implement (each maps to one `test(...)` call):
      1. **Empty scan + empty DB**: `mergeResults(scannedVideos: [], ...)` → `ScanMergeResult(added:0, updated:0, markedMissing:0)`.
      2. **3 new videos**: `added == 3`; verify DB has 3 `video_items` rows and 3 `source_locations` rows via `db.select(db.videoItems).get()` and `db.select(db.sourceLocations).get()`.
      3. **2 existing re-scanned**: pre-insert 2 rows; re-scan same 2 URIs → `added:0, updated:2, markedMissing:0`; check `source_locations.availability == 'available'`; check `video_items` title unchanged.
      4. **1 of 2 disappears**: pre-insert 2; scan returns only 1 → `added:0, updated:1, markedMissing:1`; missing row has `availability == 'missing'`; `video_items` still has 2 rows.
      5. **Mixed**: pre-insert 2, scan sends 2 existing + 1 new + 1 missing → `added:1, updated:2, markedMissing:1`.
      6. **User metadata preserved**: insert item with `isFavourite = true` (via `db.into(db.videoItems).insert(...)`); re-scan same URI → `isFavourite` still `true` after merge (check with `dao.getItemById`).
      7. **Cross-provider isolation**: insert a `localMediaStore` SourceLocation and an `oneDrive` SourceLocation both belonging to same VideoItem; run merge for `localMediaStore` without the `oneDrive` sourceId → `oneDrive` location NOT marked missing (still `'unknown'` or whatever it started as).
      8. **Idempotent re-scan**: run `mergeResults` twice with same 2-video input → after second run, still exactly 2 `video_items` rows and 2 `source_locations` rows.
      9. **Cancellation before loop**: pre-cancel token; call `mergeResults` → returns `Ok` quickly; `added == 0`.
      10. **Availability restored**: mark a source location as `missing` via `db.update(db.sourceLocations)...`; re-scan with it present → `availability == 'available'`.
      11. **DisplayName update; title NOT overwritten**: pre-insert video item with title `'Original Title'`; re-scan with same sourceId but `displayName: 'New Name'` → `source_locations.displayName == 'New Name'`; `video_items.title` still `'Original Title'`.
      12. **Large batch (100 items)**: scan 100 fresh URIs → `added == 100`; DB has 100 `video_items` rows.
      Files: `test/unit/domain/scan_merge_service_test.dart` (new file, new directory `test/unit/domain/`)
      Verify: `flutter test test/unit/domain/scan_merge_service_test.dart` — all 12 tests pass.

- [ ] 8. Run full formatter, analyzer, and test suite; fix any issues found.
      Commands (run in order):
      ```
      dart format .
      flutter analyze
      flutter test
      ```
      Expected outcome: `dart format .` makes no changes or only whitespace; `flutter analyze` reports `No issues found!`; `flutter test` shows `181+ tests passed` (169 existing + 12 new).
      Fix any root-cause issues before proceeding.
      Files: any files with format/analysis issues
      Verify: all three commands exit 0.

- [ ] 9. Mark P3-04 Done in `TASKS.md`.
      Replace the P3-04 Todo entry with:
      ```
      -   [x] **P3-04** Merge overlapping scan results without losing source
          locations. --- Done (`ScanMergeService` domain service; merges
          `SourceVideo` scan results into DB; creates new VideoItem+SourceLocation
          pairs for new items; updates availability/metadata for existing items;
          marks unseen sources `missing` without deleting rows or user metadata;
          cross-provider isolation; `scanMergeServiceProvider`; new repository
          methods added to interface + DriftVideoRepository; 12 unit tests;
          analyzer + format clean)
      ```
      Files: `TASKS.md`
      Verify: `TASKS.md` shows P3-04 as `[x]` Done.

---

## Key decisions and rationale

**uuid package**: The codebase has no existing UUID generator. `uuid: ^4.5.1` is the standard Flutter/Dart choice — MIT license, pure Dart, actively maintained. Alternative of `dart:math`-based UUID v4 would require a bespoke utility and is harder to audit for correctness.

**`durationMs` in `updateSourceLocationMetadata`**: The interface accepts it for forward compatibility (future cloud adapters may return duration), but `source_locations` has no `duration_ms` column. The DAO method omits it, and the repository implementation silently drops it. This avoids a misleading no-op but keeps the API honest about what callers can express. Adding `durationMs` to `video_items` on re-scan is intentionally out of scope — P3-07 covers user-owned metadata policy.

**Real DB in tests (no mocks)**: Using `AppDatabase.inMemory()` + `DriftVideoRepository` gives real SQL semantics (foreign keys, cascade, constraints), matching the pattern established by `migrations_test.dart` and `drift_video_repository_test.dart`. Mocking the repository would weaken the tests and defeat the purpose of verifying the merge algorithm end-to-end.

**`SourceLocation` domain type lives in `video_repository.dart`**: Keeping domain value types co-located with the repository interface they serve is the existing pattern (`VideoItemSummary`, `ProgressSnapshot` are all in `video_repository.dart`). It keeps the domain layer self-contained and avoids a proliferation of single-type files.

**No schema migration needed**: The new DAO methods (`getByProviderType`, `updateMetadata`) are pure query/update additions — no new columns or tables. Schema version stays at 4.

**`build_runner` must run after DAO changes**: Drift's `@DriftAccessor` generates `_$SourceLocationsDaoMixin` via code gen. Adding methods to the DAO body does NOT require regeneration (only the `part` file needs to be consistent), but `insertOnConflictUpdate` and new query methods added via Drift macros would. Since `updateMetadata` uses `(update(sourceLocations)..where(...)).write(...)` (plain Drift API, not a `@query` macro), regeneration is only needed if the existing `.g.dart` is stale. Run it anyway to be safe.
