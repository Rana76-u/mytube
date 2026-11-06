# DL2 — Extractor Bridge Device Testing Checklist

The DL2 extractor bridge (Dart seam + `ExtractorPlugin.kt` over
youtubedl-android) is covered on the host by:

- `flutter analyze` → **No issues found** (whole tree).
- **1670** Dart tests, 0 failures (`flutter test --concurrency=1`). The 35 new
  DL2 tests are the seam value types (`media_extractor_seam_test.dart`, 15),
  the channel contract over a fake `MethodChannel`
  (`media_extractor_impl_test.dart`, 16), and the error-code map
  (`extractor_error_map_test.dart`, 4).
- A JVM unit test for the argument-safety builder
  (`android/app/src/test/.../ExtractorArgsBuilderTest.kt`) — **green** via
  `./gradlew :app:testDebugUnitTest`. It rejects a URL beginning with `-`,
  rejects non-http(s) schemes, and asserts no forbidden flag
  (`--exec*`/`--config*`/`--netrc*`/`--plugin-dirs`/caller `--cookies`) ever
  reaches the argv and that the URL is the sole trailing token after `--`.
- `flutter build apk --debug` → **succeeds**. `ExtractorPlugin.kt` compiles and
  links against the real engine API (`com.yausername.youtubedl_android`,
  `com.yausername.ffmpeg`, `com.yausername.aria2c`), so the native wiring is
  type-checked even though it is not *run* here.

## What a device must prove

Everything below launches the bundled Python/yt-dlp subprocess and touches the
network. None of it can run under the JVM test harness or `flutter test`:

- **Engine init / `preparing` → `ready`.** First `status` call should show
  `preparing` briefly, then `ready` with a version string. The lazy init runs
  off the main thread; the UI must stay responsive during it.
- **`probe`.** `--dump-single-json --no-playlist --skip-download` returns real
  metadata (title, duration, formats). Confirm the Dart decode classifies a
  video, a live stream and a playlist correctly (`WebMediaKind`).
- **`resolveStream`.** `--get-url` yields a streamable URL plus (where present)
  the request headers; HLS vs progressive and the height cap must be honoured.
  Confirm the resolved URL is *never* persisted as the durable identity.
- **Byte progress parsing.** `progressPayload` reads the
  `[download] 42.3% of 12.34MiB at 1.23MiB/s ETA 00:08` line. Verify the
  throttled events (~2/sec) drive the download UI sensibly and that unparseable
  lines degrade to nulls rather than a crash.
- **`cancel`.** `destroyProcessById` must stop a running job and emit a
  `cancelled`/`failed` terminal event; partial/staging files for that job are
  cleaned up (full staging rules land in DL3).
- **Updates.** `update` runs `updateYoutubeDL(STABLE)`; a failed update keeps
  the previous working version (ADR-028). Network-offline should map to
  `NETWORK`.
- **Error mapping in the field.** Each §15.10 code must actually fire for a real
  failure (DRM, login-required, geo-block, private/removed, 429). The keyword
  table in `mapErrorCode` is a best-effort reduction of yt-dlp's text and is the
  main thing to watch for mis-classification.

## Target device

**CPH2719 — Android 16 (API 36)** (arm64-v8a). Use a physical device: the engine
is a native subprocess and the extractors need real network + real site HTML.

```text
flutter devices
flutter run -d CPH2719
```

## Deferred to later phases (not DL2 scope)

- **Cookies / accounts** (`--cookies`) — the app-generated per-job cookie path is
  wired through the builder but is only populated from DL10.2; DL2 device passes
  run without cookies.
- **Recovery ladder** (retry, alternate clients, proxy, relaxed format) lives in
  the DL4.3 runner, not the bridge.
- **Real reach across sites** (Facebook / Instagram / direct MP4) remains
  inconclusive per the DL0.2 correction; the YouTube mechanism is proven, the
  remedial real-URL + cookie pass is scheduled for DL9/DL10.

## APK sizes (debug, recorded in DECISIONS.md ADR-022)

Universal and per-ABI debug APKs from `flutter build apk --debug`:
universal 297.9 MB; arm64-v8a 114.2 MB; armeabi-v7a 101.7 MB; x86 93.1 MB;
x86_64 113.1 MB. `useLegacyPackaging` (uncompressed `.zip.so`) is why these are
large; the per-ABI split is the intended install artifact.

---

# DL3 — Destination Publishing Device Testing Checklist

The DL3 publishing layer is covered on the host by:

- `flutter analyze` → **No issues found** (whole tree).
- **1693** Dart tests, 0 failures (`flutter test --concurrency=1`). The 23 new
  DL3 tests are `AppStoragePublisher` over a real temp directory
  (`destination_publisher_appstorage_test.dart`, 9), the `DownloadPublisher`
  dispatcher routing / fallback / staging rules over a fake bridge
  (`download_publisher_test.dart`, 8), and the fail-soft `PublishBridgeImpl`
  channel contract (`publish_bridge_impl_test.dart`, 6).
- `flutter build apk --debug` → **succeeds**. `PublishPlugin.kt` compiles and
  links against MediaStore, `DocumentFile` and `StatFs`, so the native half is
  type-checked even though it is not *run* here.

The pure-Dart `AppStoragePublisher` (atomic rename, collision resolution,
free-space gate, staging-only cleanup) is genuinely exercised on the host by the
temp-dir tests; the items below are the framework paths no JVM/widget harness
can reach.

## What a device must prove

- **MediaStore publish (API 29+, scoped storage).** `publishToDeviceFolder`
  inserts into `Movies/MyTube` (video) / `Music/MyTube` (audio) with
  `IS_PENDING` held during the copy then flipped to 0; the file must appear in
  the gallery/files app afterwards and the returned content URI must be
  playable. Confirm a duplicate display name is auto-uniquified and the
  existing file is never overwritten.
- **A failed copy leaves no orphan.** Interrupt mid-copy (low storage, revoked
  consent) and confirm the half-written `IS_PENDING` row is deleted and the
  staged file is kept for retry.
- **Pre-Q (API 24–28) write permission.** On a 24–28 device without
  `WRITE_EXTERNAL_STORAGE`, `publishToDeviceFolder` must return
  `PERMISSION_DENIED` and the dispatcher must land the file in app storage
  (result carries a `filePath`, UI should say "saved in the app"). The
  just-in-time *prompt* for that permission is a DL4/DL5 pipeline action, not a
  DL3 one; DL3 only proves the denial→fallback path.
- **SAF picked folder.** `publishToPickedFolder` into a user-picked tree must
  create the document and copy. A revoked or read-only grant must return
  `DESTINATION_UNAVAILABLE` and keep staging — never delete the staged file.
- **Staging safety.** After any successful publish, staging under
  `<downloadsRoot>/staging/<jobId>/` is removed; a file whose path is outside
  the staging tree is never touched (guarded `_discardStaging`).
- **OneDrive.** Selecting the OneDrive destination must show it disabled with
  "Connect OneDrive first"; the placeholder returns `DESTINATION_UNAVAILABLE`
  and keeps staging (real upload is DLOD-1, Phase 9).

## Target device

Same **CPH2719 — Android 16 (API 36)**. The scoped-storage MediaStore path is the
primary target; the API 24–28 fallback ideally needs a legacy device or
emulator to exercise `WRITE_EXTERNAL_STORAGE`.
