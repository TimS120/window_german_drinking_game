"""Export a Window RL PyTorch checkpoint to the Flutter ONNX asset."""

from __future__ import annotations

import argparse
import json
import hashlib
from pathlib import Path

import onnx
import torch
from torch import nn

from window_rl.contract import ACTION_SIZE, CHECKPOINT_FORMAT, HISTORY_FEATURE_SIZE, HISTORY_LENGTH, LEGACY_HISTORY_FEATURE_SIZE, MAX_HISTORY_LENGTH
from window_rl.model import WindowPolicyValueNet


class DeploymentPolicy(nn.Module):
    """Keep the Flutter value output scalar while training uses four critics."""

    def __init__(self, model: WindowPolicyValueNet, reward_scale: float = 1.0) -> None:
        super().__init__()
        self.model = model
        self.reward_scale = reward_scale

    def forward(self, history: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        logits, relative_values = self.model(history)
        # Head zero is always the player currently making the proposal.
        return logits, relative_values[:, :1] / self.reward_scale


def load_checkpoint(path: Path) -> tuple[WindowPolicyValueNet, dict]:
    payload = torch.load(path, map_location="cpu", weights_only=False)
    if payload.get("format") not in (4, CHECKPOINT_FORMAT):
        raise ValueError("Unsupported checkpoint format; retrain/export with this pipeline.")
    model = WindowPolicyValueNet(hidden_size=payload["hidden_size"], local_action_head=bool(payload.get("local_action_head", False)), history_attention=bool(payload.get("history_attention", False)), feature_size=payload.get("feature_size", LEGACY_HISTORY_FEATURE_SIZE if payload["format"] == 4 else HISTORY_FEATURE_SIZE))
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
    history_length = int(payload.get("training", {}).get("history_length", HISTORY_LENGTH))
    if not 1 <= history_length <= MAX_HISTORY_LENGTH:
        raise ValueError(f"Checkpoint history_length must be between 1 and {MAX_HISTORY_LENGTH}.")
    history = torch.zeros((1, history_length, model.history_encoder.input_size), dtype=torch.float32)
    torch.onnx.export(
        DeploymentPolicy(model, payload.get("training", {}).get("reward_scale", 1.0)),
        (history,),
        args.output,
        input_names=["history"],
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
    onnx.checker.check_model(exported, full_check=True)
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
    with args.checkpoint.open("rb") as source:
        checkpoint_digest = hashlib.file_digest(source, "sha256").hexdigest()
    with args.output.open("rb") as source:
        model_digest = hashlib.file_digest(source, "sha256").hexdigest()
    metadata = {
        "trainingRun": args.checkpoint.parent.name,
        "checkpointName": args.checkpoint.name,
        "checkpointSha256": checkpoint_digest,
        "modelSha256": model_digest,
        "trainingTimesteps": payload.get("training", {}).get("timesteps"),
        "trainingCumulativeTimesteps": payload.get("training", {}).get("cumulative_timesteps"),
        "format": payload["format"],
        "actionSize": ACTION_SIZE,
        "historyLength": history_length,
        "historyFeatureSize": model.history_encoder.input_size,
        "historyAttention": bool(payload.get("history_attention", False)),
        "trainingPlayerCounts": payload.get("training", {}).get("player_counts", [payload.get("training", {}).get("player_count", 4)]),
        "trained": payload.get("training", {}).get("status") == "trained",
        "observationRevision": payload.get("training", {}).get("observation_revision", 1),
        "trainingRewardScale": payload.get("training", {}).get("reward_scale", 1.0),
        "stateValueUnits": "unscaled training reward",
        "localActionHead": bool(payload.get("local_action_head", False)),
        "trainingPlayerCount": payload.get("training", {}).get("player_count", 4),
        "description": "Window recurrent policy exported from the PyTorch RecurrentMaskedPPO pipeline.",
    }
    args.output.with_suffix(".metadata.json").write_text(
        json.dumps(metadata, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Exported {args.output}")


if __name__ == "__main__":
    main()
