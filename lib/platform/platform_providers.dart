import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/platform/http_remote_thumbnail_fetcher.dart';
import 'package:mytube/platform/media_store_bridge.dart';
import 'package:mytube/platform/media_store_bridge_impl.dart';
import 'package:mytube/platform/remote_thumbnail_fetcher.dart';
import 'package:mytube/platform/saf_bridge.dart';
import 'package:mytube/platform/saf_bridge_impl.dart';
import 'package:mytube/platform/thumbnail_bridge.dart';
import 'package:mytube/platform/thumbnail_bridge_impl.dart';

/// Riverpod provider for the MediaStore bridge (P3-01).
///
/// Override in tests with a mock implementation via
/// [ProviderContainer(overrides: [...])].
final mediaStoreBridgeProvider = Provider<MediaStoreBridge>(
  (ref) => MediaStoreBridgeImpl(),
);

/// Riverpod provider for the SAF bridge (P3-02).
///
/// Override in tests with a mock implementation via
/// [ProviderContainer(overrides: [...])].
final safBridgeProvider = Provider<SafBridge>((ref) => SafBridgeImpl());

/// Riverpod provider for the native thumbnail bridge (P7-01).
///
/// Override in tests with a fake implementation via
/// [ProviderContainer(overrides: [...])].
final thumbnailBridgeProvider = Provider<ThumbnailBridge>(
  (ref) => ThumbnailBridgeImpl(),
);

/// Riverpod provider for remote preview fetching (P7-02).
///
/// Override in tests with a fake implementation via
/// [ProviderContainer(overrides: [...])].
final remoteThumbnailFetcherProvider = Provider<RemoteThumbnailFetcher>(
  (ref) => HttpRemoteThumbnailFetcher(),
);
