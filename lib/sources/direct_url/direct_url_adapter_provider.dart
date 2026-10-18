import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/sources/direct_url/direct_url_adapter.dart';
import 'package:mytube/sources/direct_url/io_url_metadata_prober.dart';
import 'package:mytube/sources/direct_url/url_metadata_prober.dart';

/// Prober used by the direct-URL adapter and `DirectUrlService` (P4-02).
///
/// Override in tests with a fake to avoid real network I/O.
final urlMetadataProberProvider = Provider<UrlMetadataProber>(
  (ref) => IoUrlMetadataProber(),
);

/// Direct URL adapter (P4-01/P4-02).
///
/// Deliberately NOT part of `videoSourceAdaptersProvider` — see the class
/// documentation on [DirectUrlAdapter]: an empty scan page from this adapter
/// would cause `LibraryRefreshService` to mark every stored direct URL as
/// missing. Consumers that need per-URL operations (availability checks,
/// playback resolution) should watch this provider directly.
final directUrlAdapterProvider = Provider<DirectUrlAdapter>(
  (ref) => DirectUrlAdapter(prober: ref.watch(urlMetadataProberProvider)),
);
