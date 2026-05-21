"""Gymnasium environment backed by the platform-independent core engine."""

import random
from typing import Any

import gymnasium as gym
import numpy as np
import torch
from gymnasium import spaces

try:
    from core_game import CoreWindowGame
    from config import WINDOW_LAYOUT
    from utils import get_rank_index
except ImportError:
    from .core_game import CoreWindowGame
    from .config import WINDOW_LAYOUT
    from .utils import get_rank_index


def build_global_action_space() -> list[dict[str, Any]]:
    """Build the fixed global action space for all valid board slots."""
    actions: list[dict[str, Any]] = []
    for r in range(len(WINDOW_LAYOUT)):
        for c in range(len(WINDOW_LAYOUT[r])):
            if WINDOW_LAYOUT[r][c]:
                for guess in ["higher", "same", "lower"]:
                    actions.append({"position": (r, c), "guess": guess, "orientation": None})
                for guess in ["in-between", "outside"]:
                    for orientation in ["horizontal", "vertical"]:
                        actions.append({"position": (r, c), "guess": guess, "orientation": orientation})
    return actions


GLOBAL_ACTION_SPACE = build_global_action_space()
NUM_ACTIONS = len(GLOBAL_ACTION_SPACE)


def decode_action_index(action_index: int) -> dict[str, Any]:
    """Decode an action index into its action dict."""
    if not 0 <= action_index < NUM_ACTIONS:
        raise IndexError(f"Action index {action_index} out of range [0..{NUM_ACTIONS - 1}]")
    return GLOBAL_ACTION_SPACE[action_index]


def action_to_mask_key(action: dict[str, Any]) -> str:
    guess = action["guess"]
    if guess in ["in-between", "outside"]:
        suffix = "h" if action.get("orientation") == "horizontal" else "v"
        return f"{guess.replace('-', '_')}_{suffix}"
    return guess


class WindowGameEnv(gym.Env):
    """Gymnasium-compatible environment with invalid action masking."""

    metadata = {"render_modes": ["human", None]}

    def __init__(self, players=None, observer=False, max_steps=1000, reward_config=None):
        super().__init__()
        players = players or ["Alice", "Bob", "Charlie"]
        self.observer = observer
        self.max_steps = max_steps
        self.reward_config = reward_config or {
            "correct_guess": 1.0,
            "wrong_guess": -1.0,
            "invalid_action": -1.0,
            "win_bonus": 0.0,
        }

        self.game = CoreWindowGame(players=players)
        self.global_action_space = GLOBAL_ACTION_SPACE
        self._step_count = 0

        self.action_space = spaces.Discrete(NUM_ACTIONS)
        self.observation_space = spaces.Box(low=0.0, high=1.0, shape=(300,), dtype=np.float32)

    def reset(self, *, seed=None, options=None):
        super().reset(seed=seed)
        if seed is not None:
            random.seed(seed)
            np.random.seed(seed)
            torch.manual_seed(seed)

        self.game.reset_game()
        self._step_count = 0
        state = self._get_state()
        obs = self._build_observation(state)
        info = {"debug": "reset"}
        return obs, info

    def step(self, action):
        self._step_count += 1
        action_idx = int(action)
        action_dict = decode_action_index(action_idx)

        result = self.game.simulate_action(
            action_dict["position"], action_dict["guess"], action_dict.get("orientation")
        )

        state = self._get_state()
        obs = self._build_observation(state)

        debug = result["debug"]
        terminated = bool(result["done"])
        truncated = self._step_count >= self.max_steps and not terminated

        if "Correct guess" in debug:
            reward = float(self.reward_config["correct_guess"])
        elif "Wrong guess" in debug:
            reward = float(self.reward_config["wrong_guess"])
        else:
            reward = float(self.reward_config["invalid_action"])

        if terminated:
            reward += float(self.reward_config.get("win_bonus", 0.0))

        info = {
            "debug": debug,
            "raw_reward": result["reward"],
            "action": action_dict,
            "step": self._step_count,
        }
        return obs, reward, terminated, truncated, info

    def step_global(self, action_index: int):
        """Backward-compatible helper used by older scripts."""
        obs, reward, terminated, truncated, info = self.step(action_index)
        state = self._get_state()
        done = terminated or truncated
        return state, reward, done, info.get("debug", "")

    def action_masks(self):
        """Return bool mask with True for currently valid actions."""
        state = self._get_state()
        vm = state["valid_masks"]
        mask = np.zeros(NUM_ACTIONS, dtype=bool)
        for idx, action in enumerate(self.global_action_space):
            key = action_to_mask_key(action)
            r, c = action["position"]
            mask[idx] = bool(vm[key][r, c])
        return mask

    def _get_state(self):
        state = {
            "card_grid": self.game.card_grid,
            "face_up": self.game.face_up,
            "current_player": self.game.current_player(),
            "deck_size": len(self.game.deck),
        }

        vm = {
            k: torch.zeros((5, 6), dtype=torch.bool)
            for k in [
                "higher",
                "same",
                "lower",
                "in_between_h",
                "outside_h",
                "in_between_v",
                "outside_v",
            ]
        }

        for r in range(5):
            for c in range(6):
                if not WINDOW_LAYOUT[r][c] or state["face_up"][r][c]:
                    continue
                opts = self.game.get_valid_options_for_card(r, c)
                for opt in opts:
                    for guess in opt.guess_options:
                        key = guess
                        if guess in ["in-between", "outside"]:
                            ori = opt.orientation[0]
                            key = f"{guess.replace('-', '_')}_{'h' if ori == 'h' else 'v'}"
                        vm[key][r, c] = True

        state["valid_masks"] = vm
        cards = torch.full((5, 6), -1, dtype=torch.int)
        for r in range(5):
            for c in range(6):
                if state["card_grid"][r][c] is None:
                    cards[r, c] = -1
                elif not state["face_up"][r][c]:
                    cards[r, c] = -2
                else:
                    cards[r, c] = get_rank_index(state["card_grid"][r][c])
        state["cards"] = cards
        return state

    def _build_observation(self, state):
        return flatten_state(state).numpy().astype(np.float32).reshape(-1)

    def get_valid_actions(self):
        valid_actions = []
        state = self._get_state()
        for idx, action in enumerate(self.global_action_space):
            key = action_to_mask_key(action)
            r, c = action["position"]
            if state["valid_masks"][key][r, c]:
                valid_actions.append((idx, action))
        return valid_actions

    def render(self):
        return None

    def close(self):
        return None


