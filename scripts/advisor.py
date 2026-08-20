"""Stateful, non-executing move advisor for the desktop game."""

from __future__ import annotations

import copy
import os

if __package__:
    from .agent import RLAgent
    from .simulation_env import build_public_observation
else:
    from agent import RLAgent
    from simulation_env import build_public_observation



def resolve_advisor_model_path(model_path):
    """Resolve configured module paths relative to the repository root."""
    if not model_path:
        return None
    if os.path.isabs(model_path):
        return model_path
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    return os.path.join(repo_root, model_path)


class AdvisorSession:
    """Keep model memory synchronized with actual, publicly observed moves."""

    def __init__(self, model_path=None, deterministic=True, agent=None):
        resolved_path = resolve_advisor_model_path(model_path)
        self.agent = agent or RLAgent(
            model_path=resolved_path,
            deterministic=deterministic,
        )
        self.public_history = []
        self._suggestion = None

    def reset(self, game):
        """Start a new history and prepare the initial cached suggestion."""
        self.public_history = []
        self.agent.reset_game()
        self._refresh_suggestion(game, event=None)

    def observe_transition(self, game, event):
        """Commit one actual user move and prepare advice for the resulting state."""
        if event is None:
            raise ValueError("A completed public transition event is required.")
        self.public_history.append(copy.deepcopy(event))
        if game.check_game_end():
            self._suggestion = None
            return
        self._refresh_suggestion(game, event=event)

    def _refresh_suggestion(self, game, event):
        observation = build_public_observation(game, event)
        action_index, action = self.agent.predict_observation(observation)
        options = game.get_valid_options_for_card(*action["position"])
        selected_option = next(
            (
                option
                for option in options
                if action["guess"] in option.guess_options
                and (
                    action.get("orientation") is None
                    or option.orientation == action["orientation"]
                )
            ),
            None,
        )
        orientation = (
            selected_option.orientation
            if selected_option is not None
            else action.get("orientation")
        )
        neighbors = selected_option.neighbors if selected_option is not None else ()
        if neighbors and isinstance(neighbors[0], int):
            neighbors = (neighbors,)
        self._suggestion = {
            "action_index": action_index,
            "position": tuple(action["position"]),
            "guess": action["guess"],
            "orientation": orientation,
            "comparison_positions": tuple(tuple(position) for position in neighbors),
            "history_length": len(self.public_history),
        }

    def current_suggestion(self):
        """Return cached advice without advancing recurrent memory."""
        return copy.deepcopy(self._suggestion)


def format_suggestion(suggestion):
    if suggestion is None:
        return "No model suggestion is currently available."
    row, column = suggestion["position"]
    guess = suggestion["guess"].replace("-", " ").title()
    orientation = suggestion.get("orientation")
    comparison = f" ({orientation})" if orientation else ""
    neighbors = ", ".join(
        f"row {r + 1}, column {c + 1}"
        for r, c in suggestion.get("comparison_positions", ())
    )
    neighbor_text = f"; compare with {neighbors}" if neighbors else ""
    return (
        f"Suggested move: row {row + 1}, column {column + 1} — "
        f"{guess}{comparison}{neighbor_text}."
    )
