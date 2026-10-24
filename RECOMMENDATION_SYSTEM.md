# Recommendation System

This document describes how Personal Video Hub decides **what to show next** in
the Discover feed and the Reels player. It is the reference for the rule-based
recommendation pipeline (DISC-001..003, ARCHITECTURE §8, disc redesign §17–§18).

## 1. What it is (and is not)

The recommender is a **transparent, deterministic, rule-based scorer** — not a
machine-learning model. There is no training pipeline, no server, and no
opaque model weights. Every factor that moves an item up or down the list is an
explicit, tunable number that a reviewer can read and a unit test can pin.

Design guarantees:

- **Fully local.** Ranking reads only the on-device library and its own
  exposure history. Nothing is uploaded (DISC-003, AGENTS "keep recommendation
  history local").
- **Deterministic and testable.** With a fixed clock and no random seed the
  ranking is stable; ties break on item id. Controlled randomization is
  injected as a bounded, seedable jitter so tests can reproduce any order.
- **Auditable.** Scores are a plain sum of named bonuses and penalties, never a
  black box.
- **Degrades gracefully.** Availability and exposure are best-effort: a failed
  source lookup or history read never breaks the feed — it falls back to
  relevance-only ranking.

## 2. Pipeline overview

One candidate pool feeds every surface; only the *ordering strategy* changes
(ADR-002 "one recommendation pipeline with distinct feed modes").

```
Sources (MediaStore / SAF / Direct URL / Cloud)
        │  listVideos()
        ▼
Repository  ──►  Library query (candidate pool)
        │
        ├─► Availability signal (source locations per item)
        ├─► Exposure signal   (recommended_exposures, per session)
        ▼
RecommendationCandidate (item + signals)
        │
        ▼
DiscoverFeedRanker ── mode ──► RecommendationScorer (recommended)
        │                       or chronological  (recentlyAdded)
        │                       or eligibility     (unwatched)
        ▼
Ranked list ──► Discover "Recommended for you" feed
             └─► Reels queue (vertical swipe playback)
```

Key files:

| Concern | File |
|---|---|
| Pure scorer + weights + candidate | [`recommendation_scorer.dart`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/domain/services/recommendation_scorer.dart) |
| Wiring, ranking controller, providers | [`recommendation_scorer_provider.dart`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/domain/services/recommendation_scorer_provider.dart) |
| Ordering strategy per feed mode | [`discover_feed_ranker.dart`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/domain/services/discover_feed_ranker.dart) |
| Feed mode enum | [`discover_feed_mode.dart`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/domain/services/discover_feed_mode.dart) |
| Session boundary policy | [`discover_session.dart`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/domain/services/discover_session.dart) |
| Exposure store contract | [`recommendation_history_repository.dart`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/domain/repositories/recommendation_history_repository.dart) |
| Exposure table (Drift) | [`recommendation_exposures_table.dart`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/data/database/tables/recommendation_exposures_table.dart) |
| Paginated Discover feed | [`discover_feed_provider.dart`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/domain/services/discover_feed_provider.dart) |
| Reels queue (now recommendation-driven) | [`reels_queue_controller.dart`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/features/reels/reels_queue_controller.dart) |

## 3. The scoring signals

[`RecommendationScorer.score`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/domain/services/recommendation_scorer.dart)
turns a [`RecommendationCandidate`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/domain/services/recommendation_scorer.dart)
into a single number. The candidate carries the item plus the signals that do
not live on the summary itself (availability, source preference, and whether it
was just shown).

The score is the sum of these terms. Each maps to a `RecommendationWeights`
field; the defaults below are intentionally modest so no single factor
dominates.

| Term | Default weight | Direction | Meaning |
|---|---:|---|---|
| `unwatchedBonus` | 30 | + | Item has never been played (`lastPlayedAt == null`). Unwatched content rises to the top (DISC-002). |
| `favouriteBonus` | 15 | + | The user favourited the item. |
| `availableBonus` | 10 | + | The item's primary source is currently reachable. |
| `preferredSourceBonus` | 12 | + | The item's provider is one the user prefers. |
| `recencyMaxBonus` / `recencyPerDay` | 20 / 0.5 | + | Freshness bonus: newest earns the full 20 and decays 0.5/day to zero. |
| `historyMaxPenalty` / `historyPerDay` | 15 / 0.4 | − | Modest viewing-history sink: a just-watched item drops and the penalty relieves 0.4/day. |
| `recentlyShownPenalty` | 40 | − | Repetition reduction (DISC-003): demote anything in the recent head. |
| `recentSessionPenalty` | 15 | − | Lighter cross-session demotion for items shown in a recent *earlier* session (§18.5). |
| `randomAmplitude` | 12 | ± | Bounded jitter that only reshuffles near-ties; reproducible with a seed. |

Notes:

- Signals that live on the summary (favourite, watch progress, last-played,
  created-at) are read straight from the item; the external signals are supplied
  on the candidate so the scorer stays a **pure function**.
- `recency`/`history` use an injectable clock so age math is deterministic in
  tests.
- The jitter (`randomAmplitude`) is the *only* stochastic term. It is capped so
  it can never overturn a decisive gap — it exists to vary the head between
  refreshes, not to scramble relevance.

`rank` sorts candidates by descending score and breaks ties on item id, so the
output is fully reproducible.

## 4. Feed modes

[`DiscoverFeedRanker`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/domain/services/discover_feed_ranker.dart)
is the single ordering stage shared by the three
[`DiscoverFeedMode`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/domain/services/discover_feed_mode.dart)
values. They share one candidate pool; only ordering differs.

- **`recommended`** (default) — the rule-based scorer decides. This is the mode
  Reels plays and the Discover "Recommended for you" feed uses.
- **`recentlyAdded`** — strict newest-added-first with a stable id tie-break.
  Scoring is deliberately *not* consulted so recommendation signals can never
  disturb the chronological meaning (§17.3).
- **`unwatched`** — eligibility first: completed videos are excluded,
  never-started videos rank ahead of partially-watched ones, and the scorer is
  used only to break ties *within* each tier (§17.1).

## 5. Repetition reduction and exposure history

Repetition is handled on two complementary levels (DISC-003).

**In-memory head (per controller).** [`RecommendationsController`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/domain/services/recommendation_scorer_provider.dart)
keeps a bounded rolling set of the top ids it just ranked (`_shownHeadSize = 5`,
capped at `_shownHistoryCap = 20`). `reshuffle()` re-ranks from the already-loaded
library so the previous head is penalised and a fresh set surfaces — refresh goes
through `reshuffle`, never provider invalidation (which would recreate the
notifier and drop the history).

**Persisted exposure (per session).** The
[`recommended_exposures`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/data/database/tables/recommendation_exposures_table.dart)
table logs which videos were *meaningfully presented*, keyed by
`(videoItemId, sessionId)`. Exposure is **not** watch history — it only means a
card was shown. The composite primary key makes recording idempotent within a
session, and the cascading FK prunes an item's exposure when its library entry is
removed.

- The Discover feed pages items in and calls `markExposed` as cards surface
  ([`discover_feed_provider.dart`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/domain/services/discover_feed_provider.dart)).
- Items exposed in the **current** session get the strong `recentlyShownPenalty`;
  items exposed in a **recent earlier** session get the lighter
  `recentSessionPenalty` (§18.5).
- **Controlled relaxation:** when the whole eligible pool is already exposed, the
  penalty is dropped so the feed keeps returning useful results instead of
  demoting everything toward randomness.
- **Bounded retention (§18.6):** when a genuinely new session begins, rows older
  than 7 days or beyond 2000 rows are pruned.
- Session identity comes from
  [`DiscoverSession`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/domain/services/discover_session.dart):
  one app-scoped instance whose id stays stable across tab navigation and rolls
  over only after a 30-minute inactivity gap. A widget rebuild or route push never
  creates a session.

All exposure reads/writes are wrapped so a missing or failing history store
degrades to relevance-only ranking — Discover and Reels never break because of
the exposure layer (ADR-003).

## 6. Source availability

`RecommendationsController.build` reads each item's source locations once and
collapses them to a single "reachable?" signal:

- A verified-`available` location wins; otherwise the first location judges.
- **Hard-unavailable** states (missing / expired / revoked / unsupported) demote
  the item via the missing `availableBonus`.
- **Transient** states (offline / unknown) and items with no recorded location
  stay optimistic, so an unverified source is never over-penalised.
- A failed lookup is treated as available so a transient repository error cannot
  silently bury an item.

Preferred-source weighting is supported by the scorer but stays off until a user
source-preference setting exists.

## 7. How the surfaces consume the ranking

[`recommendationsProvider`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/domain/services/recommendation_scorer_provider.dart)
is the single ranked snapshot.

- **Discover** layers pagination over it
  ([`discoverFeedProvider`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/domain/services/discover_feed_provider.dart)):
  lazily-paged, deduplicated, with exposure recorded as items surface. A refresh
  button calls `reshuffle`; the mode chips call `setMode`.
- **Reels** plays the recommendation ranking.
  [`ReelsQueueController.build`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/features/reels/reels_queue_controller.dart)
  watches `recommendationsProvider` and builds the vertical
  [`ReelsQueue`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/lib/features/reels/reels_queue.dart)
  from the ranked list. Previously Reels walked the library in raw
  most-recently-added order — "one after another" — with no personalisation. It
  now shows a curated feed: unwatched, available, favourite and fresh clips rise,
  while just-shown and recently-watched clips sink. Because Reels shares the same
  provider, cross-surface repetition reduction applies too — a video already
  surfaced in Discover is de-prioritised in Reels and vice-versa. The swipe
  navigation surface (`goTo` / `next` / `previous`) is unchanged by the wiring.

## 8. Determinism and testing

- `RecommendationScorer` with a `null` random and a frozen clock is fully
  deterministic; `rank` ties break on id. Tests inject a seeded `math.Random` or
  a frozen `clock` to pin ordering
  ([`recommendation_scorer_test.dart`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/test/unit/domain/recommendation_scorer_test.dart),
  [`recommendation_scorer_provider_test.dart`](file:///e:/02_Development/Projects/1.%20Video%20Streaming%20Personal%20App/mytube/test/unit/domain/recommendation_scorer_provider_test.dart)).
- The provider tests override `recommendationScorerProvider`, `discoverSessionProvider`,
  and `recommendationHistoryRepositoryProvider` to exercise the real ranking path
  with no database.
- The Reels tests (`reels_queue_test`, `reels_screen_test`) now stand up the same
  deterministic pipeline: a no-jitter scorer keeps equal-signal fixtures in the
  stable id order the assertions rely on, and an empty in-memory exposure store
  keeps ranking purely on relevance.

## 9. Constraints honoured

- No ML pipeline (MVP rule-based only).
- Recommendation history stays local; no account, no upload.
- Original videos are never modified as a side effect of ranking.
- No tokens or signed URLs are consulted or logged by the recommender; it reads
  only library summaries, availability states, and exposure ids.
- Empty / small-library states are handled — the feed returns an empty list and
  the surfaces show guidance rather than a blank screen.

## 10. Tuning

All weights are plain numbers on `RecommendationWeights`, so behaviour can be
adjusted without touching the scoring code — for example, raising
`unwatchedBonus` to push more new content forward, or lowering
`randomAmplitude` for a steadier head. Exposing these as user-facing settings is
a natural follow-up (the scorer already reads them as injected parameters).
