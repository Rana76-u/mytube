import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/services/scan_merge_service.dart';

/// Riverpod provider for [ScanMergeService].
///
/// Depends on [videoRepositoryProvider]; the service itself has no Flutter or
/// Riverpod imports — this file is the only wiring point.
final scanMergeServiceProvider = Provider<ScanMergeService>((ref) {
  return ScanMergeService(repository: ref.watch(videoRepositoryProvider));
});
