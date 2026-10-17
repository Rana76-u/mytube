import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/sources/local/local_media_adapter_provider.dart';
import 'package:mytube/sources/source_adapter.dart';

/// All registered source adapters, in priority order (ARCHITECTURE §6).
///
/// Higher-level services (e.g. the scan orchestrator) watch this provider to
/// iterate over every available source without knowing their concrete types.
final videoSourceAdaptersProvider = Provider<List<VideoSourceAdapter>>(
  (ref) => [ref.watch(localMediaAdapterProvider)],
);
