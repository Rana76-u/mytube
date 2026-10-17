# Implementation Plan — P3-01 & P3-02

Tasks: Android MediaStore video discovery/metadata bridge + SAF folder
selection and persistable access.

---

## Context and design decisions

### Channel names
- MediaStore channel: `com.example.mytube/media_store` — matches namespace in
  `build.gradle.kts` (`com.example.mytube`) and is the most natural per-plugin
  convention. SAF channel: `com.example.mytube/saf`. Both are Kotlin
  `MethodChannel`s registered in `MainActivity.configureFlutterEngine`.

**Rationale:** Flutter's recommended pattern for one-shot request/response
calls is `MethodChannel`; `EventChannel` is for streams. Both operations
(query, permission check, folder pick) are request-response, so
`MethodChannel` is the right fit.

### Permission handling across API levels
- API 24–32: declare `READ_EXTERNAL_STORAGE` (maxSdk 32 to avoid redundant
  grant on API 33+).
- API 33+: declare `READ_MEDIA_VIDEO`.
- API 34+: also declare `READ_MEDIA_VISUAL_USER_SELECTED`.
- The Kotlin side reads `Build.VERSION.SDK_INT` at runtime to decide which
  permission to request; the permission request result maps to
  `MediaStorePermissionStatus` values the Dart side already defines.

**Rationale:** The interface doc in `media_store_bridge.dart` already spells
out this three-tier split; the Kotlin plugin must implement it faithfully.

### SAF persistence
- `Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION`
  on the `ACTION_OPEN_DOCUMENT_TREE` result. Call
  `contentResolver.takePersistableUriPermission(uri, FLAG_GRANT_READ_URI_PERMISSION)`
  immediately.
- Store `Uri.toString()` strings in the `SaffBridgePlugin` result map; Dart
  converts them to `SafFolder` value objects.
- Persisted URIs are returned by `listGrantedFolders` by querying
  `contentResolver.persistedUriPermissions`.

**Rationale:** `takePersistableUriPermission` is the only way to retain cross-
restart access without asking the user again (LOCAL-003). Storing the raw URI
string keeps the Dart/Kotlin interface serialization-free.

### Kotlin file names
- `MediaStorePlugin.kt` registers as a `MethodCallHandler` (not a Flutter
  plugin class) and is instantiated directly from `MainActivity`.
- `SaffBridgePlugin.kt` does the same. Both live in
  `android/app/src/main/kotlin/com/example/mytube/`.

**Rationale:** Registering from `MainActivity.configureFlutterEngine` avoids
needing a separate plugin registration entry and is the idiomatic approach for
app-level platform channels.

### Dart-side SaffBridge interface
- A new `SaffBridge` abstract interface (`lib/platform/saf_bridge.dart`) with:
  - `Future<SafFolder?> pickFolder()` — returns `null` if user cancels.
  - `Future<List<SafFolder>> listGrantedFolders()` — returns currently persisted
    grants.
  - `Future<void> releaseFolder(String uriString)` — releases the grant.
- `SafFolder` value class: `uriString`, `displayName` (nullable — SAF does not
  always return a human-readable name).

### Riverpod providers
- `platform_providers.dart` exposes `mediaStoreBridgeProvider` and
  `safBridgeProvider` as `Provider<T>`.
- Both return the real impl in the app; tests override them.

### Test approach
- Use `TestWidgetsFlutterBinding.ensureInitialized()` +
  `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler`
  to intercept channel calls without a device.
- Tests for `MediaStoreBridgeImpl` cover: successful query, permission denied
  response, platform exception → `UnexpectedError`, `checkPermission`, and
  `requestPermission` mapping each `MediaStorePermissionStatus` value.
- Tests for `SaffBridgeImpl` cover: `pickFolder` success, user cancel (null),
  `listGrantedFolders`, and `releaseFolder`.

### build.gradle.kts
- No `dependencies {}` block exists yet. Add one with the `androidx.core:core-ktx`
  dependency that the Kotlin plugin needs (`ContextCompat.checkSelfPermission`,
  `ActivityCompat.requestPermissions`). The existing
  `sourceCompatibility/targetCompatibility` already targets Java 17; no
  additional block merging is needed.

---

## Implementation order

