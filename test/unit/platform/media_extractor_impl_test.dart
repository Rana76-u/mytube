import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/platform/extractor/extractor_error_map.dart';
import 'package:mytube/platform/extractor/media_extractor.dart';
import 'package:mytube/platform/extractor/media_extractor_impl.dart';
import 'package:mytube/sources/source_adapter.dart' show CancellationToken;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'com.example.mytube/extractor';
  const channel = MethodChannel(channelName);

  /// Records every method call the impl makes so tests can assert argument
  /// shapes (§15.11: structured fields, URL only as the `url` value).
  late List<MethodCall> calls;
  late Map<String, Future<Object?> Function(MethodCall)> handlers;

  setUp(() {
    calls = [];
    handlers = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final h = handlers[call.method];
          if (h == null) return null;
          return h(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  MediaExtractorImpl build({
    Stream<dynamic> Function(Object? args)? eventSource,
    CancelWatchFactory? cancelWatcher,
  }) => MediaExtractorImpl(
    method: channel,
    eventSource: eventSource,
    cancelWatcher: cancelWatcher ?? _neverCancels,
  );

  MethodCall? call(String method) {
    for (final c in calls) {
      if (c.method == method) return c;
    }
    return null;
  }

  group('status', () {
    test('maps the native state and version', () async {
      handlers['status'] = (_) async => {
        'state': 'ready',
        'version': '2026.10.26',
      };
      final r = await build().status();
      final s = (r as Ok<ExtractorStatus>).value;
      expect(s.isReady, isTrue);
      expect(s.version, '2026.10.26');
    });

    test(
      'reports unavailable when the plugin is absent (no handler)',
      () async {
        // No handler registered for the channel -> MissingPluginException.
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        final r = await build().status();
        final s = (r as Ok<ExtractorStatus>).value;
        expect(s.isUnavailable, isTrue);
      },
    );
  });

  group('probe', () {
    test('sends a structured request and decodes the json payload', () async {
      const payload =
          '{"webpage_url":"https://e/watch?v=1","title":"Hi",'
          '"duration":61.5,"formats":['
          '{"format_id":"137","height":1080,"vcodec":"avc1.64001F",'
          '"acodec":"none","ext":"mp4","tbr":4500,"filesize":900},'
          '{"format_id":"140","vcodec":"none","acodec":"mp4a.40.2",'
          '"ext":"m4a","filesize_approx":800}]}';
      handlers['probe'] = (_) async => payload;

      final r = await build().probe(
        Uri.parse('https://e/watch?v=1'),
        cancellationToken: CancellationToken(),
      );
      final info = (r as Ok<WebMediaInfo>).value;

      final args = call('probe')!.arguments as Map;
      expect(args['url'], 'https://e/watch?v=1');
      expect(args['processId'], isA<int>());

      expect(info.title, 'Hi');
      expect(info.kind, WebMediaKind.video);
      expect(info.duration, const Duration(seconds: 62));
      final v = info.formats.firstWhere((f) => f.formatId == '137');
      expect(v.isVideoOnly, isTrue);
      expect(v.bitrateKbps, 4500);
      expect(v.sizeBytes, 900);
      final a = info.formats.firstWhere((f) => f.formatId == '140');
      expect(a.isAudioOnly, isTrue);
      expect(a.isAac, isTrue);
    });

    test('classifies live and playlist payloads', () async {
      handlers['probe'] = (c) async {
        final u = (c.arguments as Map)['url'] as String;
        if (u.contains('live')) return '{"is_live":true,"formats":[]}';
        return '{"_type":"playlist","entries":[],"formats":[]}';
      };
      final live = await build().probe(
        Uri.parse('https://e/live/1'),
        cancellationToken: CancellationToken(),
      );
      expect((live as Ok<WebMediaInfo>).value.kind, WebMediaKind.live);
      final pl = await build().probe(
        Uri.parse('https://e/playlist/1'),
        cancellationToken: CancellationToken(),
      );
      expect((pl as Ok<WebMediaInfo>).value.kind, WebMediaKind.playlist);
    });

    test(
      'maps a DRM failure and redacts the signed URL from diagnostics',
      () async {
        handlers['probe'] = (_) async => throw PlatformException(
          code: ExtractorErrorMap.drmProtected,
          message: 'raw https://signed.example/x?token=SECRET',
        );
        final r = await build().probe(
          Uri.parse('https://e/x'),
          cancellationToken: CancellationToken(),
        );
        final err = (r as Err<WebMediaInfo>).error;
        expect(err, isA<DrmProtectedError>());
        expect(err.diagnosticMessage, isNot(contains('signed.example')));
        expect(err.diagnosticMessage, isNot(contains('SECRET')));
      },
    );

    test('missing plugin yields a typed unavailable error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      final r = await build().probe(
        Uri.parse('https://e/x'),
        cancellationToken: CancellationToken(),
      );
      expect((r as Err<WebMediaInfo>).error, isA<ExtractorUnavailableError>());
    });

    test('a token cancelled up front never calls the channel', () async {
      final token = CancellationToken()..cancel();
      final r = await build().probe(
        Uri.parse('https://e/x'),
        cancellationToken: token,
      );
      expect((r as Err<WebMediaInfo>).error, isA<DownloadCancelledError>());
      expect(call('probe'), isNull);
    });

    test('cancellation mid-flight tells native to stop', () async {
      final started = Completer<Object?>();
      handlers['probe'] = (_) => started.future; // never completes in-test
      final probe = build(
        cancelWatcher: _immediateCancel,
      ).probe(Uri.parse('https://e/x'), cancellationToken: CancellationToken());
      final r = await probe;
      expect((r as Err<WebMediaInfo>).error, isA<DownloadCancelledError>());
      expect(call('cancel'), isNotNull);
      final args = call('cancel')!.arguments as Map;
      expect(args['processId'], isA<int>());
    });
  });

  group('resolveStream', () {
    test('returns an in-memory playable with headers', () async {
      handlers['resolveStream'] = (_) async => {
        'url': 'https://cdn/x.m3u8?sig=SECRET',
        'headers': {'referer': 'https://e', 'cookie': 'a=b'},
        'mimeType': 'application/x-mpegurl',
        'canSeek': false,
        'isLive': true,
        'formatId': 'hls',
      };
      final r = await build().resolveStream(
        Uri.parse('https://e/x'),
        preference: const StreamPreference(
          mode: StreamMode.hls,
          maxHeight: 720,
        ),
        cancellationToken: CancellationToken(),
      );
      final s = (r as Ok<ExtractorStream>).value;
      expect(s.isLive, isTrue);
      expect(s.headers['cookie'], 'a=b');
      expect(s.toString(), isNot(contains('SECRET')));
      final args = call('resolveStream')!.arguments as Map;
      expect(args['mode'], 'hls');
      expect(args['maxHeight'], 720);
    });

    test('empty url is an unsupported-format error', () async {
      handlers['resolveStream'] = (_) async => {'url': ''};
      final r = await build().resolveStream(
        Uri.parse('https://e/x'),
        preference: const StreamPreference(),
        cancellationToken: CancellationToken(),
      );
      expect((r as Err<ExtractorStream>).error, isA<UnsupportedFormatError>());
    });
  });

  group('run', () {
    ExtractorJob job() => ExtractorJob(
      jobId: 'j1',
      pageUrl: Uri.parse('https://e/x'),
      stagingDirectory: '/stage/j1',
      outputFileName: 'clip.mp4',
      videoFormatId: '137',
      audioFormatId: '140',
      merge: true,
      container: OutputContainer.mp4,
    );

    test('sends structured args then maps progress and done events', () async {
      handlers['run'] = (_) async => null;
      final src = StreamController<dynamic>();
      addTearDown(src.close);
      final events = build(eventSource: (_) => src.stream).run(job()).toList();

      src.add({
        'jobId': 'j1',
        'type': 'progress',
        'phase': 'downloading',
        'done': 500,
        'total': 1000,
        'speed': 120,
        'eta': 4,
      });
      src.add({'jobId': 'other', 'type': 'done', 'path': '/x'}); // filtered
      src.add({
        'jobId': 'j1',
        'type': 'done',
        'path': '/stage/j1/clip.mp4',
        'size': 1000,
      });

      final got = await events;
      expect(got.length, 2);
      expect(got[0], isA<ExtractorProgress>());
      expect(got[1], isA<ExtractorDone>());
      expect((got[1] as ExtractorDone).stagedPath, '/stage/j1/clip.mp4');

      final args = call('run')!.arguments as Map;
      expect(args['jobId'], 'j1');
      expect(args['url'], 'https://e/x');
      expect(args['merge'], true);
      expect(args['container'], 'mp4');
      expect(args['videoFormatId'], '137');
    });

    test('a failed event carries a typed mapped error', () async {
      handlers['run'] = (_) async => null;
      final src = StreamController<dynamic>();
      addTearDown(src.close);
      final events = build(eventSource: (_) => src.stream).run(job()).toList();
      src.add({
        'jobId': 'j1',
        'type': 'failed',
        'code': ExtractorErrorMap.loginRequired,
        'detail': 'needs sign in',
      });
      final got = await events;
      expect(got.single, isA<ExtractorFailed>());
      expect((got.single as ExtractorFailed).error, isA<LoginRequiredError>());
    });

    test('a start failure is a terminal typed event', () async {
      handlers['run'] = (_) async => throw PlatformException(
        code: ExtractorErrorMap.unavailable,
        message: 'engine down',
      );
      final got = await build().run(job()).toList();
      expect(got.single, isA<ExtractorFailed>());
      expect(
        (got.single as ExtractorFailed).error,
        isA<ExtractorUnavailableError>(),
      );
    });
  });

  group('updates', () {
    test('checkForUpdate reports an available engine version', () async {
      handlers['checkForUpdate'] = (_) async => {
        'status': 'available',
        'currentVersion': '2025.11.12',
        'latestVersion': '2026.10.26',
      };
      final r = await build().checkForUpdate();
      final u = (r as Ok<ExtractorUpdate>).value;
      expect(u.hasUpdate, isTrue);
      expect(u.latestVersion, '2026.10.26');
    });

    test(
      'a failed update keeps the previous working version (ADR-028)',
      () async {
        handlers['update'] = (_) async => {
          'status': 'failed',
          'currentVersion': '2025.11.12',
          'code': ExtractorErrorMap.network,
          'detail': 'offline',
        };
        final r = await build().update();
        final u = (r as Ok<ExtractorUpdate>).value;
        expect(u.status, ExtractorUpdateStatus.failed);
        expect(u.currentVersion, '2025.11.12');
        expect(u.failure, isA<NetworkUnavailableError>());
      },
    );
  });

  test('cancel forwards the job id', () async {
    handlers['cancel'] = (_) async => null;
    await build().cancel('job-7');
    expect((call('cancel')!.arguments as Map)['jobId'], 'job-7');
  });
}

/// A watch that never fires — the guarded call runs to completion.
CancelWatch _neverCancels(CancellationToken _) =>
    CancelWatch(Completer<void>(), null);

/// A watch already completed — models a cancel arriving mid-flight.
CancelWatch _immediateCancel(CancellationToken _) {
  final c = Completer<void>()..complete();
  return CancelWatch(c, null);
}
