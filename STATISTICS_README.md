# Statistics move adviser

Select **Propose best move → Pure statistics**. The adviser estimates the
current player's remaining drinks through game completion. It does not execute
moves or learn from opponents. RL availability or inference failures are displayed as errors; they never select this adviser automatically.

## Repository layout

- `statistics/` contains statistics-only evaluation tools, their Python tests,
  the native history experiment, and supporting investigation documents.
- `app/lib/statistics/` contains the runtime adviser, card beliefs, table model,
  and public statistics API. They remain Dart parts of the shared `policy_core.dart`
  library so app and native benchmarks use the same game types and implementation.
- `app/test/statistics/` contains the Flutter statistics tests.
- `STATISTICS_README.md` is the single statistics overview at repository root.
  The shared RL-versus-statistics comparison stays in `tools/` and is described in
  `BENCHMARK_README.md`; shared generated results/cache folders remain unchanged.

From the repository root, run the statistics-only checks with:

```bash
python3 -m unittest discover -s statistics/tests -p 'test_*.py'
cd app
flutter test test/statistics
```

## Information boundary and beliefs

`WindowGameEngine.publicObservation()` copies face-up cards, turn flags, player
information, and a configurable window of 0–32 public events (default: 16). Face-down identities are null and
no deck cards are copied. It supplies both the synchronous API and the
asynchronous UI API; actual hidden cards and RNG state never enter the search.

The retained method has two distinct probability paths:

- **Reported next-guess probabilities** are calculated directly from nested
  public card constraints in `statistics_card_beliefs.dart`. An untouched hidden
  slot excludes cards observed elsewhere since its last deal; a replacement
  starts with a wider allowed set. These sets remain nested under the current
  full-shuffle rules, allowing exact current-card marginals without particles.
- **Strategic ranking and future search** retain the previous 128-sample filter
  and world generator. They may still exhaust compatible samples and fall back
  to the current-board prior. The direct calculation runs after selection and
  never consumes that search's RNG.

`inspectBeliefs` and proposal percentages use the direct calculation. Its
probabilities are exact for the retained public-constraint model, not a claim
that the chosen move minimizes true whole-game drinking costs. Inconsistent
history falls back to the current public board. Nothing is persisted between
requests or sessions, and older-than-window observations are discarded.

See [Documented insights and adoption decision](statistics/docs/insights.md) for the
history study, exhaustive validation, unsuccessful full-strategy experiments,
and the narrower changes that were supported by the evidence.

## Future search

All legal actions receive success estimates and expected immediate penalties,
including the complete connected removal group. Internal ranking retains its
previous card-count/sampled estimates and conservative certainty checks. The
percentage shown with the selected move is then corrected by the direct public
constraint calculation, without changing those ranking scores.

Up to nine distinct candidates enter future search: four with the lowest
immediate expected penalties, four with the highest success estimates, and
passing whenever legal. Each candidate is evaluated on paired sampled worlds
and shuffle seeds so comparisons have less noise. Guesses with the same target
and the same success condition and same-rank drink effects share their rollout result
within that scenario, even when their orientations differ. This avoids duplicate
simulations while preserving candidate ordering, tie breaking, and fixed-round
scenario semantics. The sampled first-move penalty is replaced with its probability-weighted expectation, further reducing
noise when only a few scenarios fit the budget.

A final-card action can override the search only when the direct public
constraints prove it correct. Finishing immediately adds zero personal drinks,
so this exception is provably optimal for the stated objective. It does not play
a move or skip confirmations. Other actions retain the existing search choice.

In multiplayer games, the adviser requires evidence before overriding a legal
pass with a risky guess. It compares the estimated benefit against one paired
standard error of the simulated cost difference. If that benefit is no larger,
it recommends passing with “Pass; benefit of guessing is unclear.” This avoids
treating tiny, noisy simulation advantages as reasons to take more immediate
risk. It is a conservative switching heuristic, not a calibrated confidence
interval or a different learning objective. It adds no rollouts and never overrides
a selected publicly certain guess. Solo games keep the original comparison rule.

## History-length investigation

`StatisticsPolicy.propose`, `proposeFromState`, `inspectBeliefs`, and
`WindowRlPolicy.proposeStatistics` accept `historyLength: 0` through `32`.
The default remains `16`; the shorter-default/full-search prototype was not adopted. Zero removes the public move log while retaining the
current board, players, public scores, and legal turn flags. The limit counts
public events, including passes, rather than guesses alone. Raw-state entry
points enforce the same window and sanitize private values before inference.

`inspectBeliefs` exposes public rank marginals and diagnostics. Statistical
proposals include optional diagnostics for the requested/available history,
reported-probability fallback, preparation time, total time, and search-round
count. `searchHistoryFallback` separately identifies depletion in the old search
filter; `guaranteedFinish` marks a proven final reveal, and `probabilityMicros`
measures the extra direct calculation.
These are measurement outputs and do not influence the selected move.

Reproduce the native, headless ablation from the repository root:

```bash
python3 statistics/tools/compare_statistics_history.py
```

The default run compares `0, 4, 8, 16, 24, 32` over 240 complete games, with
matched initial deals across all four player counts and six fixed search rounds.
It also scores all integer lengths `0–32` on identical public-board snapshots.
Hidden ranks are read only by the external evaluator after predictions, never
by the adviser. The tool compiles the actual shared Dart adviser and rules into
a cached CLI; it does not need ONNX, a display, Firebase, or a network connection.
Each complete-game comparison is capped at 250 games.