- [ ] 1. Add Android permissions to `AndroidManifest.xml`.
      Add `READ_EXTERNAL_STORAGE` (maxSdk 32), `READ_MEDIA_VIDEO` (minSdk 33),
      and `READ_MEDIA_VISUAL_USER_SELECTED` (minSdk 34) inside `<manifest>`.
      No `<uses-feature>` required — all are runtime permissions.
      Files: `android/app/src/main/AndroidManifest.xml`
      Verify: `flutter build apk --debug` (or `flutter analyze`) — no manifest
      merge errors.

- [ ] 2. Add the `dependencies` block to `build.gradle.kts`.
      Insert after the `flutter {}` block:
      ```kotlin
      dependencies {
          implementation("androidx.core:core-ktx:1.16.0")
      }
      ```
      `core-ktx 1.16.0` is the latest stable release and supports API 24+.
      `ActivityCompat` and `ContextCompat` are used by `MediaStorePlugin.kt`
      for permission checks/requests; `ContentResolver` and `MediaStore` columns
      are in the Android SDK itself (no extra dep needed).
      Files: `android/app/build.gradle.kts`
      Verify: `flutter build apk --debug` — Gradle resolves `core-ktx` with no
      errors.

- [ ] 3. Implement `MediaStorePlugin.kt`.
      Create the Kotlin `MethodCallHandler` class.

      Channel name: `com.example.mytube/media_store`

      Handle these method names:
      - `"checkPermission"` → call `ContextCompat.checkSelfPermission` for the
        correct permission (`READ_MEDIA_VIDEO` on API 33+,
        `READ_EXTERNAL_STORAGE` on API 24–32) plus check `shouldShowRequestPermissionRationale`
        to distinguish `denied` from `permanentlyDenied`. Return a `String`
        matching the enum value name (`"granted"`, `"partiallyGranted"`,
        `"denied"`, `"permanentlyDenied"`).
      - `"requestPermission"` → call `ActivityCompat.requestPermissions` and
        return the result via a one-shot `ActivityResultListener`. Return the
        same status string.
      - `"queryVideos"` → query `MediaStore.Video.Media.EXTERNAL_CONTENT_URI`
        with these columns: `_ID`, `DISPLAY_NAME`, `DURATION`, `WIDTH`, `HEIGHT`,
        `MIME_TYPE`, `SIZE`, `DATE_ADDED`, `DATE_MODIFIED`. Return a
        `List<Map<String, Any?>>` where each map has keys matching the
        `MediaStoreVideo` field names exactly:
        `mediaStoreId`, `contentUri`, `displayName`, `durationMs`, `widthPx`,
        `heightPx`, `mimeType`, `sizeBytes`, `dateAddedSeconds`,
        `dateModifiedSeconds`.
        If permission is not granted, call `result.error("PERMISSION_DENIED",
        "Permission not granted", null)`.
        Wrap everything in try/catch; surface unexpected exceptions via
        `result.error("UNEXPECTED_ERROR", message, null)`.

      Important implementation notes:
      - Use `activity.contentResolver` (not `context.contentResolver`) so that
        the activity reference is valid; store it as a nullable `Activity?`
        property, obtained from `FlutterPlugin.FlutterPluginBinding` or
        `ActivityAware`.
      - On API 34+ also request `READ_MEDIA_VISUAL_USER_SELECTED` alongside
        `READ_MEDIA_VIDEO`; if the user selected partial access, map to
        `partiallyGranted`.
      - `contentUri` must be `ContentUris.withAppendedId(
          MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id).toString()`.

      Files: `android/app/src/main/kotlin/com/example/mytube/MediaStorePlugin.kt`
      Verify: `flutter build apk --debug` — compiles without Kotlin errors.

- [ ] 4. Implement `SaffBridgePlugin.kt`.
      Create the Kotlin `MethodCallHandler` class.

      Channel name: `com.example.mytube/saf`

      Handle these method names:
      - `"pickFolder"` → launch `Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)` with
        `FLAG_GRANT_READ_URI_PERMISSION or FLAG_GRANT_PERSISTABLE_URI_PERMISSION`.
        On result: call `contentResolver.takePersistableUriPermission(uri,
        FLAG_GRANT_READ_URI_PERMISSION)` then return a `Map<String, Any?>` with
        `uriString` and `displayName` (obtain display name from `DocumentFile
        .fromTreeUri(context, uri)?.name`). Return `null` if the user cancels
        (result code ≠ `RESULT_OK`).
      - `"listGrantedFolders"` → iterate
        `contentResolver.persistedUriPermissions`, filter for read-permission
        entries, and return `List<Map<String, Any?>>` with the same shape
        (`uriString`, `displayName` — which can be `null` if DocumentFile
        resolution fails).
      - `"releaseFolder"` → accept a `Map` argument with `"uriString"`, parse
        the `Uri`, call `contentResolver.releasePersistableUriPermission(uri,
        FLAG_GRANT_READ_URI_PERMISSION)`, and call `result.success(null)`.
      - All unexpected exceptions → `result.error("UNEXPECTED_ERROR", ...)`.

      Implementation notes:
      - Extend `ActivityAware` to hold `Activity?`; use it to `startActivityForResult`.
      - Register an `ActivityResultListener` to capture the document-tree result
        and forward it back to the pending `MethodChannel.Result`.
      - Never call `result.success/error` more than once per call (guard with a
        `replied` flag).

      Files: `android/app/src/main/kotlin/com/example/mytube/SaffBridgePlugin.kt`
      Verify: `flutter build apk --debug` — compiles without Kotlin errors.

