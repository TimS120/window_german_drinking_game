# Window ML development

This document explains how to train and deploy the advisory move-proposal
model. [`ml/ml_move_prediction_plan.txt`](ml/ml_move_prediction_plan.txt) is
the authoritative target and restriction specification; read it before
changing observations, actions, rewards, or evaluation criteria.

## Pipeline

```text
batched Window simulator -> masked PPO training -> .pt checkpoint
                                                -> ONNX export -> Flutter proposal button
```

The model only proposes a move. The Flutter rules engine remains authoritative
for every legal move and result.

## Why training is CUDA-native

The original pipeline combined a tiny neural network with a Python/NumPy
simulation. Moving only inference to a GPU was ineffective because Python work
and CPU↔GPU transfers dominated every step.

`ml/window_rl/cuda_environment.py` fixes that by keeping the batched board,
deck, masks, sampled actions, rewards, redeals, public-history windows, and
PPO tensors on one PyTorch device. It uses four-player shared-policy
self-play by default. `ml/window_rl/environment.py` remains the readable
single-game reference implementation. Metrics and checkpoint writing are the
only normal CPU synchronization points.

## Recurrent public history

Window is partially observable: a card can be publicly revealed, removed, and
later redealt face-down. The model therefore receives a chronological public
event window. Each event contains the visible board before an action, action,
outcome, and visible removed cards. Cards include rank and suit, allowing the
model to learn from the four physical copies of every rank without seeing
hidden cards.

The policy is a real LSTM policy/value network: it processes the ordered
history and PPO backpropagates through that sequence. It is not a flat PPO
input with unordered old data. The current training configuration uses a
32-event `history_length` (supported range: 1–64) and must match the deployed
ONNX contract. The public event log
is serialized in game state, so reconnecting players reconstruct the same
input.

Self-play remains competitive rather than cooperative: the CUDA simulator
tracks a reward stream for every seat. The first recurrent experiment revealed
that a scalar critic with an end-of-rollout return could see only 16 moves per
game and therefore could not propagate late drinks or completion rewards. The
current trainer uses four critic heads ordered relative to the current player
(`current`, `next`, `next-next`, `previous`). It rotates those predictions
back to physical seats and applies per-seat GAE across rollout boundaries.
The policy advantage still uses only the current player's head. The deployment
export keeps the value output scalar by exposing that current-player head.

An evaluation edge case also needed a fix: completed games may have no legal
follow-up action. Evaluation records a terminal result, resets that individual
environment before the next batch inference, and excludes its replacement from
the evaluation metrics.

The CUDA simulator test samples legal moves repeatedly and verifies that every
environment still owns all 36 cards exactly once across board and deck:

```bash
cd ml
.venv/bin/python -m unittest test_cuda_environment.py -v
```

## Latest training review

The v4 run in `ml/runs/2026-09-28_18-47-46/` completed 67,108,864 transitions
in 36:57 with compilation enabled. Its best recorded checkpoint occurred at
4,194,304 transitions, reaching 82.4% completion and 499.2 evaluation drinks.
The final checkpoint regressed to 24.6% completion and 1,007.0 drinks. The
learning curve shows a sustained entropy decline and later policy regression,
so extending the identical configuration would waste compute rather than
improve it.

The next configuration lowers the update size, adds a PPO target-KL guard,
compares all checkpoints on the same two held-out deck sets, and stops after a
long no-improvement streak. It retains a larger maximum budget only for the
case where learning remains stable.

The next iteration uses a 32-event recurrent window and a 384-unit LSTM. The
v5 policy remained stable but plateaued after 52.4M transitions (best fixed
held-out result: 76.8% completion and 549.0 drinks at 31.5M). Doubling the
public context is the next targeted change: it lets the learned belief retain
more revealed/removed-card evidence instead of spending more time repeating
the same 16-event input. It requires a fresh training run and an ONNX export;
the bundled 16-event asset remains compatible until that export replaces it.

## Compatibility contract

- Input `history`: `float32[1, H, 130]`, where `H` is the exported model's
  metadata-declared history length (the current bundled asset uses 16; the
  next training configuration uses 32)
- Output `policy_logits`: `float32[1, 301]`
- Output `state_value`: `float32[1, 1]`
- Actions `0..299`: card position × orientation × guess type
- Action `300`: pass/end turn

