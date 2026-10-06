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
PPO tensors on one PyTorch device. It uses single-player training by default, matching the specification.
Four-player competitive self-play remains available with `player_count: 4`. `ml/window_rl/environment.py` remains the readable
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
16-event `history_length` (supported range: 1–64) and must match the deployed
ONNX contract. The public event log
is serialized in game state, so reconnecting players reconstruct the same
input.

When enabled, four-player self-play remains competitive rather than cooperative: the CUDA simulator
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


## Compatibility contract

- Input `history`: `float32[1, H, 130]`, where `H` is the exported model's
  metadata-declared history length (the current profile uses 16)
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

The default uses the October 6 critic-scaling profile: 512 single-player games,
16-event windows, a 128-unit LSTM plus shared learned comparison head,
16,384 rollout transitions (32 per environment), four PPO epochs, and a
4,194,304-transition budget. The learning rate decreases from 0.0003 to
0.0001; the PPO target-KL guard is retained. The auxiliary observed-outcome
loss has coefficient 0.5. PPO reward/value units use `reward_scale=0.01`;
only active players contribute to critic loss. This smaller, bounded profile replaces the previous
201-million-step default because increasing model size had not addressed the
input bugs or the missing learned rank comparisons.

Evaluation occurs every 524,288 transitions on fixed validation seeds;
every evaluated checkpoint is saved (every 524,288 transitions). Always use
`best_window_policy.pt`, selected by completion rate then lower drink costs.
The final `window_policy.pt` may be worse. A no-improvement patience remains
available for longer experiments. Both rollout and total transitions must be
multiples of the number of environments.

Use `--training-config configs/critic_scaling_validation.json` to reproduce
the tested numerical profile under a separate run directory (that experiment
saved periodic checkpoints every 1,048,576 steps).
`recurrent_local_validation.json` retains the earlier unscaled profile. The earlier
`recurrent_fix_validation.json` is a control experiment with only the data
fixes and no shared comparison head; it did not pass the maximum-rank probe.

`--compile` optionally enables `torch.compile`. The validated experiments use
eager PyTorch; benchmark compilation separately before assuming it is faster.

Each run includes its exact configuration, `metrics.csv`, learning-curve SVG,
elapsed-time summary, periodic/final checkpoints, and the best checkpoint.
New runs also log the rate of obviously impossible guesses during evaluation
and the auxiliary outcome loss. The impossible-guess diagnostic never changes
the policy's inputs or its legal actions.

Regenerate a chart for a historical run with:

```bash
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

The exporter writes matching metadata and checks the ONNX graph. Numerically
compare the export with its PyTorch checkpoint, then run the Flutter tests:

```bash
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 .venv/bin/python validate_onnx.py \
  --checkpoint runs/RUN_DIRECTORY/best_window_policy.pt \
  --onnx ../app/assets/models/window_policy.onnx
```

Validate actual inference in the Flutter app before distributing it:

```bash
cd app
flutter test
flutter run -d chrome
```

## Diagnostic model

For packaging-only checks, an untrained deterministic model can be generated.
Do not replace a validated trained asset with this diagnostic model. Recreate it only for plumbing validation:

```bash
cd ml
.venv/bin/python create_untrained_checkpoint.py
.venv/bin/python export_onnx.py --checkpoint checkpoints/untrained_window_policy.pt
```