- [ ] 5. Register both plugins in `MainActivity.kt`.
      Override `configureFlutterEngine` (not `onCreate`). In the body:
      1. `super.configureFlutterEngine(flutterEngine)`
      2. Instantiate `MediaStorePlugin` and call
         `flutterEngine.plugins.add(mediaStorePlugin)` or register the channel
         directly: `MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
         "com.example.mytube/media_store").setMethodCallHandler(mediaStorePlugin)`.
      3. Same for `SaffBridgePlugin`.

      Note: Because both plugins need `ActivityAware` lifecycle callbacks
      (for `requestPermission` and `startActivityForResult`), pass `this`
      (the `FlutterActivity`) to each plugin constructor so they can cast it
      to `Activity` directly — this avoids the full `FlutterPlugin`/
      `ActivityAware` registration complexity while still being safe for an
      app-embedded plugin.

      Files: `android/app/src/main/kotlin/com/example/mytube/MainActivity.kt`
      Verify: `flutter build apk --debug` — no compile errors; existing Flutter
      engine embedding is unaffected.

- [ ] 6. Implement `MediaStoreBridgeImpl` (Dart).
      Dart class that implements `MediaStoreBridge` from
      `lib/platform/media_store_bridge.dart`.

      Channel: `const MethodChannel('com.example.mytube/media_store')`

      `checkPermission()`:
      - Invoke `"checkPermission"`, map the returned `String` to
        `MediaStorePermissionStatus` via a switch expression. Unknown strings →
        `MediaStorePermissionStatus.denied` as a safe default.

      `requestPermission()`:
      - Invoke `"requestPermission"`, map the same way.

      `queryVideos()`:
      - Invoke `"queryVideos"`.
      - On success: cast result to `List<Object?>`, map each entry to a
        `MediaStoreVideo`. Field names match those specified in step 3.
        All nullable fields use `as int?` / `as String?` casts; non-nullable
        `mediaStoreId` and `contentUri` and `displayName` use `as String` (throw
        `StateError` if unexpectedly null — that indicates a Kotlin bug).
      - On `PlatformException` with code `"PERMISSION_DENIED"`: return
        `Result.err(PermissionDeniedError(diagnosticMessage: e.message ?? 'permission denied'))`.
      - On `PlatformException` with any other code, or on any other exception:
        return `Result.err(UnexpectedError(diagnosticMessage: ..., cause: e))`.

      Use `AppError` subtypes **exactly as documented**: `PermissionDeniedError`
      for permission denial, `UnexpectedError` for platform exceptions. Do NOT
      use `AppError` directly (it is sealed) or any other subtype.

      Files: `lib/platform/media_store_bridge_impl.dart`
      Verify: `flutter analyze` — no errors; `flutter test test/unit/platform/`
      — new tests pass (step 8 must be done first, or run them together).

