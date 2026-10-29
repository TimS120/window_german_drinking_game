"""Public-history policy/value network for Window inference."""

import torch
from torch import nn

from .contract import ACTION_SIZE, BOARD_FEATURE_SIZE, COLUMNS, HISTORY_FEATURE_SIZE, PLAYER_COUNT, ROWS


class WindowPolicyValueNet(nn.Module):
    """Finite-window LSTM policy with relative-player critic heads."""

    def __init__(self, hidden_size: int = 128, local_action_head: bool = False,
                 history_attention: bool = False, feature_size: int = HISTORY_FEATURE_SIZE) -> None:
        super().__init__()
        self.history_encoder = nn.LSTM(
            input_size=feature_size,
            hidden_size=hidden_size,
            batch_first=True,
        )
        self.history_attention = nn.Linear(hidden_size, 1) if history_attention else None
        self.context_projection = nn.Sequential(nn.Linear(hidden_size * 2, hidden_size), nn.Tanh()) if history_attention else None
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
        if self.history_attention is not None:
            # Learned retrieval of older public records, with padding excluded.
            scores = self.history_attention(encoded).squeeze(-1)
            valid = history[:, :, :BOARD_FEATURE_SIZE].abs().sum(-1) > 0
            valid[:, -1] = True
            weights = scores.masked_fill(~valid, -1e9).softmax(-1)
            context = (encoded * weights.unsqueeze(-1)).sum(1)
            encoded = self.context_projection(torch.cat((encoded[:, -1], context), -1))
        else:
            encoded = encoded[:, -1]
        logits = self.policy(encoded)
        if self.local_policy is not None:
            logits = logits + self.local_action_logits(history)
        return logits, self.value(encoded)
