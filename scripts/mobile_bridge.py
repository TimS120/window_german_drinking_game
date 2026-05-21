"""
Small JSON-friendly bridge around CoreWindowGame for Android integration.
"""

from __future__ import annotations

try:
    from core_game import CoreWindowGame
    from config import WINDOW_LAYOUT
except ImportError:
    from .core_game import CoreWindowGame
    from .config import WINDOW_LAYOUT


class MobileGameBridge:
    """
    Exposes game lifecycle and actions in a serialization-friendly format.
    """

    def __init__(self, players: list[str]):
        self.game = CoreWindowGame(players=players)

    def reset(self):
        self.game.reset_game()
        return self.get_state()

    def act(self, row: int, col: int, guess: str, orientation: str | None = None):
        result = self.game.simulate_action((row, col), guess, orientation)
        return {
            "result": result,
            "state": self.get_state(),
        }

    def get_state(self):
        options = {}
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if not WINDOW_LAYOUT[r][c] or self.game.face_up[r][c]:
                    continue
                key = f"{r},{c}"
                options[key] = [
                    {
                        "type": opt.type,
                        "guess_options": list(opt.guess_options),
                        "orientation": opt.orientation,
                    }
                    for opt in self.game.get_valid_options_for_card(r, c)
                ]

        return {
            "card_grid": self.game.card_grid,
            "face_up": self.game.face_up,
            "deck_size": len(self.game.deck),
            "current_player": self.game.current_player(),
            "must_select_adjacent_to_handle": self.game.must_select_adjacent_to_handle,
            "turn_can_end": self.game.turn_can_end,
            "valid_options": options,
            "stats": {
                "drink_count": self.game.drink_count,
                "correct_guess_count": self.game.correct_guess_count,
                "wrong_guess_count": self.game.wrong_guess_count,
                "player_changed_cards": self.game.player_changed_cards,
                "player_turns": self.game.player_turns,
            },
            "is_game_over": self.game.check_game_end(),
        }
