import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/availability_check_service_provider.dart';

/// Bottom sheet listing every source location of one logical video item,
/// with primary selection and availability retry actions (P7-06/P7-07,
/// DUP-005, AVAIL-001/AVAIL-002, LIB-008).
///
/// A duplicate group is ONE item with several locations (P7-05); this sheet is
/// where the user chooses which location plays (DUP-005 — the choice is
/// persisted via [VideoRepository.setPrimarySourceLocation] and honoured by
/// the playback resolver) and where unavailable rows offer retry/reconnect
/// actions instead of disappearing (AVAIL-001/AVAIL-002).
///
/// Removing sources is deliberately NOT offered here — removing a library
/// entry only ever removes app metadata (LIB-008) and is separate future UI
/// work; this task is selection + availability.
class ManageSourcesSheet extends ConsumerStatefulWidget {
  const ManageSourcesSheet({super.key, required this.video});

  final VideoItemSummary video;

  @override
  ConsumerState<ManageSourcesSheet> createState() => _ManageSourcesSheetState();
}

class _ManageSourcesSheetState extends ConsumerState<ManageSourcesSheet> {
  List<SourceLocation> _locations = const [];
  bool _loading = true;
  bool _busy = false;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repository = ref.read(videoRepositoryProvider);
    final result = await repository.getSourceLocationsForVideo(widget.video.id);
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        setState(() {
          _locations = value;
          _loading = false;
        });
      case Err(:final error):
        setState(() {
          _error = error;
          _loading = false;
        });
    }
  }

  Future<void> _setPrimary(SourceLocation location) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repository = ref.read(videoRepositoryProvider);
    final result = await repository.setPrimarySourceLocation(
      videoItemId: widget.video.id.value,
      locationId: location.id,
    );
    if (!mounted) return;
    if (result case Err(:final error)) {
      _fail(error);
      return;
    }
    // Re-read so ordering (primary first) reflects the change.
    await _loadLocations();
    if (mounted) setState(() => _busy = false);
  }

  /// Retry for one location — routes to the reconnect-capable flow when the
  /// state says user action is required (AVAIL-002).
  Future<void> _recheck(SourceLocation location) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = ref.read(availabilityCheckServiceProvider);
    final result = await switch (location.availability) {
      AvailabilityState.permissionRevoked
          when location.providerType == ProviderType.localMediaStore =>
        service.requestMediaStoreAccessAndRecheck(location),
      AvailabilityState.permissionRevoked
          when location.providerType == ProviderType.selectedFolder =>
        service.reconnectFolderAndRecheck(location),
      _ => service.recheckLocation(location),
    };
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        setState(() {
          _locations = [
            for (final loc in _locations)
              if (loc.id == location.id)
                SourceLocation(
                  id: loc.id,
                  videoItemId: loc.videoItemId,
                  providerType: loc.providerType,
                  sourceUri: loc.sourceUri,
                  displayName: loc.displayName,
                  availability: value,
                  lastCheckedAt: DateTime.now(),
                  sizeBytes: loc.sizeBytes,
                  thumbnailUri: loc.thumbnailUri,
                  isPrimary: loc.isPrimary,
                )
              else
                loc,
          ];
          _busy = false;
        });
      case Err(:final error):
        _fail(error);
    }
  }

  void _fail(AppError error) {
    setState(() {
      _error = error;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Manage sources', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        widget.video.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  key: const ValueKey('manage_sources_done'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error!.userMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              )
            else if (_locations.isEmpty)
              Text(
                'No sources are attached to this video.',
                style: theme.textTheme.bodyMedium,
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final location in _locations)
                        _SourceRow(
                          location: location,
                          showPrimaryAction:
                              _locations.length > 1 && !location.isPrimary,
                          busy: _busy,
                          onSetPrimary: () => _setPrimary(location),
                          onRecheck: () => _recheck(location),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One location row: label, provider, availability badge, primary marker,
/// and the retry/set-primary actions (P7-06/P7-07).
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.location,
    required this.showPrimaryAction,
    required this.busy,
    required this.onSetPrimary,
    required this.onRecheck,
  });

  final SourceLocation location;
  final bool showPrimaryAction;
  final bool busy;
  final VoidCallback onSetPrimary;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = location.displayName ?? _shorten(location);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: location.isPrimary ? FontWeight.bold : null,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      _providerLabel(location.providerType),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _AvailabilityBadge(state: location.availability),
                    if (location.isPrimary) ...[
                      const SizedBox(width: 8),
                      Text(
                        'Primary',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (showPrimaryAction)
            TextButton(
              key: ValueKey('source_primary_${location.id}'),
              onPressed: busy ? null : onSetPrimary,
              child: const Text('Set primary'),
            ),
          IconButton(
            key: ValueKey('source_recheck_${location.id}'),
            icon: const Icon(Icons.refresh),
            tooltip: _recheckTooltip(location),
            visualDensity: VisualDensity.compact,
            onPressed: busy ? null : onRecheck,
          ),
        ],
      ),
    );
  }

  static String _providerLabel(ProviderType type) => switch (type) {
    ProviderType.localMediaStore => 'This device',
    ProviderType.selectedFolder => 'Selected folder',
    ProviderType.directUrl => 'Direct URL',
    ProviderType.oneDrive => 'OneDrive',
    ProviderType.googleDrive => 'Google Drive',
    ProviderType.cloudflareR2 => 'Cloudflare R2',
  };

  static String _recheckTooltip(SourceLocation location) {
    if (location.availability == AvailabilityState.permissionRevoked &&
        location.providerType == ProviderType.selectedFolder) {
      return 'Reconnect folder';
    }
    if (location.availability == AvailabilityState.permissionRevoked &&
        location.providerType == ProviderType.localMediaStore) {
      return 'Grant access again';
    }
    return 'Check again';
  }

  /// A user-safe source description. Never shows raw signed URLs in full —
  /// the query portion (which may carry tokens) is dropped (privacy rules).
  static String _shorten(SourceLocation location) {
    final uri = Uri.tryParse(location.sourceUri);
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.hasAuthority) {
      return '${uri.host}${uri.path}';
    }
    final segment = location.sourceUri.split('/').last;
    return segment.isEmpty ? location.sourceUri : segment;
  }
}

/// Coloured chip mirroring the location's [AvailabilityState] (AVAIL-001 —
/// unavailable entries stay listed with their status, they never vanish).
class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({required this.state});

  final AvailabilityState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (state) {
      AvailabilityState.available => ('Available', theme.colorScheme.primary),
      AvailabilityState.offline => ('Offline', theme.colorScheme.tertiary),
      AvailabilityState.missing => ('Missing', theme.colorScheme.error),
      AvailabilityState.expiredLink => (
        'Expired link',
        theme.colorScheme.error,
      ),
      AvailabilityState.reconnectRequired => (
        'Reconnect needed',
        theme.colorScheme.error,
      ),
      AvailabilityState.permissionRevoked => (
        'Access revoked',
        theme.colorScheme.error,
      ),
      AvailabilityState.unsupported => ('Unsupported', theme.colorScheme.error),
      AvailabilityState.unknown => (
        'Unknown',
        theme.colorScheme.onSurfaceVariant,
      ),
    };
    return Container(
      key: ValueKey('availability_${state.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
