import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/services/availability_check_service.dart';
import 'package:mytube/platform/platform_providers.dart';
import 'package:mytube/sources/direct_url/direct_url_adapter_provider.dart';
import 'package:mytube/sources/google_drive/google_drive_providers.dart';
import 'package:mytube/sources/local/local_media_adapter_provider.dart';
import 'package:mytube/sources/onedrive/onedrive_providers.dart';

/// Riverpod provider for [AvailabilityCheckService].
///
/// Depends on [localMediaAdapterProvider], [safBridgeProvider],
/// [mediaStoreBridgeProvider], and [videoRepositoryProvider].
///
/// Direct-URL, OneDrive, and Google Drive adapters are passed through
/// `adapters` so per-location retry actions can re-check their provider rows.
/// Direct URLs stay out of the bulk scan path; cloud adapters also participate
/// in library refresh through the source registry.
final availabilityCheckServiceProvider = Provider<AvailabilityCheckService>(
  (ref) => AvailabilityCheckService(
    localAdapter: ref.watch(localMediaAdapterProvider),
    safBridge: ref.watch(safBridgeProvider),
    mediaStoreBridge: ref.watch(mediaStoreBridgeProvider),
    repository: ref.watch(videoRepositoryProvider),
    adapters: [
      ref.watch(directUrlAdapterProvider),
      ref.watch(oneDriveAdapterProvider),
      ref.watch(googleDriveAdapterProvider),
    ],
  ),
);
