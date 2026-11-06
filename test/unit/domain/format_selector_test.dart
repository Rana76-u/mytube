import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/download_preset.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/services/format_selector.dart';

WebFormat v(
  String id, {
  int? height,
  double? fps,
  String codec = 'avc1.64001F',
  String ext = 'mp4',
  bool hasAudio = false,
  int? bitrate,
  int? size,
  bool drm = false,
  bool muxed = false,
  bool hdr = false,
}) => WebFormat(
  formatId: id,
  height: height,
  fps: fps,
  hasVideo: true,
  hasAudio: hasAudio || muxed,
  videoCodec: codec,
  ext: ext,
  bitrateKbps: bitrate,
  sizeBytes: size,
  isDrm: drm,
  isMuxed: muxed,
  isHdr: hdr,
);

WebFormat a(
  String id, {
  String codec = 'mp4a.40.2',
  String ext = 'm4a',
  int? bitrate,
  int? size,
}) => WebFormat(
  formatId: id,
  hasVideo: false,
  hasAudio: true,
  audioCodec: codec,
  ext: ext,
  bitrateKbps: bitrate,
  sizeBytes: size,
);

WebMediaInfo info(
  List<WebFormat> formats, {
  WebMediaKind kind = WebMediaKind.video,
}) => WebMediaInfo(
  canonicalUrl: 'https://x.test/p',
  formats: formats,
  kind: kind,
);

const selector = FormatSelector();

DownloadPreset preset({
  DownloadMediaKind kind = DownloadMediaKind.video,
  int maxHeight = 0,
  ContainerPreference container = ContainerPreference.any,
  bool compatMode = false,
  AudioFormat audioFormat = AudioFormat.m4a,
  int audioBitrateKbps = 0,
}) => DownloadPreset(
  kind: kind,
  maxHeight: maxHeight,
  container: container,
  compatMode: compatMode,
  audioFormat: audioFormat,
  audioBitrateKbps: audioBitrateKbps,
);

