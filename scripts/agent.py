"""Stateful inference agent for a recurrent, action-masked RLlib PPO module."""

from __future__ import annotations

import os

import numpy as np
import torch
from ray.rllib.core.columns import Columns
from ray.rllib.core.rl_module.rl_module import RLModule

try:
    from simulation_env import WindowGameEnv, decode_action_index
except ImportError:
    from .simulation_env import WindowGameEnv, decode_action_index


class RLAgent:
    """Inference wrapper that retains LSTM state for one complete game."""

    def __init__(self, model_path=None, deterministic=True):
        self.model_path = self._resolve_model_path(model_path)
        self.module = RLModule.from_checkpoint(self.model_path)
        if not self.module.is_stateful():
            raise ValueError(f"Module at {self.model_path} is not recurrent.")
        self.module.eval()
        self.device = next(self.module.parameters()).device
        self.deterministic = deterministic
        self._state = None
        self.reset_game()

    @staticmethod
    def _resolve_model_path(model_path):
        if model_path:
            resolved = os.path.abspath(model_path)
            if not os.path.isdir(resolved):
                raise FileNotFoundError(f"RLlib module checkpoint not found: {resolved}")
            return resolved

        repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
        outputs_dir = os.path.join(repo_root, "outputs")
        if not os.path.isdir(outputs_dir):
            raise FileNotFoundError("No outputs directory found. Run training first.")

        run_dirs = sorted(
            os.path.join(outputs_dir, name)
            for name in os.listdir(outputs_dir)
            if os.path.isdir(os.path.join(outputs_dir, name))
        )
        for run_dir in reversed(run_dirs):
            candidate = os.path.join(run_dir, "module_final")
            if os.path.isdir(candidate):
                return candidate
        raise FileNotFoundError("No module_final checkpoint found. Run recurrent training first.")

    def reset_game(self):
        """Reset memory at the start of a new game, never between turns."""
        initial_state = self.module.get_initial_state()
        self._state = {
            key: value.detach().clone().unsqueeze(0).to(self.device)
            for key, value in initial_state.items()
        }

    def _observation_batch(self, observation):
        return {
            key: torch.from_numpy(np.asarray(value, dtype=np.float32))[
                None, None, :
            ].to(self.device)
            for key, value in observation.items()
        }

    def predict_action(self, env: WindowGameEnv):
        observation = env.get_observation()
        batch = {
            Columns.OBS: self._observation_batch(observation),
            Columns.STATE_IN: self._state,
        }
        with torch.inference_mode():
            outputs = self.module.forward_inference(batch)

        logits = outputs[Columns.ACTION_DIST_INPUTS][0, -1]
        if self.deterministic:
            action_index = int(torch.argmax(logits).item())
        else:
            action_index = int(
                torch.distributions.Categorical(logits=logits).sample().item()
            )
        self._state = {
            key: value.detach()
            for key, value in outputs[Columns.STATE_OUT].items()
        }
        return action_index, decode_action_index(action_index)


if __name__ == "__main__":
    env = WindowGameEnv(observer=False)
    agent = RLAgent()

    observation, _ = env.reset()
    agent.reset_game()
    done = False
    while not done:
        action_index, action_dict = agent.predict_action(env)
        observation, reward, terminated, truncated, info = env.step(action_index)
        done = terminated or truncated
        print(
            f"Action={action_index} {action_dict} Reward={reward} "
            f"Debug={info.get('debug', '')}"
        )

    env.close()
