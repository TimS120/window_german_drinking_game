"""Export a Window RL PyTorch checkpoint to the Flutter ONNX asset."""

from __future__ import annotations

import argparse
from pathlib import Path

import torch

from window_rl.contract import CHECKPOINT_FORMAT, FEATURE_SIZE
from window_rl.model import WindowPolicyValueNet


def load_checkpoint(path: Path) -> WindowPolicyValueNet:
    payload = torch.load(path, map_location="cpu", weights_only=False)
    if payload.get("format") != CHECKPOINT_FORMAT:
        raise ValueError("Unsupported checkpoint format; retrain/export with this pipeline.")
    model = WindowPolicyValueNet(hidden_size=payload["hidden_size"])
    model.load_state_dict(payload["model_state_dict"])
    model.eval()
    return model


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("../app/assets/models/window_policy.onnx"),
    )
    args = parser.parse_args()
    model = load_checkpoint(args.checkpoint)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    observation = torch.zeros((1, FEATURE_SIZE), dtype=torch.float32)
    torch.onnx.export(
        model,
        (observation,),
        args.output,
        input_names=["observation"],
        output_names=["policy_logits", "state_value"],
        dynamic_axes={
            "observation": {0: "batch"},
            "policy_logits": {0: "batch"},
            "state_value": {0: "batch"},
        },
        opset_version=17,
        # The legacy exporter is intentionally used here: it produces a
        # compact, broadly compatible graph and avoids Windows-console output
        # failures in the newer dynamo exporter.
        dynamo=False,
    )
    print(f"Exported {args.output}")


if __name__ == "__main__":
    main()
