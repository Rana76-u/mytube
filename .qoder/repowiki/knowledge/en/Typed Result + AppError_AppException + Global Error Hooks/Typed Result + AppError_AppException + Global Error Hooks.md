---
kind: error_handling
name: Typed Result + AppError/AppException + Global Error Hooks
category: error_handling
scope:
    - '**'
source_files:
    - lib/domain/models/app_error.dart
    - lib/core/result.dart
    - lib/core/errors/app_exception.dart
    - lib/app/app_error_handler.dart
    - lib/app/uncaught_app_error.dart
    - lib/app/app_error_surface.dart
    - lib/app/personal_video_hub_app.dart
---

## Overview

MyTube uses a two-tier error model:

1. **Expected, domain-level failures** are represented as typed sealed classes (`AppError` variants) wrapped in a `Result<T>` discriminated union returned from repository/source methods.
2. **Unexpected/uncaught failures** are represented by `AppException`, logged via `PrivacySafeLogger`, and surfaced to the user through global Flutter error hooks and an app-shell banner.

This is documented in `lib/core/result.dart` (ARCHITECTURE §3 — Data layer: "Use typed results/errors") and `lib/domain/models/app_error.dart` (ARCHITECTURE §12, NFR-004).

## Key Types and Files

| File | Role |
|---|---|
| `lib/domain/models/app_error.dart` | Sealed `AppError` base with named variants (`PermissionDeniedError`, `AuthenticationRequiredError`, `NetworkUnavailableError`, `NotFoundError`, `UnsupportedFormatError`, `ExpiredSourceError`, `RateLimitError`, `UnexpectedError`, `RefreshThrottledError`). Each variant carries `userMessage` (UI-safe) and `diagnosticMessage` (logged after redaction). |
| `lib/core/result.dart` | `sealed class Result<T>` with `Ok<T>` / `Err<AppError>` branches, plus `valueOrThrow` (throws `StateError`) and `map`. Repository methods return `Result<T>` instead of throwing. |
| `lib/core/errors/app_exception.dart` | `AppException` for unexpected failures; also carries `userMessage` + `diagnosticMessage` + optional `cause`. |
| `lib/app/app_error_handler.dart` | `AppErrorHandler` installs `FlutterError.onError`, `PlatformDispatcher.instance.onError`, and `ErrorWidget.builder`; returns previous hooks so tests can restore them. Platform errors return `true` to keep the isolate alive (comment cites PLAY-013 / NFR-006). |
| `lib/app/uncaught_app_error.dart` | Riverpod `NotifierProvider` (`uncaughtAppErrorProvider`) holding an `UncaughtAppError?`. `report(Object)` extracts `userMessage` from `AppException` or falls back to a static message. |
| `lib/app/app_error_surface.dart` | `AppErrorSurface` (fallback for `ErrorWidget.builder`) and `AppErrorBanner` (dismissable banner at the app shell). |
| `lib/app/personal_video_hub_app.dart` | Root widget that watches `uncaughtAppErrorProvider` and renders `AppErrorBanner` above the app body. |

## Architecture and Conventions

### Expected errors: `Result<T>` + `AppError`

- Repository methods and source adapters return `Result<T>` rather than throwing (documented in `lib/core/result.dart`).
- Callers pattern-match on `Ok` / `Err` using Dart's `switch` expressions (see the doc comment example in `result.dart`).
- `Result.valueOrThrow` is available but marked "prefer pattern-matching over this in production code"; it throws `StateError(error.diagnosticMessage)` on failure.
- Every `AppError` variant has a default `userMessage` suitable for UI display and requires a `diagnosticMessage` for logs.

### Unexpected errors: `AppException` + global hooks

- `AppErrorHandler.install()` replaces three global Flutter error entry points:
  - `FlutterError.onError` → logs via `PrivacySafeLogger.logError`.
  - `PlatformDispatcher.instance.onError` → logs, invokes optional `_onPlatformError` callback, and returns `true` to prevent isolate termination.
  - `ErrorWidget.builder` → renders `AppErrorSurface` with safe defaults.
- The install function returns a `VoidCallback` that restores the previous handlers, used by tests.
- Uncaught async/platform errors are funneled into the Riverpod state via `UncaughtAppErrorNotifier.report()`, which reads `error.userMessage` when the error is an `AppException`, otherwise uses `fallbackUserMessage`.
- The root widget renders `AppErrorBanner` with a dismiss action that calls `uncaughtAppErrorProvider.notifier.dismiss()`.

### Privacy separation

Both `AppError` and `AppException` carry two messages:
- `userMessage` — shown in UI; must not contain tokens or signed URL query parameters (stated in both type docs).
- `diagnosticMessage` — logged after redaction; may include internal detail.

The `PrivacySafeLogger` (referenced by `AppErrorHandler`) performs the redaction step before logging.

## Conventions Observed

- Domain-layer functions do not throw; they wrap failures in `Err(AppError)` and callers switch on the result.
- Only infrastructure/UI layers catch or surface exceptions; business logic propagates `AppError` values.
- All user-facing error text goes through `AppError.userMessage` / `AppException.userMessage`; raw exception objects are never displayed directly.
- Global error hooks are installed once at app startup via `AppErrorHandler` and restored in tests.
- `AppError` variants are kept small and named per failure mode, enabling callers to branch on specific cases (e.g., `RefreshThrottledError` is treated as a signal to skip refresh rather than show an error).

## Rules Enforced by Code/Docs

- Repository methods and source adapters return `Result<T>` instead of throwing (enforced by the `Result` API and documented in `lib/core/result.dart`).
- `AppError` and `AppException` fields `userMessage` must not contain credentials or signed-URL params (stated in their doc comments).
- Platform error handlers return `true` to keep the isolate alive (PLAY-013 / NFR-006), enforced by the implementation of `AppErrorHandler.handlePlatformError`.
- Tests can restore previous global error hooks via the `VoidCallback` returned by `AppErrorHandler.install()`.