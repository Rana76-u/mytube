---
kind: logging_system
name: Privacy-Safe Diagnostic Logging via PrivacySafeLogger and DiagnosticRedactor
category: logging_system
scope:
    - '**'
source_files:
    - lib/core/logging/privacy_safe_logger.dart
    - lib/core/logging/diagnostic_redactor.dart
    - lib/main.dart
    - lib/app/app_error_handler.dart
    - test/unit/privacy_safe_logger_test.dart
    - test/unit/diagnostic_redactor_test.dart
---

## What system/approach is used

MyTube does not use a third-party logging framework (e.g. `logger`, `logging`, `log4dart`). Instead it ships a small, in-repo diagnostic subsystem built on top of Dart's `dart:developer` API:

- **Sink**: `dart:developer.log(message, name: 'mytube')` — the default sink writes to the Dart developer service (visible in Flutter DevTools / Observatory).
- **Abstraction**: `PrivacySafeLogger` exposes a single `logError(Object error, [StackTrace? stackTrace])` method plus a `redact(...)` helper.
- **Redaction**: `DiagnosticRedactor` strips credentials and signed URLs from any diagnostic text before it reaches a sink.
- **Injection point**: `main.dart` constructs one `PrivacySafeLogger` instance and injects it into `AppErrorHandler`, which installs uncaught-error hooks (`onPlatformError`) so all app-wide errors flow through the redactor.

The design is intentionally minimal: there are no log levels, no structured-field model, no file/network sinks, and no configuration flags. The only "level" is error diagnostics.

## Key files and packages

- `lib/core/logging/privacy_safe_logger.dart` — logger abstraction + default `dart:developer` sink.
- `lib/core/logging/diagnostic_redactor.dart` — regex-based credential/URL scrubbing.
- `lib/main.dart` — bootstraps the logger and wires it into `AppErrorHandler`.
- `lib/app/app_error_handler.dart` — consumes the logger for platform/uncaught errors.
- `test/unit/privacy_safe_logger_test.dart` — verifies redaction behavior.
- `test/unit/diagnostic_redactor_test.dart` — verifies URL/token stripping rules.

## Architecture and conventions

1. **Single logger instance.** `bootstrapAndRun()` creates exactly one `PrivacySafeLogger` (line 20) and passes it to `AppErrorHandler`. Tests override it by supplying a custom `sink` that captures output into a list.

2. **Errors-only path.** The public API is `logError`; there is no `debug/info/warn/fatal`. Callers pass an `Object` (typically an exception) and an optional `StackTrace`.

3. **Redaction is mandatory before sinking.** The class comment states: "Never send raw exceptions to a sink; always redact first." `logError` delegates to `redact`, which chains `DiagnosticRedactor.redactObject` and `DiagnosticRedactor.redact(StackTrace.toString())`.

4. **Redaction rules** (from `diagnostic_redactor.dart`):
   - Any `https?://...` URL has its query string replaced with `?[redacted]`, fragment with `#[redacted]`, and `userInfo` (user:password@host) is dropped entirely — leaving only scheme/host/port/path.
   - Bearer tokens matching `Bearer \S+` become `Bearer [redacted]`.
   - Assignments of the form `token|access_token|refresh_token|id_token|password|secret|api[_-]?key|authorization` followed by `:` or `=` have their value replaced with `[redacted]`.

5. **Testability via `LogSink` typedef.** `PrivacySafeLogger` accepts an optional `LogSink = void Function(String message)` constructor parameter; when omitted it falls back to `_defaultSink`, which calls `developer.log(name: 'mytube')`. Tests construct `PrivacySafeLogger(sink: lines.add)` to assert emitted strings without touching the developer service.

6. **Named logs.** All messages are emitted under the constant `logName = 'mytube'`, enabling filtering in DevTools.

## Conventions and constraints

- **Observed convention**: All application-wide error reporting goes through `PrivacySafeLogger.logError` (used by `AppErrorHandler`); direct calls to `print`, `debugPrint`, or `developer.log` are not present in the production code paths examined.
- **Constraint enforced by code**: Raw exceptions are never passed directly to a sink — `logError` always runs them through `DiagnosticRedactor` first. This is documented in the class docstring and enforced by the implementation.
- **Constraint enforced by tests**: `privacy_safe_logger_test.dart` and `diagnostic_redactor_test.dart` verify that URLs, bearer tokens, and key=value secrets are redacted before reaching the sink.
- **No log-level strategy exists**: There are no level enums, no conditional compilation flags for verbose/debug builds, and no per-module loggers. The subsystem is deliberately scoped to error diagnostics only.
- **No structured fields**: Log output is plain text produced by `StringBuffer` concatenation of the redacted object and stack trace; there is no JSON/map payload shape.