# Window ML development

## Independent RL-versus-statistics assessment

The [October 29 comparison](benchmark-reports/2026-10-29/assessment.md) completed
240 full games with the deployed model. RL has a supported lower mean drink
cost in solo and two-player play; the three/four-player comparisons remain
inconclusive, with four-player sample results favoring statistics. Treat
four-player performance as a priority for replication and possible refinement;
training validation gains alone do not establish superiority at every table size.

The advisory policy minimizes the current player's expected remaining drinks.
Read `ml/ml_move_prediction_plan.txt` before changing the information boundary.
The requested 1–4 player support extends the original solo-first scope; it does
not introduce cooperation, collusion, or automatic play.

## Normal from-scratch training

Run `.venv/bin/python train.py` from `ml/`. The standard
`ml/configs/training_config.json` has `initialization_checkpoint: null`, so it
always starts with random weights. No previous run directory is needed.

The completed experiments support retaining 32 past public events plus the
current board (33 records), a 256-unit LSTM with learned history attention,
public player-count inputs, and balanced competitive training across 1–4 seats.
The October 29 refinement improved validation from 73.63 to 64.26 personal drinks;
its saved best was at 22,020,096 additional transitions. The final weights were
worse, so deployment uses `best_window_policy.pt`, not the final checkpoint.

The normal profile allocates 67,108,864 transitions, matching the combined budget
of the original 33.6M run and a 33.6M refinement. Learning rate decreases linearly
from 0.0003 to 0.00002; entropy coefficient decreases from 0.01 to 0.001. These
start values allow initial learning/exploration; the low endpoints allow later
refinement. This uninterrupted annealing profile has not itself completed a full
training experiment and is not a claim of reproducing the two-stage weights.

Retained settings: `gamma=1`, `gae_lambda=0.99`, reward scale 0.01, PPO minibatch
512, four epochs, 512 environments per table size, 65,536-transition rollouts,
and the existing KL guard. Every player minimizes their own actual drinks,
including charges by opponents. No completion/pass bonuses are added.

Training caps each game at 2,000 actions; truncated states bootstrap their
remaining value. Evaluation caps at 4,000 actions and uses 256 games for each of
two fixed seeds per table size. Evaluation/checkpoints occur every 1,048,576
transitions. Inspect completion before comparing capped drink costs. Keep the
same evaluation settings when comparing future normal-config runs, and use
independent game seeds for final assessments.

To refine an existing policy intentionally, set `initialization_checkpoint` to a
compatible `.pt` file and lower the learning rate/exploration as appropriate.
The saved config under `ml/runs/2026-10-29_08-31-48/` records the completed
refinement experiment exactly. Initialization is a weight warm start with a fresh
optimizer/RNG, not exact optimizer resumption. The trainer records source path,
SHA-256, and cumulative transitions, evaluates the initial weights, and retains
them if subsequent updates do not improve the same validation criterion.
`--from-scratch` forces random initialization even when a source was specified.

Solo games never permit ending the turn: the app and training action masks
exclude action 300 when there is one player, and the rules engine rejects direct
end-turn requests. The current trained model needs no retraining: selection
chooses its highest-scoring legal guess after masking out pass. With 2–4 players,
passing remains available after success. The historical success flag in saved
observations stays unchanged for compatibility with existing weights; UI controls
use actual turn-ending legality. Old solo pass events remain readable.

Only public card observations and observed attempted outcomes enter learning.
No hidden identities, deck information, RNG state, computed probabilities, or
statistics-adviser features enter the network. Advice never executes a move.

## Experiment evidence

The October 28 comparison and current decision are documented in
`ml/docs/october_28_training_assessment.md`. Its table separates saved selection
scores from independent checkpoint testing.

The earlier retained runs were inspected through their saved configs and metrics.
Longer training often regressed. The old four-player 384-unit/H32 run reached
only about 50.2% best completion, whereas an older four-player H16 run reached
82.4%; these also differ in implementation and cannot isolate memory or model
size. The October 6 fixed/scaled solo run peaked at 1,048,576 transitions,
80.1% completion and 387.4 recorded drinks. Its final checkpoint was worse.
Historical multiplayer drink columns counted table-level wrong-guess penalties
and omitted “same” opponent charges: they are not comparable to the new
personal-drink metric. Re-evaluate old checkpoints with the current evaluator.
Old format-4 checkpoints remain readable but lack player-count conditioning;
do not warm-start the expanded format-5 network by silently padding weights.

`statistics/docs/insights.md` explains that short history looked preferable
because the old particle filter exhausted its samples. Direct public-constraint
prediction improved with longer history, but this did not establish better
whole-game strategy. RL must learn from raw observations: none of those
calculated constraints or probabilities are added as model features or labels.

The completed October 28 runs differed only in input-history length: 33, 17,
and 5 records, corresponding to 32, 16, and 4 past events plus the current board.
Their exact configurations remain in their run directories. Temporary experiment
configs have been removed; `ml/configs/training_config.json` is the single active
profile. Passes count as public events. Supported length remains 1–64 records.

## Setup and verification

From the repository root:

```bash
cd ml
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -c 'import torch; print(torch.__version__, torch.cuda.is_available())'
OMP_NUM_THREADS=2 .venv/bin/python -m unittest discover -p 'test_*.py'
```

CUDA-native simulation, histories, PPO rollouts, and gradients stay on the GPU.
CPU remains supported for small plumbing checks. `--compile` is optional; first
validate eager training. Higher compute capacity does not establish better play.
To reduce peak memory, reduce `minibatch_size` first. Rollout observations alone
occupy about 1.08 GiB at H32, with additional copies, network activations, and
optimizer memory. Do not launch several training runs concurrently by default.

## Train yourself

From the repository root:

```bash
cd ml
.venv/bin/python train.py
```

This starts a new independent training run with random weights. Training creates
a timestamped directory under `ml/runs/`; previous runs remain intact. Keep the
exact config, metrics, learning curve, summary, best/final checkpoint, and
periodic checkpoints for assessment. Automatic early stopping is disabled.

## Evaluate before deployment

Replace `RUN` with each completed run directory, from `ml/`:

```bash
.venv/bin/python evaluate_policy.py \
  --checkpoint runs/RUN/best_window_policy.pt \
  --config runs/RUN/training_config.json \
  --players 1 2 3 4 --episodes 512 --max-steps 4000 \
  --seeds 2026110101 2026110102 2026110103 \
  --output runs/RUN/held_out_evaluation.json
```

The evaluator tests each table size separately on fixed independent seeds.
`eval_drinks` now measures the original seat-zero player's total received drinks,
including charges caused by other players, through completion or the step cap.
Every seat uses the policy; these are self-play results, not evidence of strength
against humans. The same physical deals are used for each player count.

Reports and CSVs include per-count personal drinks, completion rate, impossible
public-rank guesses, and standard errors over games (conditional on the fixed
trained policy/seeds). The macro standard error averages group errors as a
conservative upper bound because matched deals correlate table sizes. Drinks for capped games are censored partial totals, not
full-game costs. Never prefer a policy just because it fails to finish and has
accumulated fewer drinks. Best-checkpoint selection first maximizes the minimum
completion rate across table sizes, then mean completion, then minimizes mean
personal drinks. This is a feasibility gate, not a completion reward.

If completion remains low, investigate capped trajectories and consider a
longer evaluation horizon. Check
`eval_steps`, pass rate, rank sanity, and each table separately. Larger test
samples and independent training seeds are needed for high-variance drink costs.
Do not compare the old CSV drink values directly with the revised metric.
`--history-length 5` can truncate memory at evaluation without retraining; that
is a sensitivity probe, not a substitute for training the shorter-history model.

After training, provide the run paths. Assessment should inspect configs,
curves, best/periodic checkpoints, per-count held-out completion/drinks/errors,
history ablations, and rank probes. The existing headless app benchmark in
`BENCHMARK_README.md` then tests the selected policy against fixed public-only
opponents and statistics, with seat rotation, rather than self-play alone.
Only promote a model once fresh gameplay comparisons support it.

## Export and compatibility

New checkpoints use format 5 / observation revision 3:

- `history`: float32 `[1, H, 134]`, with original 130 public fields followed by
  one-hot table size `[solo, two, three, four]` in each real record; padding is zero.
- `policy_logits`: float32 `[1, 301]`.
- `state_value`: float32 `[1, 1]`, current-player reward in unscaled units.
- Action indices and the public legal mask are unchanged.

Flutter and the native comparison bridge accept both format-4/130-feature and
format-5/134-feature models, using metadata to choose the encoder. The bundled
trained model and metadata identify the selected October 29 refinement, including
its source checkpoint and ONNX SHA-256 fingerprints.

Export a candidate to scratch first, then validate it:

```bash
.venv/bin/python export_onnx.py --checkpoint runs/RUN/best_window_policy.pt \
  --output runs/RUN/candidate.onnx
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 .venv/bin/python validate_onnx.py \
  --checkpoint runs/RUN/best_window_policy.pt --onnx runs/RUN/candidate.onnx
```

The exporter checks the graph and writes matching metadata. Validation compares
PyTorch and ONNX outputs/actions on Python/Flutter public-history fixtures for
all table sizes, including passes, redeals, wrapping, and reset. For an approved
candidate, copy both the ONNX and matching metadata into `app/assets/models/`,
then run `flutter test --no-pub`, `flutter analyze --no-pub`, and
`flutter build web --no-pub` from `app/`. Automated checks remain headless.

The policy remains advisory: it never executes a move or bypasses confirmations.

## Native Linux and Android inference verification

The exported policy is bundled in both installed apps. The native loader uses a
content-dependent cache filename so replacing the asset cannot silently retain
an earlier graph. Metadata selects the 33×134 input contract. RL failures remain
explicit and never silently select statistics.

A native integration test compares all 32 public-history fixtures with PyTorch
through `WindowRlPolicy`, including legal actions, values, confidence, and
non-mutating proposals. Regenerate expectations whenever the model is replaced:

```bash
cd ml
.venv/bin/python fixtures/generate_deployment_probe.py \
  --checkpoint runs/RUN/best_window_policy.pt \
  --output ../app/integration_test/rl_deployment_cases.dart
cd ../app
xvfb-run -a -s '-screen 0 1920x1080x24' env -u WAYLAND_DISPLAY \
  flutter test integration_test/rl_native_test.dart -d linux
flutter test integration_test/rl_native_test.dart -d ANDROID_DEVICE_ID
```

Linux GUI checks use Xvfb. Android checks require an authorized device and run on
that device. After a test APK, reinstall the normal release APK with `adb install
-r` to preserve existing app data. Build the normal releases with the existing
Firebase configuration as documented in `README.md`.

## Best and second-best app advice

`WindowRlPolicy.rankedProposals` sorts only legal actions by ONNX policy logits,
with stable legal-order tie breaking. Both proposals retain probabilities
normalized over the entire legal mask and the same state-value estimate.
`propose` continues to return the first proposal. The app caches the first two
per public position and cycles best/second only on consecutive same-method
requests. Switching method, playing a move, or restarting resets to best; stale
async results cannot populate a new position's cache. No model change or
retraining is required. Native tests check first/second PyTorch parity and the
real RL/statistics UI sequence on Linux under Xvfb and on Android. Run native
integration entrypoints separately when verifying both files.