By default the experiment uses an independent scenario RNG (`scenarioSeed`)
so a longer belief reconstruction does not merely change the randomized search
sequence. Omit that optional API argument in production to preserve the existing
sequence. `--production-stream` tests that original coupled stream, and
`--probe-only --probe-deals 8` runs a larger prediction-only check. Probe seeds
are distinct for each player count; snapshots within one trajectory remain
correlated. Follow the report's caveats before treating a small mean difference
as an improvement or changing the app default.

Longer memory is not automatically better for the retained search with 128 finite particles. Repeated
conditioning can exhaust the sampled arrangements and force a current-board
reset, losing useful recent history. The investigation therefore measures reset
rates and proper prediction scores alongside drinks and runtime. The original ablation did not change inference. Subsequent work fixed the
reported probability layer, but full-search trials were inconsistent; the
search filter and default remain unchanged. The insights document records both
findings rather than treating prediction gains as proven gameplay gains.

## Player count and turn exposure

Player count is read from the public seat list on every request. The card
probabilities themselves stay independent of the number of players: the deck
and public card evidence are unchanged. Strategic values depend on who plays
next and how other players can charge the advised player drinks.

| Players | Passing and future play |
|---|---|
| 1 | Passing returns to the same person. Normal advice excludes that redundant option, and rollouts keep guessing rather than spending steps passing to themselves. All remaining penalties belong to the solo player. |
| 2 | Passing hands control to one opponent. Scenarios cover that opponent's casual, probability-aware, and cautious styles. Tail exposure follows the alternating seats. |
| 3 | Two opponents may act before the advised player returns. Additional scenarios include mixed opponent styles, with future exposure and “same” charges assigned to the relevant seats. |
| 4 | Three opponents can act before the advised player returns. The same seat accounting and mixed-table hypotheses include all three without adding rollouts. |

`StatisticsTableModel` holds fixed public seat-cycle assumptions; it is not a
learned model. For every group of three scenarios, each opponent is assigned
all three styles once. The first three scenarios stress-test uniformly casual,
probability-aware, and cautious tables. The next three mix styles across seats;
later groups alternate homogeneous and mixed profiles as the time budget allows.
Each opponent keeps its assigned style throughout one rollout. Two-player games
retain the original three individual-opponent hypotheses.

The opponent styles have the existing behavior:

- Casual: sometimes chooses a random legal guess; passes with probability 45%.
- Probability-aware: favors success probability; passes with probability 70%.
- Cautious: favors low expected immediate penalties; passes with probability 95%.

All styles take publicly certain guesses before considering passing. In
multiplayer games, the advised player's rollout continuation favors low expected
penalties and passes when available unless a guess is certain. Solo rollouts
continue guessing. All these policies use their simulated public boards, never
the sampled hidden answers, and do not adapt to human behavior.

The canonical rules engine resolves sampled outcomes, removals, shuffles,
passing, and “same” penalties charged by other players. The objective counts
only the advised player's drinks. Each rollout stops at completion or 48 actions.
For unfinished games, a tail approximation assumes one successful reveal per
turn followed by passing. It assigns remaining reveals in actual cyclic seat
order, starting at the current player or the next player if a pass is available.
It therefore distinguishes having to act now from the window potentially ending
before the owner plays again, instead of dividing remaining exposure equally.

The tail prices the owner's scheduled reveals using current safe failure/success
odds. It also estimates “same” charges from other seats using their fixed styles;
those can affect the owner without the owner taking another turn. It is still
an approximation: later failures, redeals, changing ranks, and extra guesses are
simulated within the 48-action horizon but not recursively expanded in the tail.
No extra rollout, training, longer history, or hidden information is required.

## Runtime and presentation

The default search targets 180 ms, with 3–12 complete paired scenario rounds.
Rounds finish in groups of three so each opponent style has equal weight.
Belief reconstruction and the minimum three rounds are mandatory; completing
a group can overshoot the time target. Fixed bounds on particles, candidates,
rounds, and rollout length limit total work even on slower hardware.

Installed Flutter apps run the search through `compute()` in a worker isolate.
Flutter web runs `compute()` on its main event loop, so its fixed work bounds
still matter. No smartphone latency guarantee is inferred from desktop timing.

Suggestions show estimated next-guess success, estimated remaining personal
drinks, and a short English reason. Passing displays “no immediate drinks”
instead of an artificial 100% card-success percentage. Reasons such as “Lower
expected future drinks” describe the criterion used; they are not proofs of
optimality. Neither the percentages nor the future estimates are calibrated
confidence intervals.

## Validation and limitations

Run `flutter test` and `flutter analyze` from `app/`. Tests cover hidden-card
permutation invariance, replacement versus untouched-card beliefs, the 16-event
boundary, legal and non-mutating suggestions, a guaranteed finishing move,
pending confirmations, exchangeable-card symmetry, equivalent-guess handling,
the uncertainty-aware pass rule, and the asynchronous result path. Separate history tests cover every limit 0–32, zero-history priors, old-event
truncation, hidden-card permutation invariance, raw-state sanitization, and worker
argument propagation. Table-model tests cover 1–4 players, cyclic seat accounting, balanced/mixed style
profiles, solo pass removal, and identical advice from private/public snapshots.

The method is bounded approximate search, not an exhaustive optimal solver.
Shortlisting, particle depletion, fixed opponent assumptions, simple continuation
policies, and the tail approximation can affect recommendations. Superiority
over a trained RL policy requires a separate controlled gameplay comparison;
it is not claimed by this implementation.

The headless comparison imports this same adviser through `policy_core.dart`. Shared optimizations reuse public removal components/rank sums and omit unused history recording in internal search rollouts; the externally played game retains its public history. Fixed-round decisions are deterministic. Group-averaged probabilities and the
uncertainty-aware switching rule intentionally change strategy; equivalent-move
reuse preserves the cost of each simulated scenario. See `BENCHMARK_README.md`.
