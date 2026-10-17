---
kind: external_dependency
name: flutter_riverpod 3.x state management
slug: riverpod
category: external_dependency
category_hints:
    - framework_behavior
scope:
    - '**'
source_files:
    - DECISIONS.md
    - pubspec.yaml
---

Chosen in DECISIONS.md P0-02; `ProviderScope` wrapped once in `lib/app`. Widgets read Notifiers/`AsyncValue`; Riverpod holds handles to services (e.g. `playbackControllerProvider`) but must not leak engine types into widgets. Generator (`riverpod_generator`) intentionally skipped until handwritten providers slow development.