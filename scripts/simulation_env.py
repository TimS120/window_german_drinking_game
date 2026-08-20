"""Partially observable Gymnasium environment for recurrent RL training."""

from typing import Any

import gymnasium as gym
import numpy as np
from gymnasium import spaces

try:
    from core_game import CoreWindowGame
    from config import HANDLE_POSITION, NUM_CARDS, RANKS, WINDOW_LAYOUT
    from utils import adjacent_positions, get_rank_index
except ImportError:
    from .core_game import CoreWindowGame
    from .config import HANDLE_POSITION, NUM_CARDS, RANKS, WINDOW_LAYOUT
    from .utils import adjacent_positions, get_rank_index


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
BOARD_ROWS = len(WINDOW_LAYOUT)
BOARD_COLS = len(WINDOW_LAYOUT[0])
NUM_RANKS = len(RANKS)
NUM_BOARD_POSITIONS = sum(bool(cell) for row in WINDOW_LAYOUT for cell in row)

# Current board: layout, face-down, face-up, and one channel per visible rank.
BOARD_CHANNELS = 3 + NUM_RANKS
# Previous public event: action, removed and redealt positions, plus ranks that
# were publicly visible during that event.
EVENT_CHANNELS = 3 + NUM_RANKS
GLOBAL_EVENT_FEATURES = 5 + 3 + 3 + 7
OBSERVATION_SIZE = (
    (BOARD_CHANNELS + EVENT_CHANNELS) * BOARD_ROWS * BOARD_COLS
    + GLOBAL_EVENT_FEATURES
)


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


def build_public_state(game):
    """Build the visible state shared by training and real-game advice."""
    cards = np.full((BOARD_ROWS, BOARD_COLS), -1, dtype=np.int8)
    for r in range(BOARD_ROWS):
        for c in range(BOARD_COLS):
            if game.card_grid[r][c] is None:
                cards[r, c] = -1
            elif not game.face_up[r][c]:
                cards[r, c] = -2
            else:
                cards[r, c] = get_rank_index(game.card_grid[r][c])
    return {
        "cards": cards,
        "face_up": game.face_up,
        "current_player": game.current_player(),
        "deck_size": len(game.deck),
    }


def build_action_mask(game):
    """Build the hard legality mask from public board geometry and game rules."""
    mask = np.zeros(NUM_ACTIONS, dtype=bool)
    for idx, action in enumerate(GLOBAL_ACTION_SPACE):
        r, c = action["position"]
        if not WINDOW_LAYOUT[r][c] or game.face_up[r][c]:
            continue
        if (
            game.must_select_adjacent_to_handle
            and (r, c) not in adjacent_positions(HANDLE_POSITION)
        ):
            continue
        key = action_to_mask_key(action)
        for option in game.get_valid_options_for_card(r, c):
            for guess in option.guess_options:
                option_key = guess
                if guess in ["in-between", "outside"]:
                    suffix = "h" if option.orientation == "horizontal" else "v"
                    option_key = f"{guess.replace('-', '_')}_{suffix}"
                if option_key == key:
                    mask[idx] = True
    return mask


def build_public_observation(game, event=None):
    """Encode only human-visible state plus legal actions for advisor inference."""
    state = build_public_state(game)
    return {
        "observations": encode_public_observation(state, event, game),
        "action_mask": build_action_mask(game).astype(np.float32),
    }


