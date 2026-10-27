import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/share_service.dart';
import 'package:mytube/platform/share_bridge.dart';

import '../../support/fake_video_repository.dart';

/// Records what the app asked the platform to share, so the two share paths
/// (clipboard link vs system sheet) are observable without a device.
class _FakeShareBridge implements ShareBridge {
  _FakeShareBridge({this.result = true});

  final bool result;
  final List<({String uri, String? mimeType})> calls = [];

  @override
  Future<bool> shareFile({required String uri, String? mimeType}) async {
    calls.add((uri: uri, mimeType: mimeType));
    return result;
  }
}

SourceLocation _location({
  required String videoItemId,
  required String sourceUri,
  ProviderType providerType = ProviderType.localMediaStore,
  bool isPrimary = true,
}) => SourceLocation(
  id: 'loc-$videoItemId',
  videoItemId: videoItemId,
  providerType: providerType,
  sourceUri: sourceUri,
  availability: AvailabilityState.available,
  isPrimary: isPrimary,
);

/// Share seam (plan M8): no new dependency, no raw URI ever reaching the UI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> clipboardWrites;

  setUp(() {
    clipboardWrites = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final data = call.arguments as Map<Object?, Object?>;
            clipboardWrites.add(data['text']! as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  ShareService serviceFor({
    Map<String, List<SourceLocation>>? locations,
    _FakeShareBridge? bridge,
    AppError? repositoryError,
  }) => ShareService(
    repository: FakeVideoRepository(
      locations: locations,
      sourceLocationsError: repositoryError,
    ),
    bridge: bridge ?? _FakeShareBridge(),
  );

  group('Direct-URL items', () {
    test('copies the durable link and does not open the sheet', () async {
      final bridge = _FakeShareBridge();
      final service = serviceFor(
        bridge: bridge,
        locations: {
          'a': [
            _location(
              videoItemId: 'a',
              sourceUri: 'https://example.com/clips/beach.mp4',
              providerType: ProviderType.directUrl,
            ),
          ],
        },
      );

      final outcome = await service.share(VideoItemId('a'));

      expect(outcome, ShareOutcome.linkCopied);
      expect(clipboardWrites, ['https://example.com/clips/beach.mp4']);
      // A link needs no platform grant, so the native bridge stays untouched.
      expect(bridge.calls, isEmpty);
    });

    test('trims surrounding whitespace from the stored URL', () async {
      final service = serviceFor(
        locations: {
          'a': [
            _location(
              videoItemId: 'a',
              sourceUri: '  https://example.com/x.mp4  ',
              providerType: ProviderType.directUrl,
            ),
          ],
        },
      );

      await service.share(VideoItemId('a'));

      expect(clipboardWrites, ['https://example.com/x.mp4']);
    });
  });

  group('Local and file-based items', () {
    test('a content:// location goes through the system sheet', () async {
      final bridge = _FakeShareBridge();
      final service = serviceFor(
        bridge: bridge,
        locations: {
          'a': [
            _location(
              videoItemId: 'a',
              sourceUri: 'content://media/external/video/media/42',
            ),
          ],
        },
      );

      final outcome = await service.share(VideoItemId('a'));

      expect(outcome, ShareOutcome.sheetOpened);
      expect(bridge.calls, hasLength(1));
      expect(
        bridge.calls.single.uri,
        'content://media/external/video/media/42',
      );
      expect(bridge.calls.single.mimeType, 'video/*');
      expect(clipboardWrites, isEmpty);
    });

    test('a file:// location is shareable too', () async {
      final bridge = _FakeShareBridge();
      final service = serviceFor(
        bridge: bridge,
        locations: {
          'a': [
            _location(
              videoItemId: 'a',
              sourceUri: 'file:///storage/emulated/0/Movies/clip.mp4',
              providerType: ProviderType.selectedFolder,
            ),
          ],
        },
      );

      expect(await service.share(VideoItemId('a')), ShareOutcome.sheetOpened);
      expect(bridge.calls, hasLength(1));
    });

    test('a host that cannot share degrades to unavailable', () async {
      // No plugin installed (widget tests, desktop): the bridge reports false
      // rather than throwing, and the caller shows a safe message.
      final service = serviceFor(
        bridge: _FakeShareBridge(result: false),
        locations: {
          'a': [
            _location(
              videoItemId: 'a',
              sourceUri: 'content://media/external/video/media/42',
            ),
          ],
        },
      );

      expect(await service.share(VideoItemId('a')), ShareOutcome.unavailable);
    });
  });

  group('Nothing to share', () {
    test('an item with no source location is unavailable', () async {
      final bridge = _FakeShareBridge();
      final service = serviceFor(bridge: bridge, locations: const {});

      expect(
        await service.share(VideoItemId('missing')),
        ShareOutcome.unavailable,
      );
      expect(bridge.calls, isEmpty);
      expect(clipboardWrites, isEmpty);
    });

    test('a blank source URI is unavailable', () async {
      final service = serviceFor(
        locations: {
          'a': [_location(videoItemId: 'a', sourceUri: '   ')],
        },
      );

      expect(await service.share(VideoItemId('a')), ShareOutcome.unavailable);
    });

    test(
      'a repository failure is reported as unavailable, not thrown',
      () async {
        final service = serviceFor(
          repositoryError: const NotFoundError(
            userMessage: 'That video is no longer in your library.',
            diagnosticMessage: 'fake: read failed',
          ),
        );

        expect(await service.share(VideoItemId('a')), ShareOutcome.unavailable);
      },
    );

    test('a provider-private scheme is never handed to the share sheet', () {
      // Only http(s) links and file-ish schemes leave the app; anything else
      // could leak a provider token, so it stays unshared.
      final bridge = _FakeShareBridge();
      final service = serviceFor(
        bridge: bridge,
        locations: {
          'a': [
            _location(
              videoItemId: 'a',
              sourceUri: 'r2token://bucket/private-key',
              providerType: ProviderType.cloudflareR2,
            ),
          ],
        },
      );

      expect(
        service.share(VideoItemId('a')),
        completion(ShareOutcome.unavailable),
      );
      expect(bridge.calls, isEmpty);
      expect(clipboardWrites, isEmpty);
    });
  });
}