void main() {
  group('video selection — heights', () {
    test('Best picks the greatest height', () {
      final sel = selector.select(
        info([v('1', height: 720), v('2', height: 1080), v('3', height: 2160)]),
        preset(),
      );
      expect(sel.video!.height, 2160);
    });

    test('cap 1080 with 2160 available picks 1080', () {
      final sel = selector.select(
        info([v('1', height: 720), v('2', height: 1080), v('3', height: 2160)]),
        preset(maxHeight: 1080),
      );
      expect(sel.video!.height, 1080);
      expect(sel.notes, isNot(contains(FormatSelectionNote.qualityLowered)));
    });

    test(
      'cap below the lowest available picks the lowest and flags lowered',
      () {
        final sel = selector.select(
          info([v('1', height: 720), v('2', height: 1080)]),
          preset(maxHeight: 360),
        );
        expect(sel.video!.height, 720);
        expect(sel.hasNote(FormatSelectionNote.qualityLowered), isTrue);
      },
    );

    test('cap picks highest at-or-below when several qualify', () {
      final sel = selector.select(
        info([
          v('a', height: 480),
          v('b', height: 720),
          v('c', height: 1080),
          v('d', height: 1440),
        ]),
        preset(maxHeight: 1080),
      );
      expect(sel.video!.height, 1080);
    });

    test('unknown-height formats do not become 0', () {
      final sel = selector.select(
        info([v('u'), v('h', height: 360)]),
        preset(),
      );
      // A real height beats an unknown one under Best.
      expect(sel.video!.height, 360);
    });
  });

  group('video selection — codec / fps / bitrate', () {
    test('60fps beats 30fps at the same height', () {
      final sel = selector.select(
        info([v('1', height: 1080, fps: 30), v('2', height: 1080, fps: 60)]),
        preset(),
      );
      expect(sel.video!.formatId, '2');
    });

    test('higher bitrate breaks an fps tie', () {
      final sel = selector.select(
        info([
          v('1', height: 1080, fps: 60, bitrate: 4000),
          v('2', height: 1080, fps: 60, bitrate: 6000),
        ]),
        preset(),
      );
      expect(sel.video!.formatId, '2');
    });

    test('compatMode prefers H.264 over a higher-bitrate VP9', () {
      final sel = selector.select(
        info([
          v('vp9', height: 1080, codec: 'vp09.00', ext: 'webm', bitrate: 9000),
          v('h264', height: 1080, codec: 'avc1.64001F', bitrate: 5000),
        ]),
        preset(compatMode: true),
      );
      expect(sel.video!.formatId, 'h264');
    });

    test('compat off lets VP9 win and adds codecMayNotPlay', () {
      final sel = selector.select(
        info([
          v('vp9', height: 1080, codec: 'vp09.00', ext: 'webm', bitrate: 9000),
          v('h264', height: 1080, codec: 'avc1.64001F', bitrate: 5000),
        ]),
        preset(),
      );
      expect(sel.video!.formatId, 'vp9');
      expect(sel.hasNote(FormatSelectionNote.codecMayNotPlay), isTrue);
    });

    test('AV1 adds codecMayNotPlay', () {
      final sel = selector.select(
        info([v('av1', height: 720, codec: 'av01.0.14M', ext: 'webm')]),
        preset(),
      );
      expect(sel.hasNote(FormatSelectionNote.codecMayNotPlay), isTrue);
    });

    test('HDR adds codecMayNotPlay', () {
      final sel = selector.select(
        info([v('hdr', height: 1080, codec: 'avc1', hdr: true)]),
        preset(),
      );
      expect(sel.hasNote(FormatSelectionNote.codecMayNotPlay), isTrue);
    });
  });

  group('video selection — pairing and containers', () {
    test('video-only pick pairs audio and marks needsMerge', () {
      final sel = selector.select(
        info([v('v', height: 720, codec: 'avc1'), a('aud', codec: 'mp4a')]),
        preset(),
      );
      expect(sel.needsMerge, isTrue);
      expect(sel.hasNote(FormatSelectionNote.needsMerge), isTrue);
      expect(sel.audio!.formatId, 'aud');
    });

    test('H.264 + AAC pair yields MP4 container', () {
      final sel = selector.select(
        info([v('v', height: 720, codec: 'avc1'), a('aud', codec: 'mp4a')]),
        preset(),
      );
      expect(sel.container, OutputContainer.mp4);
    });

    test('VP9 video pairs Opus and yields MKV', () {
      final sel = selector.select(
        info([
          v('v', height: 720, codec: 'vp09.00', ext: 'webm'),
          a('aud', codec: 'opus', ext: 'webm'),
        ]),
        preset(),
      );
      expect(sel.container, OutputContainer.mkv);
      expect(sel.audio!.isOpus, isTrue);
    });

    test('muxed-only source needs no merge', () {
      final sel = selector.select(
        info([v('m', height: 480, muxed: true, ext: 'mp4')]),
        preset(),
      );
      expect(sel.needsMerge, isFalse);
      expect(sel.audio, isNull);
      expect(sel.container, OutputContainer.mp4);
    });

    test('size estimate sums video and audio', () {
      final sel = selector.select(
        info([v('v', height: 720, size: 1000), a('aud', size: 500)]),
        preset(),
      );
      expect(sel.estimatedBytes, 1500);
    });

    test('unknown size gives null, not 0', () {
      final sel = selector.select(
        info([v('v', height: 720, size: null), a('aud', size: 500)]),
        preset(),
      );
      expect(sel.estimatedBytes, isNull);
    });

    test('unknown audio size gives null too', () {
      final sel = selector.select(
        info([v('v', height: 720, size: 1000), a('aud', size: null)]),
        preset(),
      );
      expect(sel.estimatedBytes, isNull);
    });
  });

  group('video selection — MP4-only', () {
    test('MP4-only drops to the best H.264 height', () {
      final sel = selector.select(
        info([
          v('vp9', height: 1080, codec: 'vp09.00', ext: 'webm'),
          v('h264a', height: 720, codec: 'avc1'),
          v('h264b', height: 480, codec: 'avc1'),
        ]),
        preset(container: ContainerPreference.mp4),
      );
      expect(sel.video!.isH264, isTrue);
      expect(sel.video!.height, 720);
      expect(sel.hasNote(FormatSelectionNote.mp4Unavailable), isFalse);
    });

    test('MP4-only with no H.264 falls back and flags mp4Unavailable', () {
      final sel = selector.select(
        info([v('vp9', height: 1080, codec: 'vp09.00', ext: 'webm')]),
        preset(container: ContainerPreference.mp4),
      );
      expect(sel.hasNote(FormatSelectionNote.mp4Unavailable), isTrue);
      expect(sel.container, OutputContainer.mkv);
    });
  });

  group('selection — DRM and routing', () {
    test('DRM formats are ignored', () {
      final sel = selector.select(
        info([v('drm', height: 2160, drm: true), v('ok', height: 1080)]),
        preset(),
      );
      expect(sel.video!.formatId, 'ok');
    });

    test('all-DRM fails with DrmProtected', () {
      expect(
        () => selector.select(
          info([
            v('d1', height: 1080, drm: true),
            v('d2', height: 720, drm: true),
          ]),
          preset(),
        ),
        throwsA(isA<DrmProtectedError>()),
      );
    });

    test('empty formats fails with UnsupportedFormat', () {
      expect(
        () => selector.select(info(const []), preset()),
        throwsA(isA<UnsupportedFormatError>()),
      );
    });

    test('no video stream for a video request fails', () {
      expect(
        () => selector.select(info([a('only')]), preset()),
        throwsA(isA<UnsupportedFormatError>()),
      );
    });

    test('live info is routed out before selection', () {
      expect(
        () => selector.select(
          info([v('x', height: 720)], kind: WebMediaKind.live),
          preset(),
        ),
        throwsA(isA<LiveStreamUnsupportedError>()),
      );
    });

    test('playlist info is routed out before selection', () {
      expect(
        () => selector.select(
          info([v('x', height: 720)], kind: WebMediaKind.playlist),
          preset(),
        ),
        throwsA(isA<PlaylistUnsupportedError>()),
      );
    });
  });

  group('audio selection', () {
    test('M4A copies an AAC source (mp4 container)', () {
      final sel = selector.select(
        info([
          a('m4a', codec: 'mp4a', ext: 'm4a'),
          a('op', codec: 'opus', ext: 'webm'),
        ]),
        preset(kind: DownloadMediaKind.audio, audioFormat: AudioFormat.m4a),
      );
      expect(sel.video!.formatId, 'm4a');
      expect(sel.container, OutputContainer.mp4);
      expect(sel.needsMerge, isFalse);
    });

    test('Opus copies an Opus source (mkv container)', () {
      final sel = selector.select(
        info([a('m4a', codec: 'mp4a'), a('op', codec: 'opus', ext: 'webm')]),
        preset(kind: DownloadMediaKind.audio, audioFormat: AudioFormat.opus),
      );
      expect(sel.video!.formatId, 'op');
      expect(sel.container, OutputContainer.mkv);
    });

    test('MP3 re-encodes from the best source (other container)', () {
      final sel = selector.select(
        info([
          a('lo', codec: 'mp4a', bitrate: 96),
          a('hi', codec: 'mp4a', bitrate: 128),
        ]),
        preset(
          kind: DownloadMediaKind.audio,
          audioFormat: AudioFormat.mp3,
          audioBitrateKbps: 32,
        ),
      );
      // Re-encode picks the highest-bitrate source; the target bitrate is a
      // runner concern applied only because this is a re-encode.
      expect(sel.video!.formatId, 'hi');
      expect(sel.container, OutputContainer.other);
    });

    test(
      'copy ignores the requested bitrate (bitrate applies to re-encode)',
      () {
        final sel = selector.select(
          info([a('m4a', codec: 'mp4a', bitrate: 128)]),
          preset(
            kind: DownloadMediaKind.audio,
            audioFormat: AudioFormat.m4a,
            audioBitrateKbps: 32,
          ),
        );
        expect(sel.video!.formatId, 'm4a');
        expect(sel.container, OutputContainer.mp4);
      },
    );

    test('audio request with only muxed streams still resolves', () {
      final sel = selector.select(
        info([v('mux', height: 480, muxed: true, ext: 'mp4')]),
        preset(kind: DownloadMediaKind.audio, audioFormat: AudioFormat.m4a),
      );
      expect(sel.video!.hasAudio, isTrue);
    });

    test('audio-only with no audio at all fails', () {
      expect(
        () => selector.select(
          info([WebFormat(formatId: 'vonly', hasVideo: true, hasAudio: false)]),
          preset(kind: DownloadMediaKind.audio),
        ),
        throwsA(isA<UnsupportedFormatError>()),
      );
    });
  });
}
