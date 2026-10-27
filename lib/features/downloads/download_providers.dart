import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show ChangeNotifierProvider;

import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver.dart';
import 'package:mytube/features/downloads/download_controller.dart';
import 'package:mytube/features/downloads/download_manager.dart';
import 'package:mytube/features/downloads/download_transport.dart';
import 'package:mytube/features/downloads/network_probe.dart';
import 'package:mytube/features/downloads/offline_download_resolver.dart';
import 'package:mytube/platform/platform_providers.dart';

/// Riverpod provider for the [DownloadTransport] (P12-02).
///
/// A single reusable `dart:io` HTTP client backs every transfer; it is closed
/// when the provider is disposed. Override in tests with a fake transport that
/// yields a scripted byte stream.
final downloadTransportProvider = Provider<DownloadTransport>((ref) {
  final transport = HttpDownloadTransport();
  ref.onDispose(transport.dispose);
  return transport;
});

/// Resolves the dedicated downloads root, or an [Err] when the layout is shared
/// with the cache or otherwise unusable (CACHE-006).
///
/// Shared by the transfer engine and offline playback so both agree on exactly
/// where app-owned download files live, and both refuse to touch the cache.
final downloadsRootResolverProvider =
    Provider<Future<Result<String>> Function()>((ref) {
      return () async {
        final roots = await ref.read(storagePathsProvider).resolve();
        return switch (roots) {
          Ok(:final value) when value.isSeparated => Result.ok(
            value.downloadsRoot,
          ),
          Ok(:final value) => Result.err(
            UnexpectedError(
              userMessage: 'Offline storage is unavailable on this device.',
              diagnosticMessage:
                  'download roots overlap, downloads disabled: '
                  '$value',
            ),
          ),
          Err(:final error) => Result.err(error),
        };
      };
    });

/// Riverpod provider for the [DownloadManager] (P12-02, P12-04).
///
/// The downloads root is resolved through [downloadsRootResolverProvider] on
/// every access and verified separated from the cache root before use — so a
/// shared or unusable layout refuses downloads rather than letting cache
/// cleanup reach them (CACHE-006). The low-storage probe is left null on hosts
/// without an OS free-space API: refusal then only triggers when a size is
/// declared and a probe is supplied (see the ADR for the on-device follow-up).
final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final manager = HttpDownloadManager(
    repository: ref.watch(downloadRepositoryProvider),
    transport: ref.watch(downloadTransportProvider),
    resolveRoot: ref.watch(downloadsRootResolverProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// Riverpod provider for the [OfflineDownloadResolver] (P12-03 / VP6.3).
///
/// Reads completed download records and the shared downloads root so the
/// playback resolver can prefer a local copy over re-streaming. Tests override
/// it with a fake that returns a scripted source (or `null`).
final offlineDownloadResolverProvider = Provider<OfflineDownloadResolver>((
  ref,
) {
  return StorageOfflineDownloadResolver(
    repository: ref.watch(downloadRepositoryProvider),
    resolveRoot: ref.watch(downloadsRootResolverProvider),
  );
});

/// Reachability probe the download pill consults to disable a fresh start while
/// offline (VP6.4). Override in tests to drive both branches deterministically.
final onlineProbeProvider = Provider<Future<bool> Function()>(
  (ref) => ioOnlineProbe,
);

/// Per-item [DownloadController] backing the player's download pill (P12-05 /
/// VP6.4). Auto-disposed with the pill so its manager subscription and
/// notifier listeners do not outlive the page.
final downloadControllerProvider = ChangeNotifierProvider.autoDispose
    .family<DownloadController, VideoItemId>((ref, id) {
      final controller = DownloadController(
        videoItemId: id,
        manager: ref.watch(downloadManagerProvider),
        downloadRepository: ref.watch(downloadRepositoryProvider),
        videoRepository: ref.watch(videoRepositoryProvider),
        onlineProbe: ref.watch(onlineProbeProvider),
      );
      // Fire-and-forget: the pill renders `hidden` until the source resolves.
      unawaited(controller.bootstrap());
      return controller;
    });
