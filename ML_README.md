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
deck, masks, sampled actions, rewards, redeals, GAE, and PPO tensors on one
PyTorch device. `ml/window_rl/environment.py` remains the readable single-game
reference implementation. Metrics and checkpoint writing are the only normal
CPU synchronization points.

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

- Input `observation`: `float32[1, 95]`
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
games, 65,536 rollout transitions, and 1,048,576 total steps. Both
`rollout_steps` and `total_timesteps` must be multiples of
`environment.parallel_environments`.

For a fast smoke run, copy the configuration and use, for example, 256
environments, 4,096 rollout steps, and 8,192 total steps. Once a normal run
succeeds, `--compile` may improve long experiments at a one-time startup cost:

```bash
.venv/bin/python train.py --compile
```

Each run creates `ml/runs/TIMESTAMP/` with its copied configuration,
`metrics.csv`, periodic checkpoints, and final `window_policy.pt`.

## Evaluate and export

Select candidates by deterministic, held-out evaluation: prioritize mean drinks
per completed game, completion rate, and legal suggestions. Do not select by
PPO loss alone. The exact acceptance requirements are in the ML specification.

Export a selected checkpoint:

```bash
cd ml
.venv/bin/python export_onnx.py \
  --checkpoint runs/RUN_DIRECTORY/window_policy.pt \
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
