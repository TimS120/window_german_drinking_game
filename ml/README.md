# Window RL pipeline

This directory defines the contract for a future reinforcement-learning policy.
No useful model is trained yet. The repository bundles one deterministic,
untrained ONNX artifact solely to verify that the same model can load on every
target; the app never plays a move automatically.

## Contract

- Observation: one `float32[1, 95]` tensor named `observation`.
- Policy: one `float32[1, 301]` tensor named `policy_logits`.
- Value: one `float32[1, 1]` tensor named `state_value`.
- Invalid actions are masked by Flutter before selecting the largest logit.
- Card action index: `(((row * 6 + column) * 2 + orientation) * 5 + guess)`.
  Index `300` is the legal end-turn/pass action.

Keep `ml/window_rl/contract.py` and `app/lib/rl_policy.dart` in lockstep.

## Future training flow

```powershell
cd ml
py -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements.txt
# Future: run the RL trainer to create checkpoints/window_policy.pt
.\.venv\Scripts\python export_onnx.py --checkpoint checkpoints/window_policy.pt
```

The exporter writes to `app/assets/models/window_policy.onnx` by default. The
Flutter asset directory is already declared in `pubspec.yaml`, so rebuilding
the app bundles the model for Windows, Android, iOS, and web.

## Plumbing-only validation (no training)

To create a random, explicitly untrained checkpoint and validate export:

```powershell
cd ml
.\.venv\Scripts\python create_untrained_checkpoint.py
.\.venv\Scripts\python export_onnx.py --checkpoint checkpoints/untrained_window_policy.pt
```

The repository includes one deterministic random `window_policy.onnx` solely
to test loading the same artifact on Windows, Android, and web. It is not a
useful move policy. Replace it with a trained export when training is added.
