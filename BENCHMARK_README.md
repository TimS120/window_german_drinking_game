# Repeatable adviser comparison

Run from the repository root on Linux:

```bash
python3 tools/compare_advisers.py
```

The default launcher is **fully headless**. It compiles the actual app's `game_engine.dart`, `policy_core.dart`, and statistical adviser into a native Dart command-line executable. These are copied byte-for-byte into an isolated build snapshot; they are not a separate implementation of the rules. Flutter imports, widgets, rendering, plugin calls, and per-move isolates are absent. It does not launch the normal game, contact Firebase, open a browser, or require a display/Xvfb.

RL runs the current bundled ONNX graph in a persistent, single-threaded Python ONNX Runtime process per game worker. It receives the same encoded public history and legal-action order as the app, with the same highest-legal-logit decision and tie breaking. RL retains the full available public event window for metadata-declared history lengths; statistics keeps its existing 16-event boundary. The Python process contains no game simulator. On this machine, seeded comparisons matched the old app-runtime game results across solo play and 2–4-player games.

Requirements: Linux, the Dart SDK (included with Flutter), Git, and Python 3.12+. The launcher creates an isolated `benchmark-cache/venv` and installs pinned ONNX/NumPy dependencies on its first run; the training environment stays unchanged. Build artifacts and frozen model copies live in `benchmark-cache/`, which is ignored by Git. Unchanged adviser code reuses the compiled executable, and new model weights do not require recompiling it.

Read the printed `benchmark-results/TIMESTAMP/report.md`. That short report contains mean personal drinks, the paired difference and its uncertainty, supported advantages, and runtime. `summary.json` adds medians, 95th percentiles, guesses, passes, game duration, pairwise fewer-drinks/tie frequencies, and source/model SHA-256 fingerprints. These frequencies compare the two methods, not the probability of beating every player at a table. `games.jsonl` retains each completed game's per-seat counts; `run.log` contains compilation output and live progress. The report records backend/worker count as well as evaluation wall time. Results are local and ignored by Git.

## Scope and runtime

Default runs contain **240 complete games**, with a hard maximum of **250** for any comparison configuration. Output folders use the RL training timestamp format: `benchmark-results/YYYY-MM-DD_HH-MM-SS/` (Berlin local time).

| Scenario | Independent initial deals | Complete games |
|---|---:|---:|
| Solo: paired RL/statistics games | 30 | 60 |
| Two-player RL versus statistics, both starting-seat assignments | 30 | 60 |
| Three-player focal replacement against varied opponents | 30 | 60 |
| Four-player focal replacement against varied opponents | 30 | 60 |

For focal replacement, RL and statistics occupy the same evaluated seat in their paired games, starting with the same physical deal and fixed opponents. Focal seats rotate **across deals**, rather than replaying every deal from every seat. Seat counts differ by at most one. The 30 deals use combinations of RL, statistics, casual, probability-aware and cautious opponents; each style has equal representation across the default sample. Opponent order also rotates. Results describe this pooled opponent mixture rather than separate conclusions for every opponent type.

The two-player matchup still runs both starting-seat assignments for every initial deal. Statistical uncertainty resamples complete initial-deal blocks, keeping those related games together.

Use the ordinary command for the complete 240-game assessment:

```bash
python3 tools/compare_advisers.py
```

For a smaller pilot or a focused comparison:

```bash
python3 tools/compare_advisers.py --deals 10
python3 tools/compare_advisers.py --deals 30 --scenarios solo head-to-head
python3 tools/compare_advisers.py --deals 30 --scenarios focal-3 focal-4 --opponents rl statistics
```

Those commands run 80, 120, and 240 games respectively. `--deals 31` with the default selection runs 248 games; `--deals 32` would require 256 and is rejected before gameplay. Any custom combination exceeding 250 is rejected, with instructions to reduce deal count or narrow scenario/opponent selection. The adviser search budget remains 12 rounds by default.

Use `--help` for all options. `--output PATH` chooses a **new** output directory; existing results are never overwritten. Keep the same seeds/settings when comparing revisions, and use fresh seeds for final validation if earlier seeds influenced development.

Independent initial-deal blocks run in parallel. Completion order can differ; results do not depend on that order. The default worker count leaves one CPU core free (three workers on this four-core machine, capped at eight). Set `--workers 1` for serial execution or choose another count. Evaluation uses frozen prepared code/model snapshots and does not overwrite the normal game build.

## Scoring and interpretation

The primary score is the evaluated player's **undiscounted actual total drinks until the board is complete**, including opponents' successful “same” penalties. It never uses predicted drink estimates, training rewards, or turn counts as the score.

Both methods use `WindowGameEngine` for all legal actions, reveals, full connected removals, shuffles, passing, confirmations and completion. Advisers and baseline opponents receive only a reconstructed public observation, with no hidden identities, deck, or environment RNG. RL uses the deployed ONNX graph and highest-legal-logit decision, with a validated trained model/observation contract; it cannot fall back to statistics. CPU ONNX Runtime is pinned and its version is recorded; inference latency describes this headless backend rather than phone/Flutter UI latency.

