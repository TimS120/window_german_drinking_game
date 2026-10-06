"""Small policy/value network intended for on-device Window inference."""

import torch
from torch import nn

from .contract import ACTION_SIZE, BOARD_FEATURE_SIZE, COLUMNS, HISTORY_FEATURE_SIZE, PLAYER_COUNT, ROWS


class WindowPolicyValueNet(nn.Module):
    """Finite-window LSTM policy with relative-player critic heads."""

    def __init__(self, hidden_size: int = 128, local_action_head: bool = False) -> None:
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
        # Share a learned comparison function across all positions. These are
        # literal public neighbor rank/suit pairs, not probabilities or counts.
        self.local_policy = None
        if local_action_head:
            neighbors = []
            for row in range(ROWS):
                for column in range(COLUMNS):
                    for offsets in (((0, -1), (0, 1)), ((-1, 0), (1, 0))):
                        neighbors.append([
                            (row + dr) * COLUMNS + column + dc
                            if 0 <= row + dr < ROWS and 0 <= column + dc < COLUMNS
                            else ROWS * COLUMNS
                            for dr, dc in offsets
                        ])
            self.register_buffer("neighbor_indices", torch.tensor(neighbors), persistent=False)
            self.local_policy = nn.Sequential(nn.Linear(4, 64), nn.Tanh(), nn.Linear(64, 5))

    def local_action_logits(self, history: torch.Tensor) -> torch.Tensor:
        if self.local_policy is None:
            raise ValueError("local_action_head must be enabled for outcome supervision")
        cards = history[:, -1, :BOARD_FEATURE_SIZE].reshape(-1, ROWS * COLUMNS, 2)
        outside = torch.full_like(cards[:, :1], -2)
        cards = torch.cat((cards, outside), dim=1)
        neighbors = cards[:, self.neighbor_indices].flatten(-2)
        logits = self.local_policy(neighbors).flatten(1)
        return torch.cat((logits, torch.zeros_like(logits[:, :1])), dim=1)

    def forward(self, history: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        """Encode an ordered public-history window with a real LSTM pass."""
        encoded, _ = self.history_encoder(history)
        encoded = encoded[:, -1]
        logits = self.policy(encoded)
        if self.local_policy is not None:
            logits = logits + self.local_action_logits(history)
        return logits, self.value(encoded)
