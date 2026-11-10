import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/sources/google_drive/google_drive_providers.dart';
import 'package:mytube/sources/local/local_media_adapter_provider.dart';
import 'package:mytube/sources/onedrive/onedrive_providers.dart';
import 'package:mytube/sources/source_adapter.dart';

/// All registered source adapters, in priority order (ARCHITECTURE §6).
///
/// Higher-level services (e.g. the scan orchestrator) watch this provider to
/// iterate over sources without knowing their concrete types. An unconnected
/// cloud adapter reports an authentication error, which the refresh service
/// skips without marking its existing source locations missing.
final videoSourceAdaptersProvider = Provider<List<VideoSourceAdapter>>(
  (ref) => [
    ref.watch(localMediaAdapterProvider),
    ref.watch(oneDriveAdapterProvider),
    ref.watch(googleDriveAdapterProvider),
  ],
);
