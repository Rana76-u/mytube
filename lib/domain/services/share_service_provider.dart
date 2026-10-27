import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/services/share_service.dart';
import 'package:mytube/platform/platform_providers.dart';

/// Riverpod provider for [ShareService] (plan M8).
///
/// Wired here rather than inside a widget so every share affordance — the card
/// menu, the Reels action column and the player toolbar — goes through one
/// service, and tests can override [shareBridgeProvider] with a fake.
final shareServiceProvider = Provider<ShareService>(
  (ref) => ShareService(
    repository: ref.watch(videoRepositoryProvider),
    bridge: ref.watch(shareBridgeProvider),
  ),
);
