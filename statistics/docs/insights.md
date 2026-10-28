# Statistics insights and retained improvements — 28 October 2026

## Decision

The reported next-guess success probability now uses a direct calculation from public observations. The move-selection search and the default history length of 16 remain unchanged. A final-card move overrides the search only when public information proves it will complete the game with zero additional personal drinks.

A broader rewrite that used the new beliefs throughout move ranking and simulated worlds was tested but not adopted. More accurate card probabilities did not consistently produce fewer drinks with the existing approximate future search. This distinction follows the requirement to retain only changes supported by the new evidence.

## What the history study taught us

The old 128-particle filter often exhausted its compatible arrangements after repeated observations. It then reset to current-board probabilities. The previous finding that 2–4 events looked more useful than 16–32 was specific to that inference limitation; it was not evidence that older public observations have no value.

The direct calculation has no finite particle population to exhaust. On the same 232 validation snapshots from 31 trajectories, every history length 0–32 retained valid observations without a reset. Each length scored 2,456 hidden cards. Hidden identities were used only by the external scorer after prediction, never by the adviser.

| History | Old Brier score ↓ | Direct Brier score ↓ | Old log loss ↓ | Direct log loss ↓ | Old reset rate | Direct reset rate |
|---|---:|---:|---:|---:|---:|---:|
| 0 | 0.87854 | 0.87854 | 2.1447 | 2.1447 | 0.0% | 0.0% |
| 4 | 0.87746 | 0.87350 | 2.2703 | 2.1168 | 0.4% | 0.0% |
| 16 | 0.89003 | 0.85875 | 3.0698 | 2.0277 | 70.7% | 0.0% |
| 32 | 0.88044 | 0.84192 | 2.2373 | 1.9380 | 98.7% | 0.0% |

Longer memory became useful for prediction once inference was corrected. This does not establish an optimal history length for the whole-game strategy. The default remains 16, and explicit 0–32 settings are retained.

## Why direct calculation is possible

1. A face-down slot cannot contain a physical card publicly visible elsewhere since that slot was dealt. Suits distinguish the four physical copies of a rank. Current face-up cards are unavailable to every hidden slot.
2. A wrong guess returns the revealed removal group to the fully shuffled deck. Untouched hidden slots keep their exclusions; replacement slots receive the widest currently possible card set.
3. Older hidden slots therefore have allowed-card sets nested inside those of younger slots. Observing a new card removes it from every other set, preserving this nesting.
4. Given the uniform prior at the retained-history boundary and the game’s full reshuffles, compatible current assignments have equal probability. Assigning the narrowest sets first samples them uniformly: every later set loses the same number of cards, regardless of which earlier cards were assigned.
5. Marginals can be calculated directly. Before a group, its remaining pool size is its allowed-set size minus the number of older hidden slots. Each card’s probability for one slot is its probability of still being available divided by that pool size. For a group of equally constrained slots, availability decreases by the fraction of that pool used by the group.

This is exact for the retained public-constraint model, not a claim of perfect knowledge or an optimal game solver. It relies on the current 36-card rules and full shuffling of deck plus visible removals. It does not read actual hidden cards, deck order, or game RNG state. Inconsistent historical observations still fall back safely to the current public board.

## What was tested and rejected

The full-search prototype replaced the sampled belief filter and its rollout worlds. A 240-game screen compared five variants over 12 matched initial deals per player count, with six fixed search rounds and fixed human-like opponents. These were production-coupled RNG comparisons; inference changes can also alter subsequent random search draws.

| Players | Previous H16 | Previous H4 | Prototype H4 | Prototype H16 | Prototype H32 |
|---|---:|---:|---:|---:|---:|
| 1 | 515.2 | 470.4 | 232.8 | 492.1 | 272.0 |
| 2 | 166.8 | 215.0 | 163.8 | 234.7 | 179.3 |
| 3 | 236.5 | 164.2 | 164.2 | 114.3 | 172.0 |
| 4 | 170.7 | 75.2 | 101.8 | 87.6 | 123.6 |

The H4 prototype looked promising in that screen. A separate 64-game confirmation used eight new matched deals per player count and compared that candidate against the previous H16 method.

| Players | Previous H16 | H4 prototype confirmation |
|---|---:|---:|
| 1 | 554.4 | 255.6 |
| 2 | 278.6 | 681.5 |
| 3 | 109.6 | 280.1 |
| 4 | 234.8 | 150.8 |

The candidate was worse in the two- and three-player confirmation samples. We therefore did not promote H4 or replace the strategic search with the new engine. The sample sizes and high game variance do not justify a universal strength claim. Prediction quality and bounded-search decision quality are separate engineering targets; future continuation policies still use coarse public-board heuristics and a tail approximation.

## Changes retained in the application

- `statistics_card_beliefs.dart` provides direct public-card probabilities. `inspectBeliefs` and reported proposal percentages use it.
- Search candidate ranking, simulated-world generation, RNG draws, and the conservative pass rule remain the previous implementation. No new probability calculation consumes the search RNG.
- The displayed reason uses the corrected probability and actual visible removal penalty. Expected remaining drinks still come from the existing approximate search, except a proven terminal move has exactly zero remaining cost.
- The only action override is a mathematically certain final reveal. Under the stated objective, zero remaining personal drinks is optimal. Other players’ “same” charges cannot occur after the game has ended, and a correct “same” final guess charges only other players.
- Default history remains 16. The existing 0–32 API remains available. There is no training, opponent learning, automatic play, or hidden-information access.
- Diagnostics distinguish `historyFallback` for the reported probability model from `searchHistoryFallback` for the old search sampler. `guaranteedFinish` marks the safe terminal override; `probabilityMicros` measures the extra calculation. A probability snapshot runs no search, so its search flag is not applicable.

The search sampler can still lose history; this change does not claim to fix that part of the strategic estimator. It fixes the current-card probability layer without importing the unvalidated ranking change.

## Verification of the retained change

- Direct probabilities matched exhaustive enumeration of all 50,400 feasible assignments in a two-cohort public-history fixture.
- Long valid histories retained their constraints without particle exhaustion; malformed histories safely used the current board.
- A rule-engine test constructed a legal history where returned aces prove the last hidden card is between its visible bounds. The adviser chose the certain finish, the engine confirmed it, and personal drinks did not increase.
- A further 64-game check on eight fresh deals per player count found identical total drinks in all 32 baseline/retained-method pairs. This checks selection preservation; it is not evidence of an average drinking reduction. The rare proven override is verified separately by the constructed test.
- Existing tests cover public/private equivalence, hidden-card permutations, bounded history, worker-isolate arguments, legal actions, and 1–4 player handling.

On the native desktop prediction check, the analytic-only calculation averaged roughly 0.083 ms at 16 events and 0.137 ms at 32. These omit Flutter UI/isolate overhead and are not smartphone guarantees. The existing search remains bounded at 3–12 rounds and 48 actions per rollout, with its 180 ms soft target.

Final validation: all 146 Flutter tests and nine Python comparison-tool tests passed; Flutter analysis reported no issues, the web build succeeded, and `git diff --check` was clean.

## Evidence and next steps

Keep the distinction between better probabilities and better play. Integrating exact constraints into future continuation policies may be worthwhile, but it requires fresh gameplay validation before adoption. The successful probability correction does not retroactively validate a shorter default or a wholesale strategy rewrite.

The accompanying investigation artifacts contain raw prototype, confirmation, and retained-method games plus the full all-33-length prediction scores. Prototype results are explicitly not the deployed search.
