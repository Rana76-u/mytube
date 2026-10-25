import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart'
    show LocalSourceSweeper;
import 'package:mytube/domain/services/library_refresh_service.dart';
import 'package:mytube/domain/services/scan_merge_service_provider.dart';
import 'package:mytube/domain/services/scan_settings_notifier.dart';
import 'package:mytube/platform/platform_providers.dart';
import 'package:mytube/sources/source_registry.dart';

/// Riverpod provider for [LibraryRefreshNotifier].
///
/// Exposes [RefreshState] as the state and gives widgets access to
/// [LibraryRefreshNotifier.refresh] / [LibraryRefreshNotifier.cancel] via
/// `ref.read(libraryRefreshServiceProvider.notifier)`.
final libraryRefreshServiceProvider =
    NotifierProvider<LibraryRefreshNotifier, RefreshState>(
      LibraryRefreshNotifier.new,
    );

/// Bridges [LibraryRefreshService] to Riverpod's [Notifier].
///
/// Owns the [LibraryRefreshService] lifecycle: creates it in [build],
/// subscribes to its [RefreshState] stream, forwards state updates, and
/// cancels the subscription when Riverpod rebuilds or removes this notifier.
class LibraryRefreshNotifier extends Notifier<RefreshState> {
  late LibraryRefreshService _service;
  StreamSubscription<RefreshState>? _subscription;

  @override
  RefreshState build() {
    final adapters = ref.watch(videoSourceAdaptersProvider);
    final mergeService = ref.watch(scanMergeServiceProvider);
    // Folders-only scans read SAF grants exclusively, so the MediaStore
    // permission gate is not needed; passing the null seam skips it and
    // avoids prompting for a permission the chosen scan scope never uses.
    final scanAll = ref.watch(scanEntireDeviceProvider);

    _service = LibraryRefreshService(
      adapters: adapters,
      mergeService: mergeService,
      preferences: const LibraryRefreshPreferences(),
      mediaStore: scanAll ? ref.watch(mediaStoreBridgeProvider) : null,
    );

    _subscription = _service.refreshState.listen((s) => state = s);

    // Dispose the service and subscription when Riverpod invalidates this
    // notifier (e.g. watched providers changed or container is disposed).
    ref.onDispose(() {
      _subscription?.cancel();
      _service.dispose();
    });

    return const RefreshIdle();
  }

  /// Starts a library refresh.
  ///
  /// Defaults to [RefreshTrigger.manual] so UI call-sites do not have to
  /// specify the trigger explicitly.
  Future<Result<LibraryRefreshResult>> refresh({
    RefreshTrigger trigger = RefreshTrigger.manual,
  }) => _service.refresh(trigger: trigger);

  /// Cancels any in-progress refresh.
  void cancel() => _service.cancel();

  /// Re-scans the library with the current scan locations and then
  /// de-indexes local entries the scan proved absent (`missing` /
  /// `permissionRevoked`), together with video items left without any source
  /// (SET-002 scan-location changes).
  ///
  /// Call this right after a [ScanSettingsNotifier] action so Settings edits
  /// apply immediately without a manual pull-to-refresh. It lives here —
  /// rather than inside the scan-settings notifier — because this notifier
  /// already depends on the scan scope, and having the settings notifier
  /// read back would form a circular provider dependency.
  ///
  /// Data-integrity rules (AGENTS): only rows a *completed* scan observed as
  /// gone are removed; items that still have another source (duplicate copy,
  /// direct URL, cloud) keep their row and user metadata; original files and
  /// other providers' rows are never touched. If the refresh fails nothing
  /// is de-indexed — the caller's error surfaces and the user can retry.
  Future<Result<LibraryRefreshResult>> rescanAndDeindex() async {
    final refreshed = await refresh();
    if (refreshed case Err()) return refreshed;
    final repository = ref.read(videoRepositoryProvider);
    if (repository case final LocalSourceSweeper sweeper) {
      await sweeper.deindexMissingLocalSources();
    }
    return refreshed;
  }

  /// Opens the system folder picker and persists the chosen folder's read
  /// grant so the next [refresh] scans it (LOCAL-003, P3-02).
  ///
  /// Returns the folder URI, `null` when the user cancelled, or an [Err]
  /// when the picker/persistence failed. Kept on this notifier so feature
  /// widgets go through a service seam instead of touching the platform
  /// bridge directly.
  Future<Result<String?>> pickFolder() =>
      ref.read(safBridgeProvider).openFolderPicker();
}
