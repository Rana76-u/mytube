import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/platform/audio_focus_bridge.dart';
import 'package:mytube/platform/audio_focus_bridge_impl.dart';
import 'package:mytube/platform/http_remote_thumbnail_fetcher.dart';
import 'package:mytube/platform/media_session_bridge.dart';
import 'package:mytube/platform/media_session_bridge_impl.dart';
import 'package:mytube/platform/media_store_bridge.dart';
import 'package:mytube/platform/media_store_bridge_impl.dart';
import 'package:mytube/platform/pip_bridge.dart';
import 'package:mytube/platform/pip_bridge_impl.dart';
import 'package:mytube/platform/remote_thumbnail_fetcher.dart';
import 'package:mytube/platform/saf_bridge.dart';
import 'package:mytube/platform/saf_bridge_impl.dart';
import 'package:mytube/platform/storage_paths.dart';
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

/// Riverpod provider for the app's storage roots (P8-01).
///
/// Cache and download directories are resolved through `path_provider` and
/// verified to be non-overlapping before cache code may use them. Override
/// with a fake to point tests at a temporary directory.
final storagePathsProvider = Provider<StoragePaths>(
  (ref) => PathProviderStoragePaths(),
);

/// Riverpod provider for the Android audio-focus bridge (P13-01).
///
/// The [AudioFocusBridgeImpl] degrades to a safe no-op when the native plugin
/// is absent, so non-Android runs and widget tests never crash. Override with a
/// fake bridge to drive interruption scenarios in tests.
final audioFocusBridgeProvider = Provider<AudioFocusBridge>(
  (ref) => AudioFocusBridgeImpl(),
);

/// Riverpod provider for the Android media-session / notification bridge
/// (P13-03).
///
/// The [MediaSessionBridgeImpl] degrades to a safe no-op when the native plugin
/// is absent. Override with a fake bridge to drive transport commands in tests.
final mediaSessionBridgeProvider = Provider<MediaSessionBridge>(
  (ref) => MediaSessionBridgeImpl(),
);

/// Riverpod provider for the Android Picture-in-Picture bridge (P13-04).
///
/// The [PipBridgeImpl] degrades to a safe no-op and reports `isSupported` false
/// where the native plugin is absent or the device lacks PiP, so unsupported
/// hosts never show a dead control or crash (NFR-006, PLAY-013). Override with
/// a fake bridge to drive enter / mode changes in tests.
final pipBridgeProvider = Provider<PipBridge>((ref) => PipBridgeImpl());
