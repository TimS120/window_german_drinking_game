"""Export a Window RL PyTorch checkpoint to the Flutter ONNX asset."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import onnx
import torch

from window_rl.contract import ACTION_SIZE, CHECKPOINT_FORMAT, FEATURE_SIZE
from window_rl.model import WindowPolicyValueNet


def load_checkpoint(path: Path) -> tuple[WindowPolicyValueNet, dict]:
    payload = torch.load(path, map_location="cpu", weights_only=False)
    if payload.get("format") != CHECKPOINT_FORMAT:
        raise ValueError("Unsupported checkpoint format; retrain/export with this pipeline.")
    model = WindowPolicyValueNet(hidden_size=payload["hidden_size"])
    model.load_state_dict(payload["model_state_dict"])
    if model.policy.out_features != ACTION_SIZE:
        raise ValueError(
            f"Checkpoint policy has {model.policy.out_features} actions; "
            f"the app requires {ACTION_SIZE}. Retrain with this pipeline."
        )
    model.eval()
    return model, payload


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("../app/assets/models/window_policy.onnx"),
    )
    args = parser.parse_args()
    model, payload = load_checkpoint(args.checkpoint)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    observation = torch.zeros((1, FEATURE_SIZE), dtype=torch.float32)
    torch.onnx.export(
        model,
        (observation,),
        args.output,
        input_names=["observation"],
        output_names=["policy_logits", "state_value"],
        # The Flutter runtime always evaluates one game state at a time.
        # Static dimensions avoid plugin-specific handling of symbolic batch
        # dimensions and make the bundled action contract auditable.
        opset_version=17,
        # The legacy exporter is intentionally used here: it produces a
        # compact, broadly compatible graph and avoids Windows-console output
        # failures in the newer dynamo exporter.
        dynamo=False,
    )
    exported = onnx.load(args.output)
    policy_output = next(
        output for output in exported.graph.output if output.name == "policy_logits"
    )
    policy_shape = [
        dimension.dim_value for dimension in policy_output.type.tensor_type.shape.dim
    ]
    if policy_shape != [1, ACTION_SIZE]:
        raise ValueError(
            f"Exporter produced policy shape {policy_shape}; expected [1, {ACTION_SIZE}]."
        )
    metadata = {
        "format": CHECKPOINT_FORMAT,
        "actionSize": ACTION_SIZE,
        "trained": payload.get("training", {}).get("status") == "trained",
        "description": "Window policy exported from the PyTorch MaskedPPO pipeline.",
    }
    args.output.with_suffix(".metadata.json").write_text(
        json.dumps(metadata, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Exported {args.output}")


if __name__ == "__main__":
    main()
