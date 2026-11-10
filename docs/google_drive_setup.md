# Google Drive setup

Google Drive uses Google's native Android sign-in through `google_sign_in`.
It is a public mobile client: do not create or ship a client secret. No Google
callback scheme or `google-services.json` is needed for this integration.

## 1. Create the Google Cloud project

1. Create or choose a project in the
   [Google Cloud Console](https://console.cloud.google.com/).
2. Enable **Google Drive API** under **APIs & Services → Library**.
3. Configure the OAuth consent screen / Google Auth Platform:
   - Choose **External** for personal Google accounts (or **Internal** only
     when every account belongs to the same Google Workspace organization).
   - Add the Google account used for testing as a test user while the app is
     in **Testing**.
   - Add the scope `https://www.googleapis.com/auth/drive` under
     **Data Access**. The app uses it to list and stream videos, rename Drive
     files, and permanently delete originals after the app's explicit
     confirmation.

This scope grants the app access to all files in the connected Drive account,
not only videos. Review the consent screen carefully and connect only the
intended personal account. Google's OAuth verification and testing-mode rules
still apply; personal use does not change Google's scope policy. A project
left in Testing may also receive short-lived refresh authorizations; be
prepared to reconnect when Google requires it.

## 2. Create OAuth clients

Create both of these OAuth client IDs in **Google Auth Platform → Clients**:

1. **Android** client:
   - Package name: `com.example.mytube`
   - SHA-1 certificate fingerprint: use the fingerprint for the build being
     tested. In PowerShell, from the repository root:

     ```powershell
     Set-Location android
     .\gradlew signingReport
     ```

     Register the `SHA1` shown for `debug` for local debug builds. Register
     the release signing certificate separately before testing a release
     build; fingerprints differ when signing keys differ.
2. **Web application** client:
   - Create a client ID; no authorized redirect URI is needed for this
     Android-only use.
   - The app passes this public client ID to Google's native sign-in SDK as
     `serverClientId`. The Google Sign-In Android plugin requires it when
     `google-services.json` is not used.

Record the **web application client ID** (it ends in
`.apps.googleusercontent.com`). It is a public client identifier, not a
secret. Do not put a client secret, refresh token, or service-account key in
Flutter or Android source.

## 3. Configure and run the app

Open `lib/platform/google_drive/google_drive_auth_service.dart` and set
`googleDriveWebClientId` to the web application client ID. This is a
project-local default, so normal runs do not need an extra argument:

```powershell
flutter run
```

Build-time override remains available for CI or a separate build:

```powershell
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=<web-application-client-id>
```

Rebuild after changing the ID. The Android package name and signing
certificate must match the Android OAuth client.

This client uses Credential Manager / Google Sign-In rather than an
AppAuth redirect. The `msauth` redirect in the Android manifest is only for
OneDrive; do not change it for Google Drive.

## 4. Token and data handling

- The native Google Sign-In SDK owns account state and scoped authorization.
  The app keeps access tokens in memory only, asks the SDK for a new token
  when needed, and does not persist Google refresh tokens or account
  credentials in the library database or preferences.
- Drive API requests send the access token only in the HTTPS authorization
  header to `www.googleapis.com`. Playback uses the Drive API media endpoint
  and an in-memory header; no temporary download link becomes a durable
  source identity.
- Previously connected accounts must grant the new full Drive scope. If an
  operation reports missing permission, disconnect/reconnect Google Drive and
  accept the updated consent request.
- Disconnect revokes this app's Google authorization through the SDK. It
  leaves Drive files and local library entries untouched.
- Rename is available from **Manage sources → Rename in Google Drive**.
  **Delete** permanently deletes each named original in the library item's
  source list; it is available only through the per-item delete action and
  confirmation. Cancel leaves every file untouched. A mixed-source item's
  confirmation names every original that will be deleted.
- Thumbnails use Google's temporary metadata link only for the immediate
  fetch. The app validates its host, bounds redirects and response size, does
  not forward the OAuth token to the image host, and caches image bytes under
  a key derived from the stable Drive file ID.
- The app checks Drive's `canDownload` capability before offering an
  app-managed download. It does not bypass permission or download
  restrictions.

## 5. Verify the setup

Run the automated Google Drive checks:

```powershell
flutter test `
  test/unit/platform/google_drive_auth_service_test.dart `
  test/unit/sources/google_drive_api_test.dart `
  test/unit/sources/google_drive_adapter_test.dart `
  test/unit/sources/google_drive_original_deleter_test.dart `
  test/unit/domain/thumbnail_service_test.dart `
  test/widget/google_drive_settings_section_test.dart `
  test/widget/manage_sources_sheet_test.dart `
  test/widget/video_item_delete_test.dart
```

Then on an Android device, connect the test account, grant the full Drive
scope, list/search/play videos (including a Shared Drive item if available),
rename a file, and confirm a test file deletion. Revoke the app grant in the
Google Account security page and verify reconnect/error handling. Inspect
device logs for OAuth-token or response-body leakage. Repeat a sign-in with
each signing certificate that will be used. App registration, real-account
checks, and device log review are owner/device prerequisites; automated tests
do not complete them.

## Troubleshooting

- A canceled account picker can also indicate a Google client configuration
  error. Confirm the application ID, SHA-1 fingerprint, web client ID,
  enabled Drive API, and test-user list.
- If debug works but release does not, register the release signing
  certificate's SHA-1 on the Android OAuth client.
- `403` indicates that Drive denied the requested operation. Disconnect and
  reconnect to accept the full Drive scope, and check that the signed-in
  account has permission to delete that file. A debug build does not itself
  prevent deletion; its SHA-1 matters only for OAuth client configuration.
- `404` means the file is no longer available to the connected account.
- `429` is a provider rate limit; wait before retrying.

References: [Google Sign-In Android setup](https://pub.dev/packages/google_sign_in_android),
[Drive API authorization scopes](https://developers.google.com/drive/api/guides/api-specific-auth),
[Android Credential Manager and Google sign-in](https://developer.android.com/identity/sign-in/credential-manager-siwg).