- [ ] 7. Implement `SaffBridge` interface and `SaffBridgeImpl` (Dart).
      Two files:

      **`lib/platform/saf_bridge.dart`** — interface + value class:
      ```dart
      abstract interface class SaffBridge {
        Future<SafFolder?> pickFolder();
        Future<List<SafFolder>> listGrantedFolders();
        Future<void> releaseFolder(String uriString);
      }

      class SafFolder {
        const SafFolder({required this.uriString, this.displayName});
        final String uriString;
        final String? displayName;
      }
      ```

      **`lib/platform/saf_bridge_impl.dart`** — concrete implementation:
      Channel: `const MethodChannel('com.example.mytube/saf')`

      `pickFolder()`:
      - Invoke `"pickFolder"`.
      - If result is `null`, return `null` (user cancelled).
      - Otherwise cast to `Map<Object?, Object?>`, extract `uriString` and
        `displayName`, return `SafFolder(...)`.
      - On `PlatformException` → `UnexpectedError`. But since `pickFolder`
        returns `SafFolder?` not `Result`, rethrow as a typed exception wrapper
        or convert to a domain exception. Decision: rethrow as
        `PlatformException` unchanged — the caller (source adapter, not a
        widget) handles it. This is acceptable because `pickFolder` is a
        user-interactive call where the only realistic failure is a device-level
        crash, not a recoverable domain error.

        **Important gotcha:** `releaseFolder` and `listGrantedFolders` similarly
        do not return `Result` — they are non-fallible housekeeping calls. Wrap
        `PlatformException` in an `UnexpectedError` and rethrow as a Dart
        `Exception` so callers are not silently swallowing failures. Document
        this in the method signature's doc comment.

      Files: `lib/platform/saf_bridge.dart`, `lib/platform/saf_bridge_impl.dart`
      Verify: `flutter analyze` — no errors.

- [ ] 8. Add Riverpod providers for both bridges.
      Create `lib/platform/platform_providers.dart`:
      ```dart
      final mediaStoreBridgeProvider = Provider<MediaStoreBridge>(
        (ref) => MediaStoreBridgeImpl(),
      );

      final safBridgeProvider = Provider<SaffBridge>(
        (ref) => SaffBridgeImpl(),
      );
      ```
      These are `Provider<T>` (same pattern as `videoRepositoryProvider`). Tests
      override with mock implementations via `ProviderContainer(overrides: [...])`.

      Files: `lib/platform/platform_providers.dart`
      Verify: `flutter analyze` — no errors.

- [ ] 9. Write unit tests for `MediaStoreBridgeImpl`.
      File: `test/unit/platform/media_store_bridge_impl_test.dart`

      Setup pattern (from existing test conventions — no `setUpAll`, use `setUp`
      per test or shared group `setUp`):
      ```dart
      TestWidgetsFlutterBinding.ensureInitialized();
      // then in setUp:
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.example.mytube/media_store'),
            (call) async { ... },
          );
      // tearDown: set handler back to null
      ```

      Test cases (cover all paths):
      1. `checkPermission` → `"granted"` string → `MediaStorePermissionStatus.granted`
      2. `checkPermission` → `"partiallyGranted"` → `partiallyGranted`
      3. `checkPermission` → `"denied"` → `denied`
      4. `checkPermission` → `"permanentlyDenied"` → `permanentlyDenied`
      5. `requestPermission` → `"granted"` → `granted`
      6. `queryVideos` success → returns `Ok` containing `List<MediaStoreVideo>`
         with all fields correctly parsed (include at least one non-null
         optional field and one null optional field).
      7. `queryVideos` → platform error code `"PERMISSION_DENIED"` → returns
         `Err(PermissionDeniedError(...))` — verify `isErr` and type.
      8. `queryVideos` → platform error code `"UNEXPECTED_ERROR"` → returns
         `Err(UnexpectedError(...))`.
      9. `queryVideos` with empty list → returns `Ok([])`.

      Files: `test/unit/platform/media_store_bridge_impl_test.dart`
      Verify: `flutter test test/unit/platform/media_store_bridge_impl_test.dart`
      — all 9 tests pass.

- [ ] 10. Write unit tests for `SaffBridgeImpl`.
       File: `test/unit/platform/saf_bridge_impl_test.dart`

       Same `setMockMethodCallHandler` setup pattern, channel
       `"com.example.mytube/saf"`.

       Test cases:
       1. `pickFolder` success → returns `SafFolder` with correct `uriString`
          and `displayName`.
       2. `pickFolder` cancelled → Kotlin returns `null` → Dart returns `null`.
       3. `listGrantedFolders` → returns `List<SafFolder>` of correct length and
          values.
       4. `listGrantedFolders` → empty list → returns `[]`.
       5. `releaseFolder` → invoked with `"uriString"` argument, completes
          without error.

       Files: `test/unit/platform/saf_bridge_impl_test.dart`
       Verify: `flutter test test/unit/platform/saf_bridge_impl_test.dart`
       — all 5 tests pass.

