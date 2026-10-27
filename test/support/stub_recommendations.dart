import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';

/// A hand-written stand-in for the ranking pipeline.
///
/// "Up Next" and the player only care that the recommendation pool is what they
/// consume, not how it was ordered, so a stub keeps those tests free of the
/// scorer's signals (availability, exposure history, jitter). Use it as:
///
/// ```dart
/// recommendationsProvider.overrideWith(() => StubRecommendations(items))
/// ```
class StubRecommendations extends RecommendationsController {
  StubRecommendations(this.items);

  final List<VideoItemSummary> items;

  @override
  Future<List<VideoItemSummary>> build() async => items;
}
