# Implementation Plan — P3-03: Local Source Adapter

## Context from exploration

- **Dart SDK**: `^3.12.2`; **Flutter Riverpod**: `^3.4.3`
- **Test runner**: `flutter test` (155 tests passing before this change)
- **Formatter**: `dart format .`
- **Analyser**: `flutter analyze`
- **Existing adapter contract**: `lib/sources/source_adapter.dart` defines
  `VideoSourceAdapter`, `SourceCapabilities`, `SourcePage`, `SourceVideo`,
  `PlayableSource`, `DownloadEligibility`, and `CancellationToken`.
- **ProviderType** lives in `lib/domain/repositories/video_repository.dart`.
- **Result<T>/Ok/Err** in `lib/core/result.dart`; `AppError` sealed hierarchy
  in `lib/domain/models/app_error.dart`.
- **MediaStoreBridge** (interface + `MediaStoreVideo`) in
  `lib/platform/media_store_bridge.dart`. Returns `PermissionDeniedError` on
  permission failure; never throws.
- **SafBridge** (interface + `SafVideo`) in `lib/platform/saf_bridge.dart`.
  `listVideosInFolder` returns `PermissionDeniedError` when the grant is
  revoked; `getPersistedFolderUris` returns the list of folder URIs.
- **Riverpod providers**: `mediaStoreBridgeProvider` and `safBridgeProvider`
  in `lib/platform/platform_providers.dart`.
- `lib/sources/` currently contains only `source_adapter.dart`; no `local/`
  subdirectory or `source_registry.dart` yet.
- Platform bridge tests (`saf_bridge_impl_test.dart`,
  `media_store_bridge_impl_test.dart`) use `MethodChannel` mocks — the new
  tests must NOT; they use fake bridge implementations passed via constructor
  injection.
- `lib/platform/media_store_bridge_impl.dart` imports `package:flutter`
  (MethodChannel). `LocalMediaAdapter` must **not** import `package:flutter`
  to stay framework-light and testable without `TestWidgetsFlutterBinding`.

## Design decisions

1. **Constructor injection over Riverpod read inside the adapter.** The
   adapter receives `MediaStoreBridge` and `SafBridge` as constructor
   parameters. The Riverpod provider (in the same `local/` directory) wires
   them up. This keeps the adapter a plain Dart class that can be
   instantiated in unit tests with fakes.

2. **Single class, two `ProviderType` values.** `LocalMediaAdapter` returns
   `ProviderType.localMediaStore` from `get sourceType` (the primary type).
   Videos discovered via SAF are tagged `ProviderType.selectedFolder`. One
   class handles both because the deduplication and merging logic is shared.

3. **Deduplication key: SAF URI == MediaStore `contentUri`.** ARCHITECTURE §5
   requires combining sources for the same logical item. The only overlap
   detectable at this layer without a full duplicate-matching pass (P3-04) is
   when a SAF document URI exactly matches a MediaStore `contentUri`. In that
   case the MediaStore version wins (already in the combined list). This is a
   conservative rule: ambiguous matches stay separate as required.

4. **MediaStore URI prefix for routing.** `content://media/` is the stable
   prefix for all Android MediaStore content URIs. `getVideo` and
   `checkAvailability` use this prefix to route to the correct bridge without
   persisting provider metadata in the `sourceId`.

5. **`source_registry.dart` location**: `lib/sources/source_registry.dart` as
   prescribed by ARCHITECTURE §2. A single Riverpod `Provider` that returns
   `List<VideoSourceAdapter>`. This file is a thin wiring layer; no logic.

6. **No `package:flutter` import in `LocalMediaAdapter`.** The impl files for
   the bridges import Flutter; the adapter only calls the bridge interface,
   which is pure Dart. Verified by inspection: `media_store_bridge.dart` and
   `saf_bridge.dart` import only `package:mytube/...`.

7. **`checkAvailability` for SAF URIs**: iterate persisted folders and call
   `listVideosInFolder` on each until the URI is found. Return
   `AvailabilityState.permissionRevoked` when `PermissionDeniedError` is
   returned for the owning folder. Return `AvailabilityState.missing` when no
   folder produces the URI.

---

## Plan

