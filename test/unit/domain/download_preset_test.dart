import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/data/database/tables/app_preferences_table.dart';
import 'package:mytube/domain/models/download_preset.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/features/downloads/download_preset_notifier.dart';

void main() {
  group('DownloadPreset defaults', () {
    test('match the §15.9 table', () {
      const p = DownloadPreset.defaults;
      expect(p.askEveryTime, isTrue);
      expect(p.kind, DownloadMediaKind.video);
      expect(p.maxHeight, 0);
      expect(p.bestQuality, isTrue);
      expect(p.container, ContainerPreference.any);
      expect(p.compatMode, isFalse);
      expect(p.audioFormat, AudioFormat.m4a);
      expect(p.audioBitrateKbps, 0);
      expect(
        p.destination,
        const DeviceFolderDestination(DeviceFolderKind.movies),
      );
      expect(p.maxConcurrent, 3);
      expect(p.fragments, 8);
      expect(p.useAria2c, isTrue);
      expect(p.wifiOnly, isFalse);
      expect(p.sponsorBlock, SponsorBlockMode.off);
      expect(p.playlistSleepSeconds, 2);
      expect(p.extraArgs, '');
    });
  });

  group('DownloadPreset.sanitize clamps and falls back', () {
    test('out-of-range maxConcurrent and fragments clamp', () {
      final p = DownloadPreset.sanitize(maxConcurrent: 9, fragments: 40);
      expect(p.maxConcurrent, 3);
      expect(p.fragments, 8);
    });

    test('in-range values are kept', () {
      final p = DownloadPreset.sanitize(maxConcurrent: 5, fragments: 16);
      expect(p.maxConcurrent, 5);
      expect(p.fragments, 16);
    });

    test('a height cap not on the ladder falls back to Best', () {
      final p = DownloadPreset.sanitize(maxHeight: 999);
      expect(p.maxHeight, 0);
      final ok = DownloadPreset.sanitize(maxHeight: 720);
      expect(ok.maxHeight, 720);
    });

    test('negative bitrate / rate limit clamp to 0', () {
      final p = DownloadPreset.sanitize(
        audioBitrateKbps: -5,
        rateLimitKbps: -1,
      );
      expect(p.audioBitrateKbps, 0);
      expect(p.rateLimitKbps, 0);
    });

    test('subtitle list is trimmed, empties dropped, capped at 20', () {
      final p = DownloadPreset.sanitize(
        subtitleLangs: [' en ', '', '  ', 'ja', ...List.filled(30, 'x')],
      );
      expect(p.subtitleLangs.first, 'en');
      expect(p.subtitleLangs.contains(''), isFalse);
      expect(p.subtitleLangs.length, 20);
    });
  });

  group('DownloadPreset copyWith', () {
    test('setting one field keeps the rest', () {
      const base = DownloadPreset.defaults;
      final changed = base.copyWith(maxHeight: 720);
      expect(changed.maxHeight, 720);
      expect(changed.maxConcurrent, base.maxConcurrent);
      expect(changed.audioFormat, base.audioFormat);
      expect(changed.destination, base.destination);
    });
  });

  group('Codec round trip', () {
    test('encode→decode is stable for a fully customised preset', () {
      final p = DownloadPreset.sanitize(
        askEveryTime: false,
        kind: DownloadMediaKind.audio,
        maxHeight: 720,
        container: ContainerPreference.mkv,
        compatMode: true,
        audioFormat: AudioFormat.opus,
        audioBitrateKbps: 128,
        destination: const OneDriveDestination('folder-1'),
        maxConcurrent: 2,
        fragments: 4,
        subtitleLangs: ['en', 'ja'],
        sponsorBlock: SponsorBlockMode.mark,
        lastClipboardHash: 'deadbeef',
      );
      final back = DownloadPresetCodec.decode(DownloadPresetCodec.encode(p));
      expect(back, equals(p));
    });

    test('every destination subtype survives the round trip', () {
      const destinations = <DownloadDestination>[
        AppStorageDestination(),
        DeviceFolderDestination(DeviceFolderKind.music),
        OneDriveDestination('id'),
      ];
      for (final d in destinations) {
        final encoded = DownloadPresetCodec.encode(
          DownloadPreset.defaults.copyWith(destination: d),
        );
        final decoded = DownloadPresetCodec.decode(encoded);
        expect(decoded.destination, equals(d));
      }
      final picked = PickedFolderDestination(
        Uri.parse('content://tree/primary%3ADVDC'),
      );
      final encoded = DownloadPresetCodec.encode(
        DownloadPreset.defaults.copyWith(destination: picked),
      );
      expect(DownloadPresetCodec.decode(encoded).destination, equals(picked));
    });

    test('a corrupt stored value decodes to the default, not a throw', () {
      final decoded = DownloadPresetCodec.decode({
        AppPreferenceKeys.downloadMaxConcurrent: 'not-a-number',
        AppPreferenceKeys.downloadKind: 'banana',
        AppPreferenceKeys.downloadContainer: 'mp4',
      });
      expect(decoded.maxConcurrent, 3); // fell back
      expect(decoded.kind, DownloadMediaKind.video); // unknown enum → default
      expect(decoded.container, ContainerPreference.mp4); // valid one kept
    });

    test('an absent map decodes to the full defaults', () {
      expect(DownloadPresetCodec.decode(const {}), DownloadPreset.defaults);
    });
  });

  group('Preset keys carry no secrets (DL1.4)', () {
    test('no download key names a url, cookie, token, proxy or password', () {
      const forbidden = [
        'url',
        'cookie',
        'token',
        'proxy',
        'password',
        'secret',
      ];
      for (final key in AppPreferenceKeys.downloadKeys) {
        final lower = key.toLowerCase();
        for (final word in forbidden) {
          expect(lower, isNot(contains(word)), reason: key);
        }
      }
    });

    test('toString never contains a scheme or credential', () {
      final p = DownloadPreset.defaults.copyWith(
        destination: const OneDriveDestination('secret-folder'),
      );
      expect(p.toString(), isNot(contains('http')));
      expect(p.toString(), isNot(contains('secret-folder')));
    });
  });
}
