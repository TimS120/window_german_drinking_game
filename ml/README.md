# Window RL training and deployment

This is the only training pipeline for the Flutter game. It uses masked PPO,
PyTorch checkpoints, and ONNX export. The Flutter application on Windows,
Android, iOS, and web consumes the same `window_policy.onnx` artifact.

Training is GPU-native by default. `cuda_environment.py` holds the batched
game state, deck, observations, legal-action masks, sampled actions, rewards,
and PPO tensors on CUDA. The readable `environment.py` is retained as the
single-game reference implementation. No data is copied to the CPU during a
rollout; CUDA synchronization happens only for CSV/checkpoint reporting.

## Compatibility contract

- Observation: `float32[1, 95]` named `observation`.
- Policy: `float32[1, 301]` named `policy_logits`.
- Value: `float32[1, 1]` named `state_value`.
- Indices `0..299` encode a card/orientation/guess. Index `300` is pass/end
  turn. Flutter masks illegal actions before it selects a proposal.

`window_rl/environment.py` deliberately mirrors the public state, legal moves,
redeal behavior, and action indices in `app/lib/game_engine.dart`. The trainer
resolves UI-only confirmations automatically. Training is single-player and
the rewards target minimizing that player's drinks.

## Files

- `configs/training_config.json` — PPO hyperparameters, reward design,
  maximum episode length, and `parallel_environments`.
- `train.py` — trains and writes checkpoints/metrics under `ml/runs/`.
- `window_rl/environment.py` — training simulation with hard action masks.
- `export_onnx.py` — exports a checkpoint plus matching model metadata.

## Train a model

From the repository root on Linux:

```bash
cd ml
.venv/bin/python train.py
```

The repository-local `ml/.venv` is the supported environment. It includes
the CUDA-enabled PyTorch wheel. Verify the install before a long run:

```bash
ml/.venv/bin/python -c 'import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0))'
```

The default configuration runs 4,096 simulations concurrently and collects
65,536 GPU-resident transitions per PPO update. It is tuned for a modern
desktop NVIDIA GPU. For a short smoke test, copy the configuration and use
values that remain divisible: for example `parallel_environments: 256`,
`rollout_steps: 4096`, and `total_timesteps: 8192`.

Training writes a timestamped directory below `ml/runs/`. It contains the
copied configurations, `metrics.csv`, periodic checkpoints, and the final
`window_policy.pt`. The `total_timesteps` setting controls duration. Start by
changing it to `10000` in `configs/training_config.json` to validate the run;
use `500000` or more for an initial real experiment.

`environment.parallel_environments` runs independent games in one CUDA batch.
It increases data-collection throughput but does not change the single shared
policy or the ONNX file produced at the end. `rollout_steps` and
`total_timesteps` must each be exact multiples of this value. Add `--compile`
after a successful normal run to allow PyTorch to compile the network; it can
improve long experiments but has a one-time startup cost.

## Export and deploy

Replace `RUN_DIRECTORY` with the timestamped directory printed by training:

```powershell
cd ml
.\.venv\Scripts\python export_onnx.py `
  --checkpoint runs\RUN_DIRECTORY\window_policy.pt `
  --output ..\app\assets\models\window_policy.onnx
```

This overwrites the bundled ONNX model and writes
`app/assets/models/window_policy.metadata.json`. Rebuild each target; no
separate model installation is needed:

```powershell
cd ..\app
flutter run -d windows --dart-define-from-file=..\firebase-options.json
flutter run -d android --dart-define-from-file=..\firebase-options.json
flutter run -d chrome --dart-define-from-file=..\firebase-options.json
```

For a Git-shared release, review the model, then add the two files under
`app/assets/models/` to your commit. Checkpoints and metrics remain ignored.

## Plumbing-only test model

The checked-in model is deterministic but untrained. To recreate it:

```powershell
cd ml
.\.venv\Scripts\python create_untrained_checkpoint.py
.\.venv\Scripts\python export_onnx.py --checkpoint checkpoints\untrained_window_policy.pt
```

It confirms the complete packaging/runtime path but should not be judged for
move quality.
