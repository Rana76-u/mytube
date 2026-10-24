import 'dart:math' as math;

import 'package:mytube/domain/repositories/video_repository.dart';

/// Transparent, rule-based recommendation scoring (P6-05/P6-06, DISC-001,
/// DISC-002, ARCHITECTURE §8 — "deterministic, testable rule-based scoring").
///
/// The scorer is a *pure* function of a [RecommendationCandidate] and its
/// signals — no database, no provider networking, no ML. Every factor the
/// requirements call out is an explicit, tunable weight so a reviewer can see
/// exactly why an item ranked where it did:
///  * a positive bonus for **unwatched** items,
///  * a bonus for **available** and **preferred-source** items,
///  * a **recency** bonus that decays as an item ages,
///  * a **modest** penalty for recently-watched items (viewing history),
///  * a **repetition-reduction** penalty for items shown moments ago, and
///  * **controlled randomization** — a bounded jitter that only reshuffles
///    near-tied items and is fully reproducible when a seed is supplied.
///
/// Determinism: with [random] null the output is entirely stable; [rank]
/// breaks score ties by item id so equal scores never reorder between runs.

/// The tunable rule weights (DISC-002). Defaults are intentionally modest so
/// no single factor dominates; they are plain numbers, not opaque model
/// parameters, keeping the ranking auditable.
class RecommendationWeights {
  const RecommendationWeights({
    this.unwatchedBonus = 30,
    this.favouriteBonus = 15,
    this.availableBonus = 10,
    this.preferredSourceBonus = 12,
    this.recencyMaxBonus = 20,
    this.recencyPerDay = 0.5,
    this.historyMaxPenalty = 15,
    this.historyPerDay = 0.4,
    this.recentlyShownPenalty = 40,
    this.recentSessionPenalty = 15,
    this.randomAmplitude = 12,
  });

  /// Added when an item has never been played.
  final double unwatchedBonus;

  /// Added when the user favourited the item.
  final double favouriteBonus;

  /// Added when the item's primary source is known available.
  final double availableBonus;

  /// Added when the item's source is one the user prefers.
  final double preferredSourceBonus;

  /// Upper bound of the recency bonus; the newest item earns this, older ones
  /// earn less as [recencyPerDay] subtracts with age.
  final double recencyMaxBonus;

  /// Recency bonus lost per day of item age.
  final double recencyPerDay;

  /// Upper bound of the "recently watched" history penalty; it fades as the
  /// days-since-last-play grow.
  final double historyMaxPenalty;

  /// History penalty relief per day since the item was last played.
  final double historyPerDay;

  /// Penalty for an item that was in the recent recommendation head — the
  /// repetition-reduction rule (DISC-003).
  final double recentlyShownPenalty;

  /// Smaller penalty for an item shown in a *recent previous* browsing session
  /// rather than the current one (disc redesign §18.5). It is deliberately
  /// lighter than [recentlyShownPenalty] so cross-session history nudges, but
  /// never dominates, the ranking, and it fades out entirely once the row is
  /// pruned by retention (§18.6).
  final double recentSessionPenalty;

  /// Maximum magnitude of the controlled-randomization jitter added to a score.
  final double randomAmplitude;
}

/// One item plus the recommendation signals the scorer reads.
///
/// The signals that live on [VideoItemSummary] (favourite, watch progress,
/// last-played, created) are read straight from [item]; the ones that come from
/// outside the summary (source availability/preference, whether it was just
/// shown) are supplied here so the scorer stays a pure function.
class RecommendationCandidate {
  const RecommendationCandidate({
    required this.item,
    this.isAvailable = true,
    this.isPreferredSource = false,
    this.recentlyShown = false,
    this.seenInRecentSession = false,
  });

  final VideoItemSummary item;

  /// Whether the item's primary source is currently reachable.
  final bool isAvailable;

  /// Whether the item's provider is one the user marked preferred.
  final bool isPreferredSource;

  /// Whether the item appeared in the recent recommendation head (drives the
  /// repetition-reduction penalty, DISC-003).
  final bool recentlyShown;

