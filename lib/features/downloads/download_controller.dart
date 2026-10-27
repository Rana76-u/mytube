import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/downloads/download_manager.dart';

/// Which provider types the app may copy for offline playback (VP6.4 gate).
///
/// A local MediaStore/SAF item already *is* a file on the device — downloading
/// it would duplicate or lie — so only remote providers are downloadable. The
/// direct-URL provider is the sole one wired today; the cloud providers are
/// listed so their adapters light the pill up the moment they land (P12-01).
/// A source the provider *prohibits* is handled at offer time by the caller,
/// not here — this only answers "could this provider type ever be copied".
bool providerIsDownloadable(ProviderType? provider) => switch (provider) {
  ProviderType.directUrl ||
  ProviderType.oneDrive ||
  ProviderType.googleDrive ||
  ProviderType.cloudflareR2 => true,
  ProviderType.localMediaStore || ProviderType.selectedFolder || null => false,
};

/// Presentation state for the player's download pill (VP6.4).
enum DownloadPillStatus {
  /// No downloadable source (local item, or an item with no source) — the pill
  /// is not rendered at all.
  hidden,

  /// Downloadable, nothing downloaded yet. Tap to start.
  idle,

  /// A transfer is in flight; the label carries progress, the tap cancels.
  running,

  /// A completed copy is on disk; tap removes it (never the original).
  completed,

  /// The last attempt failed; tap retries.
  failed,
}

/// Bridges the [DownloadManager] to the player pill for one library item
/// (P12-05 / VP6.4).
///
/// It owns no network or file logic — it reads the item's durable source,
/// reflects the current download record, tracks live progress off the manager's
/// event stream, and exposes start / cancel / retry / remove. Keeping this in a
/// [ChangeNotifier] (rather than the widget) holds every persistence call and
/// stream subscription out of the UI, per the layering rules.
class DownloadController extends ChangeNotifier {
  DownloadController({
    required this.videoItemId,
    required this._manager,
    required this._downloadRepository,
    required this._videoRepository,
    required this._onlineProbe,
  });

  final VideoItemId videoItemId;
  final DownloadManager _manager;
  final DownloadRepository _downloadRepository;
  final VideoRepository _videoRepository;
  final Future<bool> Function() _onlineProbe;

  DownloadPillStatus _status = DownloadPillStatus.hidden;
  bool _online = true;
  String? _downloadId;
  int? _downloadedBytes;
  int? _sizeBytes;
  AppError? _lastError;

  // Durable source the item downloads from, resolved during [bootstrap].
  ProviderType? _providerType;
  String? _sourceUri;
  int? _sourceSizeBytes;
  bool _downloadable = false;

  StreamSubscription<DownloadEvent>? _eventsSub;
  bool _bootstrapped = false;

  DownloadPillStatus get status => _status;

  /// Whether the pill should accept a tap. A download already in flight or on
  /// disk is independent of connectivity; only a *fresh* start needs a network,
  /// so an offline device disables the idle pill (VP6.4 "disabled offline").
  bool get enabled => _online || _status != DownloadPillStatus.idle;

  /// Progress in 0..1 while [status] is [DownloadPillStatus.running], or null
  /// when the total size is unknown (an indeterminate spinner).
  double? get progress {
    if (_status != DownloadPillStatus.running) return null;
    final total = _sizeBytes;
    if (total == null || total <= 0) return null;
    final done = _downloadedBytes ?? 0;
    return (done / total).clamp(0.0, 1.0);
  }

  AppError? get lastError => _lastError;

  /// Resolves the item's source, loads any existing download and starts
  /// listening for progress. Safe to call once; later event-driven updates
  /// flow through the manager stream.
  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    _status = await _resolveSourceAndRecord();
    // Reflect current connectivity before the first paint so an offline device
    // shows a disabled idle pill immediately; later reconnects refresh on tap.
    _online = await _onlineProbe();
    notifyListeners();

