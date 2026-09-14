"""Small policy/value network intended for on-device Window inference."""

import torch
from torch import nn

from .contract import ACTION_SIZE, FEATURE_SIZE


class WindowPolicyValueNet(nn.Module):
    """MLP with named ONNX outputs consumed by the Flutter app."""

    def __init__(self, hidden_size: int = 128) -> None:
        super().__init__()
        self.encoder = nn.Sequential(
            nn.Linear(FEATURE_SIZE, hidden_size),
            nn.ReLU(),
            nn.Linear(hidden_size, hidden_size),
            nn.ReLU(),
        )
        self.policy = nn.Linear(hidden_size, ACTION_SIZE)
        self.value = nn.Sequential(nn.Linear(hidden_size, 1), nn.Tanh())

    def forward(self, observation: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        encoded = self.encoder(observation)
        return self.policy(encoded), self.value(encoded)
