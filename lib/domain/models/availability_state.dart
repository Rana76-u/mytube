/// Represents the current reachability of a single source location
/// (ARCHITECTURE §12, AVAIL-001).
///
/// Availability is stored on a [source_locations] row and updated by scans,
/// adapters, and playback attempts.  The UI shows the state alongside a
/// source entry and offers retry/reconnect actions where appropriate
/// (AVAIL-002).
enum AvailabilityState {
  /// Source has been verified reachable recently.
  available,

  /// Device is offline; source may still exist but cannot be verified.
  offline,

  /// Source was previously reachable but the file/item can no longer be found.
  missing,

  /// A time-limited link (e.g. a pre-signed URL) has expired.
  expiredLink,

  /// OAuth consent was revoked; user must re-authenticate.
  reconnectRequired,

  /// SAF folder grant was revoked or file permission was denied.
  permissionRevoked,

  /// The source format or codec is not supported by the current player.
  unsupported,

  /// Availability has not yet been checked or is otherwise indeterminate.
  unknown;

  /// True when the source might become available again without the user
  /// taking action (e.g. device coming back online).
  bool get isTransient =>
      this == AvailabilityState.offline || this == AvailabilityState.unknown;

  /// True when the user must take an explicit action to restore access.
  bool get requiresUserAction =>
      this == AvailabilityState.reconnectRequired ||
      this == AvailabilityState.permissionRevoked ||
      this == AvailabilityState.expiredLink;
}