    _eventsSub = _manager.events.listen(_onEvent);
  }

  Future<bool> _refreshOnline() async {
    final online = await _onlineProbe();
    if (online != _online) {
      _online = online;
      notifyListeners();
    }
    return online;
  }

  /// Picks the primary available source, decides whether it is downloadable,
  /// and reflects any existing download record.
  Future<DownloadPillStatus> _resolveSourceAndRecord() async {
    final locationsResult = await _videoRepository.getSourceLocationsForVideo(
      videoItemId,
    );
    if (locationsResult case Err()) {
      return DownloadPillStatus.hidden;
    }
    final locations = (locationsResult as Ok<List<SourceLocation>>).value;
    if (locations.isEmpty) return DownloadPillStatus.hidden;

    final primary = _pickPrimary(locations);
    _providerType = primary.providerType;
    _sourceUri = primary.sourceUri;
    _sourceSizeBytes = primary.sizeBytes;
    _downloadable = providerIsDownloadable(primary.providerType);
    if (!_downloadable) return DownloadPillStatus.hidden;

    final existing = await _downloadRepository.getByVideoItem(videoItemId);
    if (existing case Err()) return DownloadPillStatus.idle;
    final records = (existing as Ok<List<DownloadRecord>>).value;
    if (records.isEmpty) return DownloadPillStatus.idle;

    // getByVideoItem is newest-first, so the head is the record that matters.
    final record = records.first;
    _downloadId = record.id;
    _sizeBytes = record.sizeBytes;
    _downloadedBytes = record.downloadedBytes;
    return _statusFor(record);
  }

  static SourceLocation _pickPrimary(List<SourceLocation> locations) {
    for (final l in locations) {
      if (l.isPrimary && l.availability == AvailabilityState.available) {
        return l;
      }
    }
    for (final l in locations) {
      if (l.availability == AvailabilityState.available) return l;
    }
    return locations.first;
  }

  void _onEvent(DownloadEvent event) {
    final record = event.record;
    if (record.videoItemId != videoItemId.value) return;
    // A cancelled download vanishes; fall back to idle.
    if (record.status == DownloadStatus.canceled) {
      _downloadId = null;
      _downloadedBytes = 0;
      _sizeBytes = _sourceSizeBytes;
      _lastError = null;
      _status = DownloadPillStatus.idle;
      notifyListeners();
      return;
    }
    _downloadId = record.id;
    _sizeBytes = record.sizeBytes;
    _downloadedBytes = record.downloadedBytes;
    if (event.error != null) _lastError = event.error;
    _status = _statusFor(record);
    notifyListeners();
  }

  DownloadPillStatus _statusFor(DownloadRecord record) =>
      switch (record.status) {
        DownloadStatus.completed => DownloadPillStatus.completed,
        DownloadStatus.failed => DownloadPillStatus.failed,
        // pending / running / paused all read as "in progress" to the user.
        DownloadStatus.pending ||
        DownloadStatus.running ||
        DownloadStatus.paused => DownloadPillStatus.running,
        DownloadStatus.canceled => DownloadPillStatus.idle,
      };

  /// Starts a fresh download of the item's durable source.
  Future<void> start() async {
    final providerType = _providerType;
    final sourceUri = _sourceUri;
    if (!_downloadable || providerType == null || sourceUri == null) return;
    if (!await _refreshOnline()) return; // offline: refuse a fresh start

    final result = await _manager.start(
      DownloadRequest(
        videoItemId: videoItemId.value,
        providerType: providerType,
        sourceUri: sourceUri,
        sizeBytes: _sourceSizeBytes,
        // Pill-initiated downloads start without a learned range flag; the
        // engine still completes them, and a failure falls back to retry.
        acceptsRange: false,
      ),
    );
    switch (result) {
      case Ok(:final value):
        _downloadId = value.id;
        _sizeBytes = value.sizeBytes;
        _downloadedBytes = value.downloadedBytes;
        _lastError = null;
        _status = DownloadPillStatus.running;
      case Err(:final error):
        _lastError = error;
        _status = DownloadPillStatus.failed;
    }
    notifyListeners();
  }

  /// Cancels the in-flight download, dropping its partial and record.
  Future<void> cancel() async {
    final id = _downloadId;
    if (id == null) return;
    await _manager.cancel(id);
  }

  /// Re-attempts a failed download from where the engine left off.
  Future<void> retry() async {
    final id = _downloadId;
    if (id == null) return;
    if (!await _refreshOnline()) return;
    _lastError = null;
    _status = DownloadPillStatus.running;
    notifyListeners();
    await _manager.retry(id);
  }

  /// Removes a completed (or failed) download's file and record. Never touches
  /// the original video or the cache (DL-001).
  Future<void> remove() async {
    final id = _downloadId;
    if (id == null) return;
    await _manager.deleteDownload(id);
    _downloadId = null;
    _downloadedBytes = 0;
    _sizeBytes = _sourceSizeBytes;
    _status = DownloadPillStatus.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_eventsSub?.cancel());
    super.dispose();
  }
}
