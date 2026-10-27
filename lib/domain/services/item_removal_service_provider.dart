import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/services/item_removal_service.dart';
import 'package:mytube/domain/services/local_file_original_deleter.dart';
import 'package:mytube/platform/platform_providers.dart';

/// Every provider family whose originals the app can delete (ADR-017).
///
/// Deliberately a short, explicit list: a provider appears here only once it has
/// a deleter, so the removal flow can never claim to delete something it does
/// not own. Cloud adapters register their deleter here as they land; until then
/// their locations fall back to "remove from library".
final itemOriginalDeletersProvider = Provider<List<ItemOriginalDeleter>>(
  (ref) => [
    LocalFileOriginalDeleter(
      mediaStore: ref.watch(mediaStoreBridgeProvider),
      saf: ref.watch(safBridgeProvider),
    ),
  ],
);

/// Riverpod provider for [ItemRemovalService] (ADR-017).
///
/// Wired once so the card's `⋮`, the shared action sheet and any future surface
/// decide and execute removal identically, and so tests can override the
/// service or its bridges without a device.
final itemRemovalServiceProvider = Provider<ItemRemovalService>(
  (ref) => VideoItemRemovalService(
    repository: ref.watch(videoRepositoryProvider),
    deleters: ref.watch(itemOriginalDeletersProvider),
  ),
);