Flutter masks illegal actions before selecting a proposal. Changing this
contract requires coordinated changes to the app, simulator, tests, checkpoint
format, and ONNX exporter.

## Set up

On Linux with a supported NVIDIA driver:

```bash
cd ml
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
```

The Linux PyTorch package installs a matching CUDA user-space runtime. A
working NVIDIA driver is required; a separate `nvcc` toolkit is not. Verify it:

```bash
.venv/bin/python -c 'import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0))'
```

## Train

CUDA is the default device:

```bash
cd ml
.venv/bin/python train.py
```

The default configuration is tuned for the RTX 5060 Ti: 4,096 simultaneous
four-player games, 65,536 rollout transitions, and a maximum of 201,326,592
total steps. It uses a conservative learning-rate decay, two PPO update epochs,
and a target-KL guard to avoid the policy collapse observed in the long v4
experiment. The run evaluates/saves candidates every 1,048,576 steps. It may
stop earlier after 20 held-out evaluations without a new best candidate; this
avoids spending GPU time training past a sustained regression. Both
`rollout_steps` and `total_timesteps` must be multiples of
`environment.parallel_environments`.

The 32-event, 384-unit recurrent model is materially more expensive than the
previous 16-event, 256-unit model; treat the maximum budget as a multi-hour
ceiling, not an expected duration. Early stopping normally ends an unproductive
run much sooner. Its PPO `minibatch_size` is deliberately 2,048 rather than
the older 16,384: recurrent backward activations at the larger size exceed the
16 GB GPU memory budget. Smaller minibatches take more optimizer updates per
rollout but preserve the same 65,536 rollout transitions and avoid CUDA OOM.

For a fast smoke run, copy the configuration and use, for example, 256
environments, 4,096 rollout steps, and 8,192 total steps. Once a normal run
succeeds, `--compile` may improve long experiments at a one-time startup cost:

```bash
.venv/bin/python train.py --compile
```

`--compile` enables PyTorch's `torch.compile` for the policy/value network. It
captures repeated tensor operations and asks TorchInductor to specialize and
compile GPU kernels for them. It does not change the model, rules, rewards, or
use CUDA for any additional game logic; it only optimizes repeated model
forward/backward calls. The first rollout is slower while compilation occurs,
and the benefit depends on the PyTorch/GPU driver combination. Use it for long
runs after a normal smoke run works; omit it if compilation fails or makes the
measured run slower. Tiny floating-point differences versus the eager run are
normal.

Each run creates `ml/runs/TIMESTAMP/` with its copied configuration,
`metrics.csv`, periodic checkpoints, final `window_policy.pt`, and
`best_window_policy.pt`. The latter is selected by completion rate first and
then lower evaluation drinks. Evaluation uses two fixed independent held-out
deck seeds, so candidates are compared on the same boards. It also writes
`training_summary.json` with the
live/final elapsed duration and `learning_curve.svg`, updated after every
rollout and once more after training completes. The chart shows smoothed
rollout drinks, held-out evaluation drinks, completion rate, policy entropy,
and approximate KL; lower drinks and higher completion are the useful quality
signals, while KL helps diagnose oversized PPO updates.

Regenerate a chart for any finished historical run with:

```bash
cd ml
.venv/bin/python plot_training.py runs/RUN_DIRECTORY/metrics.csv \
  --output runs/RUN_DIRECTORY/learning_curve.svg
```

## Evaluate and export

Select candidates by deterministic, held-out evaluation: prioritize mean drinks
per completed game, completion rate, and legal suggestions. Do not select by
PPO loss alone. The exact acceptance requirements are in the ML specification.

Export a selected checkpoint:

```bash
cd ml
.venv/bin/python export_onnx.py \
  --checkpoint runs/RUN_DIRECTORY/best_window_policy.pt \
  --output ../app/assets/models/window_policy.onnx
```

The exporter writes matching metadata. Validate every exported model in the
Flutter app before committing it:

```bash
cd app
flutter test
flutter run -d chrome
```

## Diagnostic model

The checked-in ONNX model is deterministic but untrained; it tests packaging,
not play quality. Recreate it only for plumbing validation:

```bash
cd ml
.venv/bin/python create_untrained_checkpoint.py
.venv/bin/python export_onnx.py --checkpoint checkpoints/untrained_window_policy.pt
```
