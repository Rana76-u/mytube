# Testing Strategy

<cite>
**Referenced Files in This Document**   
- [pubspec.yaml](file://pubspec.yaml)
- [README.md](file://README.md)
- [device_testing_p3.md](file://docs/device_testing_p3.md)
- [app_database_test.dart](file://test/unit/database/app_database_test.dart)
- [drift_video_repository_test.dart](file://test/unit/database/drift_video_repository_test.dart)
- [availability_check_service_test.dart](file://test/unit/domain/availability_check_service_test.dart)
- [media_store_bridge_impl_test.dart](file://test/unit/platform/media_store_bridge_impl_test.dart)
- [local_media_adapter_test.dart](file://test/unit/sources/local_media_adapter_test.dart)
- [app_playback_controller_test.dart](file://test/unit/playback/app_playback_controller_test.dart)
- [main_scaffold_test.dart](file://test/widget/main_scaffold_test.dart)
- [state_widgets_test.dart](file://test/widget/state_widgets_test.dart)
- [database_provider.dart](file://lib/data/database/database_provider.dart)
- [repository_providers.dart](file://lib/data/repositories/repository_providers.dart)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Project Structure](#project-structure)
3. [Core Components](#core-components)
4. [Architecture Overview](#architecture-overview)
5. [Detailed Component Analysis](#detailed-component-analysis)
6. [Dependency Analysis](#dependency-analysis)
7. [Performance Considerations](#performance-considerations)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Conclusion](#conclusion)
10. [Appendices](#appendices)

## Introduction
This document explains the testing strategy for MyTube, a Flutter application focused on local Android video library management and playback. The codebase uses a layered architecture with domain logic, Drift-backed data access, platform bridges for Android Media Store and SAF, Riverpod state management, and a video player abstraction.

The testing approach follows a clear pyramid:
- Unit tests validate domain logic, database operations, source adapters, platform bridge implementations, and playback controllers.
- Widget tests validate UI components, navigation behavior, and state-driven rendering.
- Integration testing is intentionally deferred until a device test harness is available; manual device checks cover scenarios that cannot be automated with in-memory databases and fake platform bridges.

The project’s package manifest declares `flutter_test` as a development dependency, along with Drift tooling and the video player platform interface used by tests. The README is minimal and does not define additional testing conventions, so this document derives its guidance directly from the existing test files and production providers.

**Section sources**
- [pubspec.yaml:19-25](file://pubspec.yaml#L19-L25)
- [README.md:1-4](file://README.md#L1-L4)
- [device_testing_p3.md:101-107](file://docs/device_testing_p3.md#L101-L107)

## Project Structure
The test directory is organized by scope rather than by feature:
- `test/unit/`: Pure Dart unit tests grouped under `database`, `domain`, `platform`, `playback`, and `sources`.
- `test/widget/`: Flutter widget tests for app shell, theme, scaffold navigation, and shared state widgets.
- There is no `test/integration/` directory yet; integration testing is deferred per project documentation.

```mermaid
graph TB
TestRoot["test"] --> Unit["unit"]
TestRoot --> Widget["widget"]
Unit --> Database["database"]
Unit --> Domain["domain"]
Unit --> Platform["platform"]
Unit --> Playback["playback"]
Unit --> Sources["sources"]
Widget --> Shell["app_shell_test.dart"]
Widget --> Theme["app_theme_test.dart"]
Widget --> Scaffold["main_scaffold_test.dart"]
Widget --> StateWidgets["state_widgets_test.dart"]
```

**Diagram sources**
- [app_database_test.dart:1-37](file://test/unit/database/app_database_test.dart#L1-L37)
- [main_scaffold_test.dart:1-123](file://test/widget/main_scaffold_test.dart#L1-L123)
- [state_widgets_test.dart:1-289](file://test/widget/state_widgets_test.dart#L1-L289)

**Section sources**
- [app_database_test.dart:1-37](file://test/unit/database/app_database_test.dart#L1-L37)
- [main_scaffold_test.dart:1-123](file://test/widget/main_scaffold_test.dart#L1-L123)
- [state_widgets_test.dart:1-289](file://test/widget/state_widgets_test.dart#L1-L289)
- [device_testing_p3.md:101-107](file://docs/device_testing_p3.md#L101-L107)

## Core Components
MyTube’s test suite covers several core areas:

| Area | Purpose | Representative Tests |
|---|---|---|
| Database | Validate Drift database opening, schema version, migrations, repository behavior, and watch progress persistence. | `app_database_test.dart`, `drift_video_repository_test.dart`, `migrations_test.dart`, `schema_test.dart`, `watch_progress_test.dart` |
| Domain | Validate availability checking across provider types, cancellation, user metadata preservation, and cross-provider isolation. | `availability_check_service_test.dart` |
| Platform Bridges | Validate MethodChannel communication, permission status mapping, and error handling for Android integrations. | `media_store_bridge_impl_test.dart`, `saf_bridge_impl_test.dart` |
| Source Adapters | Validate local media listing, deduplication, permission handling, availability checks, and playback resolution. | `local_media_adapter_test.dart` |
| Playback Controller | Validate engine lifecycle, state transitions, command idempotency, stale load handling, and Riverpod provider disposal. | `app_playback_controller_test.dart`, `video_player_handle_test.dart` |
| Widgets | Validate navigation destinations, default tab behavior, IndexedStack behavior, and shared UI state widgets. | `main_scaffold_test.dart`, `state_widgets_test.dart`, `app_shell_test.dart`, `app_theme_test.dart` |

Key patterns observed:
- Manual fakes are preferred over external mocking libraries.
- Constructor injection isolates dependencies such as platform bridges and repositories.
- Riverpod overrides are used to inject in-memory databases and fake player handles.
- `TestDefaultBinaryMessengerBinding` mocks platform channels without requiring a real device.

**Section sources**
- [app_database_test.dart:1-37](file://test/unit/database/app_database_test.dart#L1-L37)
- [drift_video_repository_test.dart:1-212](file://test/unit/database/drift_video_repository_test.dart#L1-L212)
- [availability_check_service_test.dart:1-469](file://test/unit/domain/availability_check_service_test.dart#L1-L469)
- [media_store_bridge_impl_test.dart:1-251](file://test/unit/platform/media_store_bridge_impl_test.dart#L1-L251)
- [local_media_adapter_test.dart:1-426](file://test/unit/sources/local_media_adapter_test.dart#L1-L426)
- [app_playback_controller_test.dart:1-568](file://test/unit/playback/app_playback_controller_test.dart#L1-L568)
- [main_scaffold_test.dart:1-123](file://test/widget/main_scaffold_test.dart#L1-L123)
- [state_widgets_test.dart:1-289](file://test/widget/state_widgets_test.dart#L1-L289)

## Architecture Overview
The testing strategy maps cleanly onto the application architecture:

```mermaid
graph TB
subgraph "Tests"
UT["Unit Tests"]
WT["Widget Tests"]
end
subgraph "Application"
Domain["Domain Services"]
Data["Drift Repository"]
DB["AppDatabase"]
Platform["Platform Bridges"]
Player["Playback Controller"]
UI["Flutter Widgets"]
end
UT --> Domain
UT --> Data
UT --> Platform
UT --> Player
WT --> UI
Data --> DB
Domain --> Data
Domain --> Platform
Player --> Platform
UI --> Player
```

This diagram shows how unit tests exercise domain services, repositories, platform bridges, and playback controllers, while widget tests exercise the Flutter UI layer. Platform interactions are isolated through bridges and channel mocks.

**Diagram sources**
- [availability_check_service_test.dart:1-469](file://test/unit/domain/availability_check_service_test.dart#L1-L469)
- [media_store_bridge_impl_test.dart:1-251](file://test/unit/platform/media_store_bridge_impl_test.dart#L1-L251)
- [app_playback_controller_test.dart:1-568](file://test/unit/playback/app_playback_controller_test.dart#L1-L568)
- [main_scaffold_test.dart:1-123](file://test/widget/main_scaffold_test.dart#L1-L123)

## Detailed Component Analysis

### Unit Testing Patterns

#### Domain Logic Testing
The availability check service tests demonstrate a comprehensive pattern:
- Fakes implement domain interfaces (`VideoSourceAdapter`, `SafBridge`, `MediaStoreBridge`).
- An in-memory Drift database is created per test group.
- A helper inserts `VideoItem` and `SourceLocation` pairs to simulate realistic database state.
- Tests assert both returned results and persisted database changes.
- Cancellation, cross-provider isolation, adapter errors, and user metadata preservation are explicitly covered.

```mermaid
flowchart TD
Start(["Availability Check Test"]) --> SetupDB["Create In-Memory AppDatabase"]
SetupDB --> InsertLocations["Insert VideoItem + SourceLocation"]
InsertLocations --> ConfigureFakes["Configure Fake Adapter/Bridges"]
ConfigureFakes --> CallService["Call AvailabilityCheckService.checkAvailability"]
CallService --> AssertResult["Assert checked/became counts"]
AssertResult --> AssertDB["Assert Database Updated Correctly"]
AssertDB --> End(["Test Complete"])
```

**Diagram sources**
- [availability_check_service_test.dart:142-168](file://test/unit/domain/availability_check_service_test.dart#L142-L168)
- [availability_check_service_test.dart:170-467](file://test/unit/domain/availability_check_service_test.dart#L170-L467)

**Section sources**
- [availability_check_service_test.dart:14-94](file://test/unit/domain/availability_check_service_test.dart#L14-L94)
- [availability_check_service_test.dart:100-136](file://test/unit/domain/availability_check_service_test.dart#L100-L136)
- [availability_check_service_test.dart:142-467](file://test/unit/domain/availability_check_service_test.dart#L142-L467)

#### Drift Database Testing
Database tests focus on:
- Opening an in-memory database.
- Verifying schema version.
- Ensuring clean close behavior.
- Repository-level assertions for insert-on-conflict-update behavior and user field preservation.
- Provider wiring validation using Riverpod overrides.

```mermaid
sequenceDiagram
participant Test as "Test File"
participant DB as "AppDatabase.inMemory()"
participant Repo as "DriftVideoRepository"
participant Container as "ProviderContainer"
Test->>DB : Create in-memory database
Test->>Repo : Inject repository
Test->>Repo : Perform insert/update operations
Repo->>DB : Execute Drift queries
DB-->>Repo : Return Ok result
Repo-->>Test : Assert repository behavior
Test->>Container : Override databaseProvider
Container->>Repo : Resolve videoRepositoryProvider
Repo-->>Container : Return DriftVideoRepository instance
```

**Diagram sources**
- [app_database_test.dart:4-34](file://test/unit/database/app_database_test.dart#L4-L34)
- [drift_video_repository_test.dart:35-212](file://test/unit/database/drift_video_repository_test.dart#L35-L212)
- [database_provider.dart:1-17](file://lib/data/database/database_provider.dart#L1-L17)
- [repository_providers.dart:1-24](file://lib/data/repositories/repository_providers.dart#L1-L24)

**Section sources**
- [app_database_test.dart:4-34](file://test/unit/database/app_database_test.dart#L4-L34)
- [drift_video_repository_test.dart:35-212](file://test/unit/database/drift_video_repository_test.dart#L35-L212)
- [database_provider.dart:1-17](file://lib/data/database/database_provider.dart#L1-L17)
- [repository_providers.dart:1-24](file://lib/data/repositories/repository_providers.dart#L1-L24)

#### Platform Channel Communication Testing
Platform bridge tests use `TestDefaultBinaryMessengerBinding` to mock method channels:
- A `MethodChannel` is defined with the expected platform name.
- `setHandler` configures responses for specific method calls.
- `tearDown` clears the mock handler to avoid cross-test pollution.
- Success, empty list, permission-denied, and unexpected error paths are tested.
- Permission status strings are mapped to typed enums.

```mermaid
sequenceDiagram
participant Test as "media_store_bridge_impl_test.dart"
participant Messenger as "TestDefaultBinaryMessengerBinding"
participant Channel as "MethodChannel"
participant Bridge as "MediaStoreBridgeImpl"
Test->>Messenger : setMockMethodCallHandler(channel, handler)
Test->>Bridge : queryVideos()
Bridge->>Channel : invokeMethod("queryVideos")
Channel-->>Bridge : Mocked response or PlatformException
Bridge-->>Test : Ok or Err result
Test->>Messenger : setMockMethodCallHandler(channel, null)
```

**Diagram sources**
- [media_store_bridge_impl_test.dart:8-21](file://test/unit/platform/media_store_bridge_impl_test.dart#L8-L21)
- [media_store_bridge_impl_test.dart:28-130](file://test/unit/platform/media_store_bridge_impl_test.dart#L28-L130)
- [media_store_bridge_impl_test.dart:136-249](file://test/unit/platform/media_store_bridge_impl_test.dart#L136-L249)

**Section sources**
- [media_store_bridge_impl_test.dart:8-21](file://test/unit/platform/media_store_bridge_impl_test.dart#L8-L21)
- [media_store_bridge_impl_test.dart:28-130](file://test/unit/platform/media_store_bridge_impl_test.dart#L28-L130)
- [media_store_bridge_impl_test.dart:136-249](file://test/unit/platform/media_store_bridge_impl_test.dart#L136-L249)

#### Video Source Adapter Testing
Local media adapter tests validate:
- Capability flags.
- Listing videos from Media Store and SAF.
- Deduplication when the same URI appears in both sources.
- Cancellation before work begins.
- Permission revocation handling.
- Error propagation versus safe null returns.
- Playback resolution and download eligibility.

```mermaid
flowchart TD
Start(["LocalMediaAdapter Test"]) --> ConfigureBridges["Configure Fake MediaStoreBridge and SafBridge"]
ConfigureBridges --> ListVideos["Call listVideos"]
ListVideos --> MergeResults{"Merge MediaStore and SAF"}
MergeResults --> Deduplicate["Deduplicate by URI"]
Deduplicate --> AssertPage["Assert SourcePage contents"]
AssertPage --> GetVideo["Call getVideo / resolveForPlayback"]
GetVideo --> AssertResult["Assert Ok/Err behavior"]
AssertResult --> End(["Test Complete"])
```

**Diagram sources**
- [local_media_adapter_test.dart:100-112](file://test/unit/sources/local_media_adapter_test.dart#L100-L112)
- [local_media_adapter_test.dart:114-260](file://test/unit/sources/local_media_adapter_test.dart#L114-L260)
- [local_media_adapter_test.dart:262-426](file://test/unit/sources/local_media_adapter_test.dart#L262-L426)

**Section sources**
- [local_media_adapter_test.dart:100-112](file://test/unit/sources/local_media_adapter_test.dart#L100-L112)
- [local_media_adapter_test.dart:114-260](file://test/unit/sources/local_media_adapter_test.dart#L114-L260)
- [local_media_adapter_test.dart:262-426](file://test/unit/sources/local_media_adapter_test.dart#L262-L426)

#### Playback Controller Testing
Playback controller tests are extensive and demonstrate advanced testing techniques:
- A manual `FakePlayerHandle` implements `PlayerHandle` without external mocking libraries.
- Tests drive engine snapshots and change streams to simulate real player events.
- Stale load handling is verified using a `Completer` gate.
- Command idempotency, clamping, preference carryover, and lifecycle disposal are validated.
- Riverpod provider disposal is tested using `ProviderContainer`.

```mermaid
classDiagram
class FakePlayerHandle {
+PlayerSnapshot snapshot
+Stream~void~ changes
+initialize() void
+play() void
+pause() void
+seekTo(position) void
+setVolume(volume) void
+setSpeed(speed) void
+dispose() void
+emitChange() void
}
class AppPlaybackController {
+state
+play(source) Future
+pause() Future
+resume() Future
+seekTo(position) Future
+skipForward(delta) Future
+skipBackward(delta) Future
+setSpeed(speed) Future
+setVolume(volume) Future
+stop() Future
+dispose() Future
}
AppPlaybackController --> FakePlayerHandle : "uses via handleFactory"
```

**Diagram sources**
- [app_playback_controller_test.dart:13-96](file://test/unit/playback/app_playback_controller_test.dart#L13-L96)
- [app_playback_controller_test.dart:129-568](file://test/unit/playback/app_playback_controller_test.dart#L129-L568)

**Section sources**
- [app_playback_controller_test.dart:13-96](file://test/unit/playback/app_playback_controller_test.dart#L13-L96)
- [app_playback_controller_test.dart:129-568](file://test/unit/playback/app_playback_controller_test.dart#L129-L568)

### Widget Testing Patterns

#### Navigation and Scaffold Testing
The main scaffold tests verify:
- Rendering of a `NavigationBar` with five destinations.
- Default launch tab behavior.
- Tab selection through taps.
- Back navigation to Discover.
- `IndexedStack` keeping all screens in the tree.
- Constant tab index values matching their positions.

```mermaid
sequenceDiagram
participant Tester as "Widget Tester"
participant Scaffold as "MainScaffold"
participant Navigator as "NavigationBar"
participant Screen as "Screen Widgets"
Tester->>Scaffold : pumpWidget(ProviderScope + MaterialApp)
Tester->>Navigator : Find NavigationBar
Tester->>Screen : Verify default screen visible
Tester->>Navigator : Tap destination
Navigator-->>Tester : selectedIndex updated
Tester->>Screen : Verify active screen mounted
```

**Diagram sources**
- [main_scaffold_test.dart:11-13](file://test/widget/main_scaffold_test.dart#L11-L13)
- [main_scaffold_test.dart:15-123](file://test/widget/main_scaffold_test.dart#L15-L123)

**Section sources**
- [main_scaffold_test.dart:11-13](file://test/widget/main_scaffold_test.dart#L11-L13)
- [main_scaffold_test.dart:15-123](file://test/widget/main_scaffold_test.dart#L15-L123)

#### Shared State Widget Testing
State widget tests validate:
- Loading indicator rendering and optional messages.
- Empty state title, message, action button, icon fallback, and custom icons.
- Error state message, retry button behavior, and error icon presence.
- `AsyncValueWidget` routing between loading, data, and error states.
- Sensitive URL parameters are not leaked into user-facing messages.
- Custom loading and error widgets can be provided.

```mermaid
flowchart TD
Start(["AsyncValueWidget Test"]) --> LoadData["Render AsyncLoading"]
LoadData --> ShowLoading["Show LoadingIndicator"]
LoadData --> ProvideData["Provide AsyncData"]
ProvideData --> ShowData["Render onData widget"]
ProvideData --> ProvideError["Provide AsyncError"]
ProvideError --> ShowError["Render ErrorState or fallback"]
ShowError --> VerifyPrivacy["Verify sensitive data not shown"]
ShowError --> End(["Test Complete"])
```

**Diagram sources**
- [state_widgets_test.dart:14-37](file://test/widget/state_widgets_test.dart#L14-L37)
- [state_widgets_test.dart:39-104](file://test/widget/state_widgets_test.dart#L39-L104)
- [state_widgets_test.dart:106-140](file://test/widget/state_widgets_test.dart#L106-L140)
- [state_widgets_test.dart:142-289](file://test/widget/state_widgets_test.dart#L142-L289)

**Section sources**
- [state_widgets_test.dart:14-37](file://test/widget/state_widgets_test.dart#L14-L37)
- [state_widgets_test.dart:39-104](file://test/widget/state_widgets_test.dart#L39-L104)
- [state_widgets_test.dart:106-140](file://test/widget/state_widgets_test.dart#L106-L140)
- [state_widgets_test.dart:142-289](file://test/widget/state_widgets_test.dart#L142-L289)

## Dependency Analysis
Riverpod providers play a central role in testability:
- `databaseProvider` creates and disposes `AppDatabase`.
- `videoRepositoryProvider` depends on `databaseProvider` and returns a `DriftVideoRepository`.
- Tests override these providers to inject in-memory databases and fake dependencies.

```mermaid
graph LR
DatabaseProvider["databaseProvider"] --> AppDatabase["AppDatabase"]
RepositoryProvider["videoRepositoryProvider"] --> DatabaseProvider
RepositoryProvider --> DriftRepo["DriftVideoRepository"]
TestOverrides["Test Overrides"] --> DatabaseProvider
TestOverrides --> RepositoryProvider
```

**Diagram sources**
- [database_provider.dart:1-17](file://lib/data/database/database_provider.dart#L1-L17)
- [repository_providers.dart:1-24](file://lib/data/repositories/repository_providers.dart#L1-L24)
- [drift_video_repository_test.dart:191-212](file://test/unit/database/drift_video_repository_test.dart#L191-L212)

**Section sources**
- [database_provider.dart:1-17](file://lib/data/database/database_provider.dart#L1-L17)
- [repository_providers.dart:1-24](file://lib/data/repositories/repository_providers.dart#L1-L24)
- [drift_video_repository_test.dart:191-212](file://test/unit/database/drift_video_repository_test.dart#L191-L212)

## Performance Considerations
- In-memory Drift databases keep unit tests fast and deterministic.
- Manual fakes avoid the overhead of reflection-based mocking libraries.
- Widget tests use minimal wrappers like `MaterialApp(home: Scaffold(body: child))` to reduce test surface area.
- Platform channel mocks avoid launching real Android processes during unit tests.
- Playback controller tests use event queue pumping and gates to control asynchronous timing without relying on real timers.

[No sources needed since this section provides general guidance]

## Troubleshooting Guide

### Common Testing Issues and Solutions

| Issue | Symptom | Solution |
|---|---|---|
| Platform channel leaks between tests | Mock handlers affect unrelated tests | Clear `TestDefaultBinaryMessengerBinding` handler in `tearDown`. |
| Database not closed | Resource warnings or flaky tests | Close `AppDatabase` in `tearDown` after each test group. |
| Riverpod container not disposed | Fake resources remain alive | Use `addTearDown(container.dispose)` and await event queue if teardown is asynchronous. |
| Player handle not released | Engine resources leak | Ensure `FakePlayerHandle.dispose` closes streams and increment disposal counters. |
| Sensitive data in error messages | User-facing logs contain URLs or tokens | Assert that generic messages replace raw engine details. |
| Integration tests missing | CI only runs unit and widget tests | Follow the project decision to defer `test/integration/` until a device harness exists. |

**Section sources**
- [media_store_bridge_impl_test.dart:18-21](file://test/unit/platform/media_store_bridge_impl_test.dart#L18-L21)
- [app_database_test.dart:8-14](file://test/unit/database/app_database_test.dart#L8-L14)
- [app_playback_controller_test.dart:543-565](file://test/unit/playback/app_playback_controller_test.dart#L543-L565)
- [device_testing_p3.md:101-107](file://docs/device_testing_p3.md#L101-L107)

## Conclusion
MyTube’s testing strategy is well-structured around a clear pyramid:
- Unit tests isolate domain logic, database operations, platform bridges, source adapters, and playback controllers.
- Widget tests validate navigation, rendering, and shared state behavior.
- Integration testing is deferred until a device harness is established, with manual device checks covering platform-only scenarios.

The codebase demonstrates strong testing practices:
- Manual fakes for external dependencies.
- Constructor injection for testable design.
- Riverpod provider overrides for database and player wiring.
- Platform channel mocking for Android integrations.
- Explicit assertions for both results and side effects like database mutations.

New tests should follow these patterns:
- Place unit tests under `test/unit/<area>/`.
- Place widget tests under `test/widget/`.
- Use constructor injection and manual fakes instead of global singletons.
- Wrap platform channel tests with proper setup and teardown.
- Prefer in-memory databases and fake bridges over real platform dependencies.
- Assert both return values and observable side effects.

[No sources needed since this section summarizes without analyzing specific files]

## Appendices

### Naming Conventions
- Test files mirror production structure where applicable, e.g., `local_media_adapter_test.dart` for `LocalMediaAdapter`.
- Group names describe the component under test, e.g., `AvailabilityCheckService (P3-06)`.
- Individual tests use descriptive names indicating scenario and expectation.

**Section sources**
- [availability_check_service_test.dart:142-143](file://test/unit/domain/availability_check_service_test.dart#L142-L143)
- [local_media_adapter_test.dart:103-104](file://test/unit/sources/local_media_adapter_test.dart#L103-L104)
- [media_store_bridge_impl_test.dart:23-24](file://test/unit/platform/media_store_bridge_impl_test.dart#L23-L24)

### Assertion Patterns
- Use `expect(result.isOk, isTrue)` and `expect(result.isErr, isTrue)` for `Result` types.
- Cast results to `Ok<T>` or `Err<T>` before asserting inner values.
- Assert database state after service calls to verify side effects.
- Assert widget visibility, tap callbacks, and finder counts in widget tests.
- Assert call counts, lists, and state fields in playback controller tests.

**Section sources**
- [availability_check_service_test.dart:170-467](file://test/unit/domain/availability_check_service_test.dart#L170-L467)
- [local_media_adapter_test.dart:114-426](file://test/unit/sources/local_media_adapter_test.dart#L114-L426)
- [main_scaffold_test.dart:15-123](file://test/widget/main_scaffold_test.dart#L15-L123)
- [state_widgets_test.dart:14-289](file://test/widget/state_widgets_test.dart#L14-L289)

### Continuous Integration Guidance
- Run `flutter test` to execute both unit and widget tests.
- Coverage expectations should prioritize unit tests for domain, database, platform bridges, and playback logic.
- Widget tests should cover critical navigation and state rendering paths.
- Integration tests should be added once a device harness is available, following the project’s deferred integration plan.

**Section sources**
- [pubspec.yaml:19-25](file://pubspec.yaml#L19-L25)
- [device_testing_p3.md:101-107](file://docs/device_testing_p3.md#L101-L107)