def get_human_action(env):
    actions = env.global_action_space
    print("Global Action Space:")
    for i, action in enumerate(actions):
        pos = action["position"]
        guess = action["guess"]
        orient = action.get("orientation", "N/A")
        print(f"{i}: Position: {pos}, Guess: {guess}, Orientation: {orient}")
    try:
        choice = int(input("Enter the global action index: "))
        if 0 <= choice < len(actions):
            return actions[choice]
        print("Invalid selection.")
        return None
    except ValueError:
        print("Please enter a valid number.")
        return None


def flatten_state(state):
    """One-hot-ish encoding of the environment state as (10, 5, 6)."""
    cards = state["cards"]
    vm = state["valid_masks"]

    empty = (cards == -1).float()
    facedown = (cards == -2).float()

    rank_norm = torch.zeros_like(cards, dtype=torch.float32)
    faceup = cards.ge(0)
    rank_norm[faceup] = cards[faceup].float() / 8.0

    channels = [empty, facedown, rank_norm]
    for k in ["higher", "same", "lower", "in_between_h", "outside_h", "in_between_v", "outside_v"]:
        channels.append(vm[k].float())

    return torch.stack(channels, dim=0)


if __name__ == "__main__":
    mode = input("Select mode: [C]onsole Human or [G]lobal AI action? ").strip().upper()
    env = WindowGameEnv(observer=False)
    obs, _ = env.reset()
    print("Initial observation shape:", obs.shape)

    done = False
    while not done:
        if mode == "C":
            action = get_human_action(env)
            if action is None:
                print("No valid action selected, exiting loop.")
                break
            step_action = env.global_action_space.index(action)
        else:
            mask = env.action_masks()
            valid_idxs = np.flatnonzero(mask)
            if valid_idxs.size == 0:
                print("No valid actions available.")
                break
            step_action = int(valid_idxs[0])

        _, reward, terminated, truncated, info = env.step(step_action)
        done = terminated or truncated
        print(f"Reward: {reward}, Done: {done}, Debug: {info.get('debug', '')}")

    env.close()