  /// Whether the item was meaningfully exposed in a *recent previous* session
  /// but not the current one. Drives the lighter cross-session penalty (disc
  /// redesign §18.5). Kept separate from [recentlyShown] so the current-session
  /// demotion dominates and cross-session memory only fine-tunes it.
  final bool seenInRecentSession;
}

/// Scores and ranks [RecommendationCandidate]s (P6-05, DISC-001).
class RecommendationScorer {
  RecommendationScorer({
    this.weights = const RecommendationWeights(),
    math.Random? random,
    DateTime Function() clock = DateTime.now,
    // The jitter source; null => fully deterministic ranking.
  }) : _random = random, // ignore: prefer_initializing_formals
       _clock = clock; // ignore: prefer_initializing_formals

  final RecommendationWeights weights;
  final math.Random? _random;
  final DateTime Function() _clock;

  /// The transparent score for [candidate]. Higher ranks sooner.
  ///
  /// Pure for a fixed clock and random state: the same inputs always yield the
  /// same value, which is what makes the rules unit-testable.
  double score(RecommendationCandidate candidate) {
    final item = candidate.item;
    final now = _clock();
    var total = 0.0;

    // Unwatched items rise to the top (DISC-002).
    if (item.lastPlayedAt == null) total += weights.unwatchedBonus;

    // The user's favourites are favoured.
    if (item.isFavourite) total += weights.favouriteBonus;

    // Reachable and preferred-provider sources are boosted.
    if (candidate.isAvailable) total += weights.availableBonus;
    if (candidate.isPreferredSource) total += weights.preferredSourceBonus;

    // Recency: newest earns the full bonus, decaying to zero with age.
    final ageDays = _daysBetween(
      DateTime.fromMillisecondsSinceEpoch(item.createdAt),
      now,
    );
    total += _clamp(
      weights.recencyMaxBonus - ageDays * weights.recencyPerDay,
      0,
      weights.recencyMaxBonus,
    );

    // Modest viewing-history influence: a just-watched item sinks, and the
    // sink fades the longer it has been since it played.
    if (item.lastPlayedAt case final playedAtMs?) {
      final sinceDays = _daysBetween(
        DateTime.fromMillisecondsSinceEpoch(playedAtMs),
        now,
      );
      total -= _clamp(
        weights.historyMaxPenalty - sinceDays * weights.historyPerDay,
        0,
        weights.historyMaxPenalty,
      );
    }

    // Repetition reduction: drop anything that was in the last head.
    if (candidate.recentlyShown) total -= weights.recentlyShownPenalty;

    // Lighter cross-session demotion (§18.5) — only for items seen in a recent
    // earlier session that were not already penalised as just-shown.
    if (!candidate.recentlyShown && candidate.seenInRecentSession) {
      total -= weights.recentSessionPenalty;
    }

    // Controlled randomization: bounded jitter, only enough to reshuffle
    // near-ties. A null random leaves the ranking deterministic.
    if (_random case final jitter?) {
      total += jitter.nextDouble() * weights.randomAmplitude;
    }

    return total;
  }

  /// Ranks [candidates] by descending score into the ordered list of items to
  /// recommend. Score ties break on item id so the result is reproducible.
  List<VideoItemSummary> rank(Iterable<RecommendationCandidate> candidates) {
    final entries = [
      for (final candidate in candidates)
        _Scored(score: score(candidate), candidate: candidate),
    ];
    entries.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.candidate.item.id.value.compareTo(b.candidate.item.id.value);
    });
    return [for (final entry in entries) entry.candidate.item];
  }

  static int _daysBetween(DateTime earlier, DateTime later) {
    final diff = later.difference(earlier);
    return diff.isNegative ? 0 : diff.inDays;
  }

  static double _clamp(double value, double min, double max) =>
      value < min ? min : (value > max ? max : value);
}

class _Scored {
  const _Scored({required this.score, required this.candidate});

  final double score;
  final RecommendationCandidate candidate;
}
