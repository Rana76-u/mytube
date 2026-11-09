import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/download_list_presentation.dart';

DownloadRecord _runningRecord() => DownloadRecord(
  id: 'job-1',
  videoItemId: 'item-1',
  providerType: ProviderType.webLink,
  sourceUri: 'https://youtu.be/example',
  fileName: 'video.mp4',
  sizeBytes: 1024,
  downloadedBytes: 512,
  status: DownloadStatus.running,
  acceptsRange: false,
  createdAt: 1,
  updatedAt: 1,
);

void main() {
  test('running status includes speed and estimated remaining time', () {
    expect(
      downloadStatusLine(
        _runningRecord(),
        speedBytesPerSecond: 1024,
        etaSeconds: 65,
      ),
      '50% • 512 B / 1.0 KB • 1.0 KB/s • ETA 01:05',
    );
  });

  test('running status omits unavailable telemetry', () {
    expect(downloadStatusLine(_runningRecord()), '50% • 512 B / 1.0 KB');
  });

  test('ETA is never shown outside active byte transfer', () {
    expect(
      downloadStatusLine(
        _runningRecord().copyWith(status: DownloadStatus.paused),
        speedBytesPerSecond: 1024,
        etaSeconds: 65,
      ),
      'Paused',
    );
  });
}