- [ ] 11. Run the full test suite, formatter, and analyzer.
       Commands to run in order:
       ```
       dart format --output=none --set-exit-if-changed lib/ test/
       flutter analyze
       flutter test
       flutter build apk --debug
       ```
       All must pass clean (no formatting diffs, no analyzer issues, all tests
       green, APK builds).
       Files: none created — this is a verification-only step.
       Verify: all four commands exit 0.

- [ ] 12. Update `TASKS.md`.
       Mark P3-01 and P3-02 as `In progress` after code is written and tests
       pass, or `Done` once the Definition of Done below is satisfied. Do NOT
       mark complete merely because code was written.

       Definition of Done for P3-01/P3-02:
       - `flutter analyze` clean.
       - `dart format` no diffs.
       - `flutter test` passes (all existing + new tests).
       - `flutter build apk --debug` succeeds.
       - All test cases from steps 9 and 10 pass.
       - No secrets, tokens, or hard-coded credentials in any file.
       - `TASKS.md` updated to reflect actual state.

       Files: `TASKS.md`
       Verify: visible diff in TASKS.md matches actual completed work.

---

## Gotchas and traps

1. **`AppError` is a sealed class, not an enum.** Use `PermissionDeniedError`
   and `UnexpectedError` as concrete instantiations. Do not switch on it like
   an enum.

2. **`Result` uses `Ok`/`Err` with `Result.ok(v)` / `Result.err(e)` factory
   constructors.** Check with `isOk`/`isErr` or pattern-match; do not call
   `.value` without checking first.

3. **`build.gradle.kts` has no `dependencies {}` block.** Add it explicitly;
   do not merge into the `android {}` block by mistake.

4. **`MainActivity.kt` is a single-line class.** Overriding
   `configureFlutterEngine` requires a real body; the override must call
   `super.configureFlutterEngine(flutterEngine)` first.

5. **Method channel handler must be set on the platform thread.** In tests,
   `TestWidgetsFlutterBinding.ensureInitialized()` handles this. In Kotlin,
   `MethodChannel` is already set up on the main thread in
   `configureFlutterEngine`.

6. **`queryVideos` result type.** The Kotlin side returns
   `List<Map<String, Any?>>`. Flutter's MethodChannel codec decodes this as
   `List<Object?>` containing `Map<Object?, Object?>`. The Dart impl must cast
   accordingly — do NOT assume `Map<String, dynamic>`.

7. **SAF `displayName` may be null.** `DocumentFile.fromTreeUri` can return
   `null` for some URI types; always handle it safely.

8. **Permission request requires an Activity.** `ContextCompat.checkSelfPermission`
   only needs a `Context`, but `ActivityCompat.requestPermissions` needs an
   `Activity`. The plugin must hold a reference to the activity obtained via the
   Flutter embedding lifecycle, not just the application context.

9. **`takePersistableUriPermission` must be called on the result URI before the
   activity result is acknowledged.** Call it synchronously inside the activity
   result callback, before calling `result.success(...)`.

10. **`releaseFolder` is idempotent on Android** — calling it on a URI that was
    never persisted (or already released) throws `SecurityException`. Wrap in
    try/catch and treat as success (the grant is simply not present).

11. **`READ_MEDIA_VISUAL_USER_SELECTED` is only available on API 34+.** Do not
    declare it without `android:minSdkVersion="34"` in a `<uses-permission>` tag
    — instead use `android:minSdkVersion` attribute on the permission element:
    `<uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED"
    android:minSdkVersion="34"/>`.

12. **Never modify the `app_database.g.dart` generated file manually.** It is
    excluded from the analyzer but must remain consistent with the Drift schema.
    No Drift changes are needed for P3-01/P3-02.

---

## File summary

| Action   | Path |
|----------|------|
| Modify   | `android/app/src/main/AndroidManifest.xml` |
| Modify   | `android/app/build.gradle.kts` |
| Create   | `android/app/src/main/kotlin/com/example/mytube/MediaStorePlugin.kt` |
| Create   | `android/app/src/main/kotlin/com/example/mytube/SaffBridgePlugin.kt` |
| Modify   | `android/app/src/main/kotlin/com/example/mytube/MainActivity.kt` |
| Create   | `lib/platform/media_store_bridge_impl.dart` |
| Create   | `lib/platform/saf_bridge.dart` |
| Create   | `lib/platform/saf_bridge_impl.dart` |
| Create   | `lib/platform/platform_providers.dart` |
| Create   | `test/unit/platform/media_store_bridge_impl_test.dart` |
| Create   | `test/unit/platform/saf_bridge_impl_test.dart` |
| Modify   | `TASKS.md` |
