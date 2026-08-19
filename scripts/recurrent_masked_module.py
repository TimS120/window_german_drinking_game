"""RLlib PPO module adapter combining framework LSTM support with action masks.

The neural network and PPO implementation are provided by RLlib. This module
only separates the public observation from the legal-action mask and applies
that mask to the categorical action logits.
"""

from __future__ import annotations

from typing import Any

import gymnasium as gym
import torch
from ray.rllib.algorithms.ppo.torch.default_ppo_torch_rl_module import (
    DefaultPPOTorchRLModule,
)
from ray.rllib.core.columns import Columns
from ray.rllib.utils.torch_utils import FLOAT_MIN


class RecurrentActionMaskingTorchRLModule(DefaultPPOTorchRLModule):
    """Default RLlib PPO module with hard masking of illegal actions."""

    def __init__(self, *, observation_space=None, **kwargs):
        if not isinstance(observation_space, gym.spaces.Dict):
            raise ValueError("A Dict observation with observations/action_mask is required.")
        if set(observation_space.spaces) != {"observations", "action_mask"}:
            raise ValueError(
                "Observation keys must be exactly 'observations' and 'action_mask'."
            )

        self.observation_space_with_mask = observation_space
        super().__init__(
            observation_space=observation_space["observations"],
            **kwargs,
        )

    def setup(self):
        super().setup()
        # RLlib builds the encoder for the unmasked vector, while connectors
        # continue to validate and transport the full Dict observation.
        self.observation_space = self.observation_space_with_mask

    def _split_observation(self, batch: dict[str, Any]):
        observation = batch.get(Columns.OBS)
        if not isinstance(observation, dict):
            raise ValueError("The PPO batch does not contain a Dict observation.")
        if "action_mask" not in observation or "observations" not in observation:
            raise ValueError("The PPO batch is missing observations or action_mask.")

        # Construct a new mapping. Mutating RLlib's SampleBatch here corrupts
        # recurrent minibatches and can remove observations from later epochs.
        encoder_batch = {
            **batch,
            Columns.OBS: observation["observations"],
        }
        return observation["action_mask"], encoder_batch

    @staticmethod
    def _apply_action_mask(outputs: dict[str, Any], action_mask):
        inf_mask = torch.clamp(torch.log(action_mask), min=FLOAT_MIN)
        outputs[Columns.ACTION_DIST_INPUTS] = (
            outputs[Columns.ACTION_DIST_INPUTS] + inf_mask
        )
        return outputs

    def _forward(self, batch, **kwargs):
        action_mask, encoder_batch = self._split_observation(batch)
        outputs = super()._forward(encoder_batch, **kwargs)
        return self._apply_action_mask(outputs, action_mask)

    def _forward_train(self, batch, **kwargs):
        action_mask, encoder_batch = self._split_observation(batch)
        outputs = super()._forward_train(encoder_batch, **kwargs)
        return self._apply_action_mask(outputs, action_mask)

    def compute_values(self, batch, embeddings=None):
        _, encoder_batch = self._split_observation(batch)
        return super().compute_values(encoder_batch, embeddings)