Every paired method run begins with the same physical initial deal and the same replacement-shuffle seed. Future boards diverge naturally after different decisions. Environment and opponent random streams are separate from adviser sampling. Opponent styles have independent per-seat streams; later draws can diverge after different game trajectories. Evaluation order alternates to reduce order effects.

Statistics uses a fixed **12 paired search rounds** by default, preserving its full existing search, candidate selection, particles, opponent mixture and internal tail approximation. Fixed rounds remove hardware/time-budget differences from move selection. This is intentionally different from the app's 180 ms budget, which can run 3–12 rounds. Use `--statistics-rounds 3`, `6`, `9`, or `12` to examine search-budget sensitivity. Keep the same setting across revisions. The statistical adviser's internal 48-action planning approximation remains part of that method; the external benchmark always plays whole games. The optimized shared adviser reuses public-board rank sums/removal components and avoids rebuilding options for every belief particle. Internal rollout games omit unused event recording; external games keep public history normally. This improves the app adviser too, without changing fixed-round recommendations or the rules.

Casual/probability/cautious opponents are simple public-board baselines with pass probabilities 45%/70%/95%; all take publicly certain guesses first. Casual guesses randomly 60% of the time; otherwise it minimizes immediate expected penalties. Probability-aware opponents favor success probability; cautious opponents minimize immediate expected penalties. These resemble the adviser's opponent assumptions, so their results are sensitivity tests, not independent proof about real human play. RL/statistics/mixed opposition provides complementary tests. The default varied opposition balances all five styles through combinations and rotating positions. The optional `mixed` style uses RL/statistics opponents only. This is not exhaustive enumeration of every seating permutation or homogeneous table setup.

The report uses Δ = RL drinks minus statistics drinks. Negative favors RL. Confidence intervals bootstrap **initial-deal blocks**, retaining all related seat rotations and method pairs. Fewer than 30 deals is explicitly labeled a pilot; no finite minimum guarantees adequate precision. Choose a fixed final sample size after the pilot; do not stop whenever a favorable interval first appears. Intervals are per scenario, without multiple-comparison correction. Means can be sensitive to rare costly games; inspect the percentiles and rerun with more deals or independent seeds when results are close or unstable. There is no overall winner without a chosen weighting of player counts/opponents.

`--practical-difference 1` is the default meaningful-improvement threshold: one drink per player per game. A method can have a supported lower mean without an established advantage greater than that threshold. It is also valid for the result to be inconclusive.

## Failures and unfinished games

Games have **no scoring horizon**: they keep playing until completion. However, software cannot promise every future policy will terminate. The default 100,000-action guard is an operational error detector, not a truncated score. If any game reaches it, returns an illegal action, encounters unavailable inference, or exceeds the per-decision timeout, the entire comparison fails and names **no winner**. Completed games remain in `games.jsonl` for diagnosis but are not used to rank methods from an incomplete suite. There are no retries that selectively discard difficult games and no method substitution.

A failure report includes the scenario, deal, focal seat and method; the JSON also includes the latest acting agent and action/drink counts where available. Raise `--max-actions` only if a valid game needs more time, or investigate the method. `--decision-timeout-seconds` defaults to 60. An optional `--timeout-seconds` limits the whole native run; interruption or timeout also produces a failed report. The launcher terminates every worker process group, including its persistent ONNX subprocess, on interruption. A heartbeat watchdog also detects unresponsive workers. An interrupted run never produces a partial winner.

## Verification

```bash
cd app
flutter test test/advisor_benchmark_test.dart test/rl_policy_test.dart test/statistics/statistics_advisor_test.dart
flutter analyze
```

The tests cover the 240-game default and 250-game cap, balanced focal seats/opponent styles, public-only inputs, atomic “same” penalties, rejecting illegal/unfinished runs, head-to-head totals and correct paired aggregation. Run `python3 -m unittest discover -s tools -p 'test_compare_advisers.py'` from the repository root to check missing prerequisites and interruption cleanup with desktop launches mocked. Actual headless ONNX smoke runs are needed separately. The optional diagnostic launcher `python3 tools/compare_advisers_flutter.py` retains the old, slower Flutter/plugin path for app-runtime checks; that diagnostic requires Xvfb and always isolates its display. It is not the default comparison backend.

## Why evaluation differs from training

Training uses a batched CUDA simulator and neural-network updates. The comparison runs complete games using the app's shared Dart rules and includes the statistical adviser's expensive future search at each decision. GPU training speed therefore does not predict this benchmark's throughput. Reducing search rounds would change the method being tested; the speed improvements preserve the configured round count.

On this machine, an interrupted older run spent 1,340 seconds in the advisers across 33 completed games/15,636 actual actions. The optimized three-worker runner finished the same 33 recorded outcomes plus one additional game in 140 seconds. For the matched games, RL latency fell from 17.0 ms to 1.41 ms, and statistical latency from 129.65 ms to 32.51 ms. A separate 22-game 1–4-player check fell from 100.57 to 11.04 seconds with the same results and three-round budget. These are measured examples, not runtime guarantees.
