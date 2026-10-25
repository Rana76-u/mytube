import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/domain/services/scan_settings_notifier.dart';
import 'package:mytube/platform/platform_providers.dart';
import 'package:mytube/sources/local/local_media_adapter.dart';

/// Riverpod provider that wires the platform bridges into [LocalMediaAdapter].
///
/// Watches [scanEntireDeviceProvider] so the Settings scan-location toggle
/// re-materialises the adapter with the matching scan scope (folders-only
/// scans skip the whole-device MediaStore enumeration).
///
/// Consumers that need the adapter directly (e.g. domain services) should
/// watch this provider.  The [videoSourceAdaptersProvider] in
/// [source_registry.dart] exposes the full ordered list of adapters for
/// higher-level use.
final localMediaAdapterProvider = Provider<LocalMediaAdapter>((ref) {
  final scanAll = ref.watch(scanEntireDeviceProvider);
  return LocalMediaAdapter(
    mediaStoreBridge: ref.watch(mediaStoreBridgeProvider),
    safBridge: ref.watch(safBridgeProvider),
    fullDeviceScan: () => scanAll,
  );
});
