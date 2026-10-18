import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/services/availability_check_service.dart';
import 'package:mytube/platform/platform_providers.dart';
import 'package:mytube/sources/direct_url/direct_url_adapter_provider.dart';
import 'package:mytube/sources/local/local_media_adapter_provider.dart';

/// Riverpod provider for [AvailabilityCheckService].
///
/// Depends on [localMediaAdapterProvider], [safBridgeProvider],
/// [mediaStoreBridgeProvider], and [videoRepositoryProvider].
///
/// The direct-URL adapter is passed through `adapters` so the per-location
/// retry actions (P7-07/AVAIL-002) can re-check URL rows; it stays OUT of the
/// bulk scan path — see the note on [directUrlAdapterProvider].
final availabilityCheckServiceProvider = Provider<AvailabilityCheckService>(
  (ref) => AvailabilityCheckService(
    localAdapter: ref.watch(localMediaAdapterProvider),
    safBridge: ref.watch(safBridgeProvider),
    mediaStoreBridge: ref.watch(mediaStoreBridgeProvider),
    repository: ref.watch(videoRepositoryProvider),
    adapters: [ref.watch(directUrlAdapterProvider)],
  ),
);
