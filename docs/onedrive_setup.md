# OneDrive setup

OneDrive uses Microsoft identity platform's native authorization-code flow
through AppAuth. It is a public mobile client: do not create or ship a client
secret.

## Microsoft Entra app registration

1. Register an app that supports **organizational directory and personal
   Microsoft accounts**.
2. Under **Authentication**, add an **Android** platform using the app package
   name `com.example.mytube`. Use the callback URI generated for each signing
   certificate, in Microsoft's `msauth://<package>/<signature-hash>` format.
   The package's Android manifest registers the `msauth` scheme for AppAuth.
3. Add the delegated Microsoft Graph permission `Files.Read`. The app requests
   only `Files.Read` and `offline_access`; it does not request write access.
4. Record the application (client) ID. Do not copy a client secret into the
   Flutter project.

The debug and release signing certificates have different signature hashes.
Register the hash matching the build being tested. Follow Microsoft's current
[Android redirect URI instructions](https://learn.microsoft.com/en-us/entra/identity-platform/scenario-mobile-app-registration)
to calculate the hash; never commit signing keys or private credentials.

## Build configuration

Provide the client ID, exact redirect URI registered above, and tenant through
Dart defines when launching or building:

```powershell
flutter run `
  --dart-define=MICROSOFT_CLIENT_ID=<application-client-id> `
  --dart-define=MICROSOFT_REDIRECT_URI=msauth://com.example.mytube/<signature-hash> `
  --dart-define=MICROSOFT_TENANT=common
```

`common` accepts personal Microsoft accounts and organizational accounts.
Set `MICROSOFT_TENANT` to a specific tenant ID/domain to restrict sign-in.
These values are public app configuration, not credentials. The redirect URI
must use the `msauth` scheme and match the registered Android callback.

## Privacy and verification

- Tokens are stored only by `flutter_secure_storage`; disconnect clears this
  app's token record and leaves OneDrive files and local library metadata
  untouched.
- Android app backup is disabled so OAuth credentials are not copied to cloud
  backup or device transfer.
- Graph requests use delegated read access. Playback asks Graph for a fresh
  `@microsoft.graph.downloadUrl` and keeps that short-lived URL only in memory.
- Run `flutter test test/unit/sources/onedrive_adapter_test.dart
  test/unit/platform/onedrive_auth_service_test.dart
  test/unit/sources/onedrive_graph_api_test.dart` and
  `flutter analyze lib test`.
- Complete a real sign-in, nested-folder listing/search, playback, revoked
  consent, rate-limit, and log review on a dedicated Microsoft account and a
  device before treating Phase 9 as fully verified.
