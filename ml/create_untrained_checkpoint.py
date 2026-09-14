"""Create a checkpoint only for validating the export/runtime plumbing.

This deliberately does not train a model and must not be presented as an AI
policy. The Flutter UI will label its output as an untrained model.
"""

from pathlib import Path

import torch

from window_rl.contract import CHECKPOINT_FORMAT
from window_rl.model import WindowPolicyValueNet


def main() -> None:
    output = Path("checkpoints/untrained_window_policy.pt")
    output.parent.mkdir(parents=True, exist_ok=True)
    torch.manual_seed(20260914)
    model = WindowPolicyValueNet()
    torch.save(
        {
            "format": CHECKPOINT_FORMAT,
            "hidden_size": 128,
            "model_state_dict": model.state_dict(),
            "training": {"status": "untrained"},
        },
        output,
    )
    print(f"Created untrained checkpoint: {output}")


if __name__ == "__main__":
    main()
