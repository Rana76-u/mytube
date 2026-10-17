import 'package:flutter/foundation.dart' show debugPrint;

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/platform/media_store_bridge.dart';
import 'package:mytube/platform/saf_bridge.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Checks the current reachability of every [SourceLocation] for a given
/// [ProviderType] and updates the stored [AvailabilityState] without
/// deleting rows or touching user-owned metadata (P3-06, AVAIL-001,
/// LOCAL-003, LOCAL-009).
///
/// ### SAF grant lifecycle note
/// SAF folder grants can be silently revoked by Android when the user
/// uninstalls or clears data for the originating app, or when the originating
/// app is updated.  [SafBridge.checkFolderAccess] detects revoked grants;
/// [SafBridge.releasePersistedUri] cleans them up after confirmed revocation.
/// This service does NOT automatically release persisted URIs — that is a
/// user-facing action reserved for the Settings screen (a later phase, not
/// P3-06 scope).
///
/// ### Invariants
/// - Never deletes [VideoItem] or [SourceLocation] rows.
/// - Never overwrites user-owned fields: [isFavourite], [watchProgressMs],
///   [lastPlayedAt], tags, or collections.
/// - A revoked SAF folder causes all of its contained items to transition to
///   [AvailabilityState.permissionRevoked].
/// - A missing file (present in DB but not found) transitions to
///   [AvailabilityState.missing].
/// - A previously-missing item that reappears (e.g. SD card re-inserted)
///   transitions back to [AvailabilityState.available].
/// - If the adapter returns [Err], the item transitions to
///   [AvailabilityState.unknown] and the service continues rather than
///   aborting.
/// - All public methods return [Result<T>].
class AvailabilityCheckService {
  AvailabilityCheckService({
    required VideoSourceAdapter localAdapter,
    required SafBridge safBridge,
    required MediaStoreBridge mediaStoreBridge,
    required VideoRepository repository,
  }) : _localAdapter = localAdapter, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _safBridge = safBridge,
       // ignore: prefer_initializing_formals
       _mediaStoreBridge = mediaStoreBridge,
       // ignore: prefer_initializing_formals
       _repository = repository;

  final VideoSourceAdapter _localAdapter;

  // ignore: unused_field  — held for future per-folder check methods (P3-06+)
  final SafBridge _safBridge;

  // ignore: unused_field  — held for future per-folder check methods (P3-06+)
  final MediaStoreBridge _mediaStoreBridge;

  final VideoRepository _repository;

  // How often to check the cancellation token during the loop.
  static const _cancellationCheckInterval = 10;

  /// Checks the current availability of all [SourceLocation]s for
  /// [providerType] and updates the database rows.
  ///
  /// Returns [Ok(AvailabilityCheckResult)] on success, even when some
  /// individual items encounter errors (those are tallied as [unknown]).
  /// Only returns [Err] when the initial repository load fails.
  Future<Result<AvailabilityCheckResult>> checkAvailability({
    required ProviderType providerType,
    required CancellationToken cancellationToken,
  }) async {
    // Short-circuit if already cancelled.
    if (cancellationToken.isCancelled) {
      return Ok(
        const AvailabilityCheckResult(
          checked: 0,
          becameAvailable: 0,
          becameMissing: 0,
          becamePermissionRevoked: 0,
        ),
      );
    }

    // Load all source locations for this provider.
    final locationsResult = await _repository.getSourceLocationsByProvider(
      providerType,
    );
    final List<SourceLocation> locations;
    switch (locationsResult) {
      case Ok(:final value):
        locations = value;
      case Err(:final error):
        return Err(error);
    }

    var checked = 0;
    var becameAvailable = 0;
    var becameMissing = 0;
    var becamePermissionRevoked = 0;

    for (var i = 0; i < locations.length; i++) {
      // Check cancellation every _cancellationCheckInterval items.
      if (i % _cancellationCheckInterval == 0 &&
          cancellationToken.isCancelled) {
        break;
      }

      final location = locations[i];
      AvailabilityState newState;

      final checkResult = await _localAdapter.checkAvailability(
        location.sourceUri,
      );
      switch (checkResult) {
        case Ok(:final value):
          newState = value;
        case Err(:final error):
          // Non-fatal: log (no sensitive data) and treat as unknown.
          debugPrint(
            'AvailabilityCheckService: checkAvailability error for '
            'location ${location.id} — ${error.diagnosticMessage}',
          );
          newState = AvailabilityState.unknown;
      }

      checked++;

      // Only write to the DB if the state actually changed.
      if (newState != location.availability) {
        final updateResult = await _repository.updateSourceLocationAvailability(
          location.id,
          newState,
          DateTime.now(),
        );
        if (updateResult case Err(:final error)) {
          // Non-fatal: log and continue.
          debugPrint(
            'AvailabilityCheckService: failed to update location '
            '${location.id} — ${error.diagnosticMessage}',
          );
        }

        // Tally the transition.
        switch (newState) {
          case AvailabilityState.available:
            becameAvailable++;
          case AvailabilityState.missing:
            becameMissing++;
          case AvailabilityState.permissionRevoked:
            becamePermissionRevoked++;
          default:
            break;
        }
      }
    }

    return Ok(
      AvailabilityCheckResult(
        checked: checked,
        becameAvailable: becameAvailable,
        becameMissing: becameMissing,
        becamePermissionRevoked: becamePermissionRevoked,
      ),
    );
  }
}

/// Aggregated outcome of one [AvailabilityCheckService.checkAvailability] run.
class AvailabilityCheckResult {
  const AvailabilityCheckResult({
    required this.checked,
    required this.becameAvailable,
    required this.becameMissing,
    required this.becamePermissionRevoked,
  });

  /// Total number of [SourceLocation]s examined this run.
  final int checked;

  /// Locations that transitioned TO [AvailabilityState.available].
  final int becameAvailable;

  /// Locations that transitioned TO [AvailabilityState.missing].
  final int becameMissing;

  /// Locations that transitioned TO [AvailabilityState.permissionRevoked].
  final int becamePermissionRevoked;
}
