import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/services/watch_progress_service.dart';

/// Riverpod provider for [WatchProgressService].
///
/// The only wiring point — the service itself imports no Flutter/Riverpod state
/// management beyond the injected [VideoRepository]. One instance lives for the
/// app's lifetime so its per-item throttle state is shared across the player
/// screen and any lifecycle observer that reports or flushes progress.
final watchProgressServiceProvider = Provider<WatchProgressService>(
  (ref) => WatchProgressService(repository: ref.watch(videoRepositoryProvider)),
);