class WindowGameEnv(gym.Env):
    """POMDP environment exposing only information available to a player.

    The observation contains the visible board and the last public transition.
    It contains no inferred card probabilities and no hidden card identities.
    """

    metadata = {"render_modes": ["human", None]}

    def __init__(
        self,
        players=None,
        observer=False,
        max_steps=1000,
        reward_config=None,
        rng_seed=None,
    ):
        super().__init__()
        # RLlib passes its EnvContext as the first positional argument. Keep
        # direct Gymnasium construction convenient as well.
        if isinstance(players, dict):
            env_config = players
            players = env_config.get("players")
            observer = env_config.get("observer", observer)
            max_steps = env_config.get("max_steps", max_steps)
            reward_config = env_config.get("reward_config", reward_config)
            rng_seed = env_config.get("rng_seed", rng_seed)
        players = players or ["Alice", "Bob", "Charlie"]
        self.observer = observer
        self.max_steps = max_steps
        self.reward_config = reward_config or {
            "correct_guess": 1.0,
            "wrong_guess": -1.0,
            "invalid_action": -1.0,
            "win_bonus": 0.0,
        }

        self.game = CoreWindowGame(players=players, rng_seed=rng_seed)
        self.global_action_space = GLOBAL_ACTION_SPACE
        self._step_count = 0
        self._last_event = None
        self._episode_correct = 0
        self._episode_wrong = 0
        self._episode_wrong_penalty = 0
        self._episode_terminated = False
        self._episode_truncated = False
        self._episode_max_face_up = 0
        self._last_step_reward = 0.0
        self._last_step_correct = 0.0

        self.action_space = spaces.Discrete(NUM_ACTIONS)
        self.observation_space = spaces.Dict(
            {
                "observations": spaces.Box(
                    low=0.0,
                    high=1.0,
                    shape=(OBSERVATION_SIZE,),
                    dtype=np.float32,
                ),
                "action_mask": spaces.Box(
                    low=0.0,
                    high=1.0,
                    shape=(NUM_ACTIONS,),
                    dtype=np.float32,
                ),
            }
        )

    def reset(self, *, seed=None, options=None):
        super().reset(seed=seed)
        if seed is not None:
            self.game.rng.seed(seed)

        self.game.reset_game()
        self._step_count = 0
        self._last_event = None
        self._episode_correct = 0
        self._episode_wrong = 0
        self._episode_wrong_penalty = 0
        self._episode_terminated = False
        self._episode_truncated = False
        self._episode_max_face_up = self.game.count_face_up_cards()
        self._last_step_reward = 0.0
        self._last_step_correct = 0.0
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
        self._last_event = result.get("event")
        if self._last_event is not None:
            if self._last_event["correct"]:
                self._episode_correct += 1
            else:
                self._episode_wrong += 1
                self._episode_wrong_penalty += int(self._last_event["penalty"])

        state = self._get_state()
        obs = self._build_observation(state)

        debug = result["debug"]
        terminated = bool(result["done"])
        truncated = self._step_count >= self.max_steps and not terminated

        if "Correct guess" in debug:
            reward = float(self.reward_config["correct_guess"])
        elif "Wrong guess" in debug:
            # Match the public drinking penalty instead of treating removal of
            # two cards and removal of a large component as equally harmful.
            penalty = max(1, int(result.get("event", {}).get("penalty", 1)))
            reward = float(self.reward_config["wrong_guess"]) * penalty
        else:
            reward = float(self.reward_config["invalid_action"])

        if terminated:
            reward += float(self.reward_config.get("win_bonus", 0.0))

        self._episode_terminated = terminated
        self._episode_truncated = truncated
        self._episode_max_face_up = max(
            self._episode_max_face_up,
            self.game.count_face_up_cards(),
        )
        self._last_step_reward = reward
        self._last_step_correct = float(
            self._last_event is not None and self._last_event["correct"]
        )

        info = {
            "debug": debug,
            "raw_reward": result["reward"],
            "action": action_dict,
            "step": self._step_count,
            "event": self._last_event,
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
        return build_action_mask(self.game)

    def _get_state(self):
        state = {
            "card_grid": self.game.card_grid,
            "face_up": self.game.face_up,
            "current_player": self.game.current_player(),
            "deck_size": len(self.game.deck),
        }

        vm = {
            k: np.zeros((BOARD_ROWS, BOARD_COLS), dtype=bool)
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
                if (
                    self.game.must_select_adjacent_to_handle
                    and (r, c) not in adjacent_positions(HANDLE_POSITION)
                ):
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
        cards = np.full((BOARD_ROWS, BOARD_COLS), -1, dtype=np.int8)
        for r in range(BOARD_ROWS):
            for c in range(BOARD_COLS):
                if state["card_grid"][r][c] is None:
                    cards[r, c] = -1
                elif not state["face_up"][r][c]:
                    cards[r, c] = -2
                else:
                    cards[r, c] = get_rank_index(state["card_grid"][r][c])
        state["cards"] = cards
        return state

    def _build_observation(self, state):
        return build_public_observation(self.game, self._last_event)

    def get_observation(self):
        """Return the current public observation without changing the game."""
        return self._build_observation(self._get_state())

    def get_episode_metrics(self):
        """Return game-level measurements for local training progress reports."""
        guesses = self._episode_correct + self._episode_wrong
        return {
            "accuracy": self._episode_correct / guesses if guesses else 0.0,
            "mean_wrong_penalty": (
                self._episode_wrong_penalty / self._episode_wrong
                if self._episode_wrong
                else 0.0
            ),
            "completion_rate": float(self._episode_terminated),
            "truncation_rate": float(self._episode_truncated),
            "face_up_fraction": self.game.count_face_up_cards() / NUM_BOARD_POSITIONS,
            "max_face_up_fraction": self._episode_max_face_up / NUM_BOARD_POSITIONS,
            "correct_guesses": float(self._episode_correct),
            "wrong_guesses": float(self._episode_wrong),
            "episode_steps": float(self._step_count),
        }

    def get_step_metrics(self):
        """Return metrics available after every action, including partial episodes."""
        return {
            "reward": float(self._last_step_reward),
            "accuracy": float(self._last_step_correct),
            "face_up_fraction": self.game.count_face_up_cards()
            / NUM_BOARD_POSITIONS,
        }

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


def encode_public_observation(state, event, game):
    """Encode visible board data and one raw public transition.

    No probability, deck composition estimate, or face-down card identity is
    calculated here. Temporal interpretation is left to the recurrent policy.
    """
    cards = state["cards"]
    board = np.zeros((BOARD_CHANNELS, BOARD_ROWS, BOARD_COLS), dtype=np.float32)
    board[0] = np.asarray(WINDOW_LAYOUT, dtype=bool).astype(np.float32)
    board[1] = (cards == -2).astype(np.float32)
    face_up = cards >= 0
    board[2] = face_up.astype(np.float32)
    for rank in range(NUM_RANKS):
        board[3 + rank] = (cards == rank).astype(np.float32)

    public_event = np.zeros(
        (EVENT_CHANNELS, BOARD_ROWS, BOARD_COLS), dtype=np.float32
    )
    global_event = np.zeros(GLOBAL_EVENT_FEATURES, dtype=np.float32)

    if event is not None:
        r, c = event["position"]
        public_event[0, r, c] = 1.0
        for removed in event["removed_cards"]:
            rr, cc = removed["position"]
            public_event[1, rr, cc] = 1.0
            public_event[3 + removed["rank"], rr, cc] = 1.0
        for rr, cc in event["redealt_positions"]:
            public_event[2, rr, cc] = 1.0

        guess_index = {
            "higher": 0,
            "same": 1,
            "lower": 2,
            "in-between": 3,
            "outside": 4,
        }[event["guess"]]
        global_event[guess_index] = 1.0

        orientation_index = {"horizontal": 0, "vertical": 1}.get(
            event["orientation"], 2
        )
        global_event[5 + orientation_index] = 1.0
        global_event[8 + (0 if event["correct"] else 1)] = 1.0
        global_event[10] = 1.0
        global_event[11] = min(
            float(event["penalty"]) / NUM_BOARD_POSITIONS, 1.0
        )

    global_event[12] = float(game.must_select_adjacent_to_handle)
    global_event[13] = float(game.turn_can_end)
    global_event[14] = float(len(game.deck)) / float(NUM_CARDS)
    player_denominator = max(1, len(game.players) - 1)
    global_event[15] = float(game.current_player_idx) / float(player_denominator)
    global_event[16] = min(float(len(game.players)) / 100.0, 1.0)
    global_event[17] = min(
        float(game.pending_penalty) / NUM_BOARD_POSITIONS, 1.0
    )

    observation = np.concatenate(
        [board.reshape(-1), public_event.reshape(-1), global_event]
    ).astype(np.float32)
    if observation.shape != (OBSERVATION_SIZE,):
        raise RuntimeError(
            f"Observation shape {observation.shape} does not match {(OBSERVATION_SIZE,)}"
        )
    return observation


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
