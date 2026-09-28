"""Small policy/value network intended for on-device Window inference."""

import torch
from torch import nn

from .contract import ACTION_SIZE, HISTORY_FEATURE_SIZE, PLAYER_COUNT


class WindowPolicyValueNet(nn.Module):
    """MLP with named ONNX outputs consumed by the Flutter app."""

    def __init__(self, hidden_size: int = 128) -> None:
        super().__init__()
        self.history_encoder = nn.LSTM(
            input_size=HISTORY_FEATURE_SIZE,
            hidden_size=hidden_size,
            batch_first=True,
        )
        self.policy = nn.Linear(hidden_size, ACTION_SIZE)
        # Values are ordered relative to the player whose decision is being
        # made: current player, next player, and so on.  A scalar critic cannot
        # bootstrap a competitive return after a pass changes the active seat.
        # Do not bound this head: full-game drink returns can be far below -1.
        self.value = nn.Linear(hidden_size, PLAYER_COUNT)

    def forward(self, history: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        """Encode an ordered public-history window with a real LSTM pass."""
        encoded, _ = self.history_encoder(history)
        encoded = encoded[:, -1]
        return self.policy(encoded), self.value(encoded)
