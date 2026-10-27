import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/direct_url_service.dart';
import 'package:mytube/domain/services/library_refresh_service.dart';
import 'package:mytube/domain/services/library_refresh_service_provider.dart';
import 'package:mytube/features/library/add_url_dialog.dart';
import 'package:mytube/features/library/library_filter_sheet.dart';
import 'package:mytube/features/library/library_providers.dart';
import 'package:mytube/features/library/library_view_state.dart';

// Library actions shared by the shell header and the Library tab.
//
// The header owns the controls while the tab owns the list, so the behaviour
// (scan, folder pick, URL add, filter sheet) lives in these functions rather
// than in either widget. Each one talks to the same notifiers the tab already
// used; none of them touches persistence directly (AGENTS).

/// Runs a manual library scan (LOCAL-001/LOCAL-008, P3-05).
///
/// The service-side permission gate may raise the MediaStore dialog before
/// scanning. On completion every query family entry is invalidated so each
/// active list/search/filter view picks the new rows up, and a snackbar reports
/// what changed.
Future<void> scanLibraryDevice(BuildContext context, WidgetRef ref) async {
  final result = await ref
      .read(libraryRefreshServiceProvider.notifier)
      .refresh();
  ref.invalidate(libraryItemsProvider);
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(_scanMessageFor(result))));
}

/// Opens the system folder picker and rescans so the newly granted folder is
/// indexed immediately (LOCAL-003, P3-02).
Future<void> chooseLibraryFolder(BuildContext context, WidgetRef ref) async {
  final picked = await ref
      .read(libraryRefreshServiceProvider.notifier)
      .pickFolder();
  if (!context.mounted) return;
  switch (picked) {
    case Ok(value: final folderUri):
      if (folderUri == null) return; // User cancelled the picker.
      await scanLibraryDevice(context, ref);
    case Err(:final error):
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
  }
}

/// Opens the one-at-a-time URL entry dialog (P4-01, URL-001) and refreshes the
/// library when a URL was added.
Future<void> addDirectUrl(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<DirectUrlEntryResult>(
    context: context,
    builder: (_) => const AddUrlDialog(),
  );
  if (result == null) return;
  ref.invalidate(libraryItemsProvider);
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(_snackbarMessageFor(result))));
}

/// Opens the filter bottom sheet and applies whatever [VideoFilter] the user
/// returns (P5-03, LIB-004).
Future<void> openLibraryFilterSheet(BuildContext context, WidgetRef ref) async {
  final current = ref.read(libraryViewStateProvider).filter;
  final updated = await showModalBottomSheet<VideoFilter>(
    context: context,
    isScrollControlled: true,
    builder: (_) => LibraryFilterSheet(current: current),
  );
  if (updated == null) return;
  ref.read(libraryViewStateProvider.notifier).setFilter(updated);
}

/// User-safe scan outcome. Permission denial points at the retry path; nothing
/// here echoes raw diagnostics (AGENTS privacy rules).
String _scanMessageFor(Result<LibraryRefreshResult> result) {
  return switch (result) {
    // A cancelled run reports the rows it already merged, but never claims the
    // library was fully resynced.
    Ok(:final value) when value.wasCancelled =>
      value.totalAdded > 0
          ? 'Scan cancelled — ${value.totalAdded} new video'
                '${value.totalAdded == 1 ? '' : 's'} added.'
          : 'Scan cancelled.',
    Ok(:final value) when value.totalAdded > 0 =>
      'Scan complete — ${value.totalAdded} new video'
          '${value.totalAdded == 1 ? '' : 's'} added.',
    Ok() => 'Scan complete — no new videos found.',
    Err(:final error) => error.userMessage,
  };
}

/// User-safe feedback that mirrors the probed availability (URL-003).
String _snackbarMessageFor(DirectUrlEntryResult result) {
  switch (result.availability) {
    case AvailabilityState.available:
      return result.isNew ? 'URL added to your library.' : 'URL refreshed.';
    case AvailabilityState.offline:
      return 'URL added. The source seems unreachable right now.';
    default:
      return 'URL added. Reachability could not be confirmed.';
  }
}