- [ ] 1. Create `lib/sources/local/local_media_adapter.dart` — the
      `LocalMediaAdapter` class implementing `VideoSourceAdapter`.

  **Constructor**: `LocalMediaAdapter({required MediaStoreBridge
  mediaStore, required SafBridge saf})`.

  **`get sourceType`** → `ProviderType.localMediaStore`.

  **`getCapabilities()`** → `SourceCapabilities(canStream: true, canSeek:
  true, canProvideThumbnail: true)` (all others default to `false`).

  **`listVideos()`** logic (in order, checking
  `cancellationToken.isCancelled` before each async step):
  1. If cancelled on entry, return `Ok(SourcePage(videos: []))`.
  2. Call `mediaStore.queryVideos()`. If `PermissionDeniedError`, skip and
     continue with an empty MediaStore list. Any other `Err` → propagate
     (`return result.map(...)` / return the `Err` as-is after casting).
  3. Check cancellation.
  4. Call `saf.getPersistedFolderUris()`. If `Err`, propagate.
  5. For each folder URI, check cancellation, then call
     `saf.listVideosInFolder(uri)`. If `PermissionDeniedError`, skip that
     folder and continue. Other `Err` → propagate.
  6. Build a combined `List<SourceVideo>`: first all MediaStore videos
     (mapped to `SourceVideo` with `sourceType: ProviderType.localMediaStore`
     and `sourceId: msVideo.contentUri`), then SAF videos not already in the
     set of MediaStore `contentUri` values (mapped with `sourceType:
     ProviderType.selectedFolder` and `sourceId: safVideo.uri`).
  7. Return `Ok(SourcePage(videos: combined))`.

  **`getVideo(sourceId)`**:
  - If `sourceId.startsWith('content://media/')`, call
    `mediaStore.queryVideos()`, find matching `contentUri`, return `Ok(video)`
    or `Ok(null)`.
  - Otherwise iterate `saf.getPersistedFolderUris()` and then
    `saf.listVideosInFolder(uri)` for each, searching for `safVideo.uri ==
    sourceId`. Return `Ok(video)` or `Ok(null)`.
  - Any bridge `Err` → propagate.

  **`checkAvailability(sourceId)`**:
  - MediaStore path (`content://media/`): call `queryVideos()`; if
    `PermissionDeniedError` → `Ok(AvailabilityState.permissionRevoked)`;
    other `Err` → propagate; found → `Ok(available)`; not found →
    `Ok(missing)`.
  - SAF path: get persisted folders; for each call `listVideosInFolder`;
    if `PermissionDeniedError` skip (it's a candidate revoked folder but
    we don't know if the item was in it); if item found → `Ok(available)`.
    After all folders exhausted without finding item, attempt
    `saf.checkFolderAccess` for completeness is not needed — return
    `Ok(missing)`. If `getPersistedFolderUris` returns `Err` →
    propagate. **Special case**: if every folder returned
    `PermissionDeniedError` and the item was not found, return
    `Ok(AvailabilityState.permissionRevoked)`.

  **`resolveForPlayback(sourceId)`**: call `getVideo(sourceId)` to obtain
  `mimeType`; return `Ok(PlayableSource(uri: Uri.parse(sourceId), sourceId:
  sourceId, sourceType: ProviderType.localMediaStore, mimeType: ..., canSeek:
  true))`. If `getVideo` returns `Err` → propagate. Use
  `ProviderType.localMediaStore` for MediaStore URIs and
  `ProviderType.selectedFolder` for SAF URIs (detect by same
  `content://media/` prefix rule).

  **`checkDownloadEligibility(sourceId)`**: always return
  `Ok(DownloadEligibility.prohibited)`.
  Comment: "Local files are originals — downloading is not applicable."

  **No `package:flutter` import.** Only `dart:*` and
  `package:mytube/...` imports.

  Files: `lib/sources/local/local_media_adapter.dart`

  Verify: `dart format lib/sources/local/local_media_adapter.dart`
  completes without changes; `flutter analyze lib/sources/local/` reports
  no issues.

---

- [ ] 2. Create `lib/sources/local/local_media_adapter_provider.dart` —
      Riverpod provider.

  ```dart
  final localMediaAdapterProvider = Provider<LocalMediaAdapter>(
    (ref) => LocalMediaAdapter(
      mediaStore: ref.watch(mediaStoreBridgeProvider),
      saf: ref.watch(safBridgeProvider),
    ),
  );
  ```

  Import `flutter_riverpod`, `platform_providers.dart`, and
  `local_media_adapter.dart`. This is the **only** file in `sources/local/`
  that imports `package:flutter_riverpod`.

  Files: `lib/sources/local/local_media_adapter_provider.dart`

  Verify: `flutter analyze lib/sources/local/` — no issues.

---

- [ ] 3. Create `lib/sources/source_registry.dart`.

  ```dart
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:mytube/sources/source_adapter.dart';
  import 'package:mytube/sources/local/local_media_adapter_provider.dart';

  /// All registered source adapters, in priority order (ARCHITECTURE §6).
  final videoSourceAdaptersProvider = Provider<List<VideoSourceAdapter>>(
    (ref) => [ref.watch(localMediaAdapterProvider)],
  );
  ```

  Files: `lib/sources/source_registry.dart`

  Verify: `flutter analyze lib/sources/` — no issues.

---

- [ ] 4. Create `test/unit/sources/local_media_adapter_test.dart` with 14
      tests.

  **Fakes** (defined at the top of the test file, not in separate files):

  ```dart
  class FakeMediaStoreBridge implements MediaStoreBridge {
    Result<List<MediaStoreVideo>> videosResult = Ok(const []);
    MediaStorePermissionStatus permStatus = MediaStorePermissionStatus.granted;

    @override
    Future<Result<List<MediaStoreVideo>>> queryVideos() async => videosResult;

    @override
    Future<MediaStorePermissionStatus> checkPermission() async => permStatus;

    @override
    Future<MediaStorePermissionStatus> requestPermission() async => permStatus;
  }

  class FakeSafBridge implements SafBridge {
    Result<List<String>> persistedUrisResult = Ok(const []);
    // folderResults maps folder URI -> Result<List<SafVideo>>
    Map<String, Result<List<SafVideo>>> folderResults = {};

    @override
    Future<Result<String?>> openFolderPicker() async => Ok(null);

    @override
    Future<Result<List<String>>> getPersistedFolderUris() async =>
        persistedUrisResult;

    @override
    Future<Result<void>> releasePersistedUri(String uri) async => Ok(null);

    @override
    Future<Result<List<SafVideo>>> listVideosInFolder(String folderUri) async =>
        folderResults[folderUri] ?? Ok(const []);

    @override
    Future<Result<bool>> checkFolderAccess(String uri) async => Ok(true);
  }
  ```

  **Test group**: `group('LocalMediaAdapter (P3-03)', ...)`.

  No `TestWidgetsFlutterBinding.ensureInitialized()` needed (no Flutter
  widgets).

  **14 tests** (each creates `FakeMediaStoreBridge`, `FakeSafBridge`, and
  `LocalMediaAdapter(mediaStore: fake, saf: fakeSaf)` locally or in
  `setUp`):

  1. **`getCapabilities() returns correct flags`** — assert `canStream`,
     `canSeek`, `canProvideThumbnail` are true; `canSearch`, `canDownload`,
     `supportsPagination` are false.

  2. **`listVideos() MediaStore only — 2 videos, no SAF folders`** — set
     `fake.videosResult` to 2 `MediaStoreVideo` items; `fakeSaf.persistedUrisResult`
     = `Ok([])`. Assert result is `Ok`, `videos.length == 2`, first video
     `sourceType == ProviderType.localMediaStore`, `sourceId` equals the
     MediaStore `contentUri`, `displayName` maps correctly.

  3. **`listVideos() SAF only — MediaStore PermissionDenied, 1 SAF folder 2
     videos`** — set `fake.videosResult = Err(PermissionDeniedError(...))`;
     `fakeSaf.persistedUrisResult = Ok(['folder1'])`;
     `fakeSaf.folderResults['folder1'] = Ok([safVideo1, safVideo2])`. Assert
     `Ok`, `videos.length == 2`, both `sourceType == ProviderType.selectedFolder`.

  4. **`listVideos() combined — deduplication keeps MediaStore version`** —
     set 1 MediaStore video with `contentUri = 'content://media/external/video/media/1'`;
     1 SAF folder with 2 videos: one has `uri = 'content://media/external/video/media/1'`
     (same as MediaStore), one has a distinct SAF URI. Assert `Ok`,
     `videos.length == 2` (not 3), both entries present, the shared URI has
     `sourceType == ProviderType.localMediaStore` (not `selectedFolder`).

  5. **`listVideos() cancelled before start returns early`** — create a
     `CancellationToken`, call `token.cancel()`, then call `listVideos`. Assert
     `Ok` with `videos` empty (or assert the bridges were never called by
     checking fake call-count if tracked, but asserting empty result is
     sufficient).

  6. **`listVideos() SAF folder permission revoked — skips folder, returns
     videos from remaining folder`** — `persistedUrisResult = Ok(['f1', 'f2'])`;
     `folderResults['f1'] = Err(PermissionDeniedError(...))`;
     `folderResults['f2'] = Ok([safVideo])`. Assert `Ok`, `videos.length == 1`.

  7. **`listVideos() non-permission error from MediaStore propagates`** — set
     `fake.videosResult = Err(UnexpectedError(...))`. Assert result `isErr`.

  8. **`getVideo() found in MediaStore`** — set 2 MediaStore videos; call
     `getVideo('content://media/external/video/media/42')`. Assert `Ok`,
     returned `SourceVideo` is non-null, `sourceId` matches, `displayName`
     matches, `sourceType == ProviderType.localMediaStore`.

  9. **`getVideo() not found returns Ok(null)`** — set 0 MediaStore videos
     and no SAF folders; call `getVideo('content://media/external/video/media/99')`.
     Assert `Ok(null)`.

  10. **`checkAvailability() available — item present in MediaStore`** — set
      1 MediaStore video with the target URI; assert
      `Ok(AvailabilityState.available)`.

  11. **`checkAvailability() missing — item not in results`** — set empty
      bridges; assert `Ok(AvailabilityState.missing)`.

  12. **`checkAvailability() permission revoked — MediaStore returns
      PermissionDenied`** — set `fake.videosResult = Err(PermissionDeniedError(...))`;
      call `checkAvailability('content://media/external/video/media/1')`.
      Assert `Ok(AvailabilityState.permissionRevoked)`.

  13. **`resolveForPlayback() returns Ok(PlayableSource) with correct fields`**
      — set 1 MediaStore video with `mimeType = 'video/mp4'`; call
      `resolveForPlayback('content://media/external/video/media/1')`. Assert
      `Ok`, `uri == Uri.parse('content://media/external/video/media/1')`,
      `canSeek == true`, `mimeType == 'video/mp4'`,
      `sourceType == ProviderType.localMediaStore`.

  14. **`checkDownloadEligibility() always returns prohibited`** — call with
      any sourceId; assert `Ok(DownloadEligibility.prohibited)`.

  Files: `test/unit/sources/local_media_adapter_test.dart`

  Verify: `flutter test test/unit/sources/` — 14 new tests, all pass.

---

- [ ] 5. Run the full verification suite and confirm no regressions.

  Commands to run in order (from the project root):

  ```
  dart format .
  flutter analyze
  flutter test test/unit/sources/
  flutter test
  ```

  Expected outcomes:
  - `dart format .` — exits 0, no files reformatted (or only the new files).
  - `flutter analyze` — "No issues found." (0 errors, 0 warnings, 0 infos).
  - `flutter test test/unit/sources/` — 14 tests, all pass.
  - `flutter test` — all tests pass; total count increases from 155 to
    **169** (14 new tests).

  If any step fails, fix the root cause before proceeding. Do not suppress
  warnings with `// ignore:` unless the suppression is already established
  project practice (e.g., the existing `unused_element` suppression in
  `media_store_bridge_impl.dart`).

---

- [ ] 6. Update `TASKS.md` — mark P3-03 as Done.

  Change the P3-03 line from:

  ```
  - [ ] **P3-03** Implement local source adapter and capabilities. ---
        Todo
  ```

  to:

  ```
  - [x] **P3-03** Implement local source adapter and capabilities. ---
        Done (LocalMediaAdapter; listVideos deduplication MediaStore +
        SAF; SourceCapabilities; source_registry.dart; localMediaAdapterProvider;
        14 unit tests; analyzer + format clean)
  ```

  Only mark complete after item 5 (full verification) passes.

  Files: `TASKS.md`

  Verify: visual inspection — the checkbox is `[x]` and the description
  is accurate.
