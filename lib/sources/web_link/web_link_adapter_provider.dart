import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/platform/extractor/extractor_providers.dart';
import 'package:mytube/sources/web_link/web_link_adapter.dart';

/// Web-link adapter (DL4.2).
///
/// Deliberately NOT part of `videoSourceAdaptersProvider` — see the class
/// documentation on [WebLinkAdapter]: an empty scan page from this adapter
/// would cause `LibraryRefreshService` to mark every stored web link as
/// missing (the same reason the direct-URL adapter is excluded). It is wired
/// into `playbackSourceResolverProvider`'s adapter list so per-item playback,
/// availability and eligibility resolution can reach it.
final webLinkAdapterProvider = Provider<WebLinkAdapter>(
  (ref) => WebLinkAdapter(extractor: ref.watch(mediaExtractorProvider)),
);
