import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/services/direct_url_service.dart';
import 'package:mytube/sources/direct_url/direct_url_adapter_provider.dart';

/// Riverpod provider for [DirectUrlService].
///
/// Depends on [videoRepositoryProvider] and the direct-URL prober; the
/// service itself has no Flutter or Riverpod imports — this file is the only
/// wiring point.
final directUrlServiceProvider = Provider<DirectUrlService>((ref) {
  return DirectUrlService(
    repository: ref.watch(videoRepositoryProvider),
    prober: ref.watch(urlMetadataProberProvider),
  );
});
