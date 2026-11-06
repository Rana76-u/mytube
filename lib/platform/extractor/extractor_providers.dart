import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/platform/extractor/media_extractor.dart';
import 'package:mytube/platform/extractor/media_extractor_impl.dart';

/// Riverpod provider for the extraction seam (DL2.1, §15.1).
///
/// The single production implementation is [MediaExtractorImpl] over the
/// Android plugin; it degrades to an "unavailable" [MediaExtractor] where the
/// plugin is absent so non-Android hosts and widget tests never crash.
///
/// Override in tests with a [FakeMediaExtractor] via
/// `ProviderContainer(overrides: [mediaExtractorProvider.overrideWithValue(fake)])`.
final mediaExtractorProvider = Provider<MediaExtractor>(
  (ref) => MediaExtractorImpl(),
);
