"""
Platform-independent game engine for the Window drinking game.
"""

from __future__ import annotations

import random
from dataclasses import dataclass

try:
    from config import CORNER_POSITIONS, HANDLE_POSITION, WINDOW_LAYOUT
    from utils import adjacent_positions, create_deck, get_rank_index, is_between
except ImportError:
    from .config import CORNER_POSITIONS, HANDLE_POSITION, WINDOW_LAYOUT
    from .utils import adjacent_positions, create_deck, get_rank_index, is_between


@dataclass(frozen=True)
class GuessOption:
    type: str
    guess_options: tuple[str, ...]
    neighbors: tuple | tuple[tuple[int, int], tuple[int, int]]
    orientation: str


class CoreWindowGame:
    """
    Pure game-state engine without UI dependencies.
    """

    def __init__(self, players: list[str], rng_seed: int | None = None):
        self.players = players or ["Player1"]
        self.rng = random.Random(rng_seed)
        self.card_grid: list[list[int | None]] = []
        self.face_up: list[list[bool]] = []
        self.pending_removals: set[tuple[int, int]] = set()
        self.pending_penalty = 0
        self.must_select_adjacent_to_handle = True
        self.turn_can_end = False
        self.init_stats()
        self.reset_game()

    def init_stats(self):
        self.current_player_idx = 0
        self.drink_count = {p: 0 for p in self.players}
        self.correct_guess_count = {p: 0 for p in self.players}
        self.wrong_guess_count = {p: 0 for p in self.players}
        self.player_changed_cards = {p: 0 for p in self.players}
        self.player_turns = {p: 0 for p in self.players}

    def init_grids(self):
        self.card_grid = []
        self.face_up = []
        for row in WINDOW_LAYOUT:
            cards = []
            open_cards = []
            for cell in row:
                if cell:
                    cards.append(None)
                    open_cards.append(False)
                else:
                    cards.append(None)
                    open_cards.append(False)
            self.card_grid.append(cards)
            self.face_up.append(open_cards)

    def current_player(self):
        return self.players[self.current_player_idx]

    def next_player(self):
        self.current_player_idx = (self.current_player_idx + 1) % len(self.players)
        self.turn_start_face_up = self.count_face_up_cards()
        self.player_turns[self.current_player()] += 1
        self.turn_can_end = False

    def end_turn(self):
        current_player = self.current_player()
        delta = self.count_face_up_cards() - self.turn_start_face_up
        self.player_changed_cards[current_player] += delta
        self.next_player()

    def count_face_up_cards(self):
        count = 0
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c] and self.face_up[r][c]:
                    count += 1
        return count

    def deal_initial_cards(self):
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c]:
                    card = self.deck.pop() if self.deck else None
                    self.card_grid[r][c] = card
                    self.face_up[r][c] = bool(
                        card is not None and ((r, c) in CORNER_POSITIONS or (r, c) == HANDLE_POSITION)
                    )

    def redeal_spots(self):
        new_cards = []
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c] and self.card_grid[r][c] is None and self.deck:
                    card = self.deck.pop()
                    self.card_grid[r][c] = card
                    self.face_up[r][c] = (r, c) in CORNER_POSITIONS or (r, c) == HANDLE_POSITION
                    new_cards.append((r, c))
        return new_cards

    def reset_game(self):
        self.deck = create_deck()
        self.rng.shuffle(self.deck)
        self.init_grids()
        self.deal_initial_cards()
        self.pending_removals = set()
        self.pending_penalty = 0
        self.must_select_adjacent_to_handle = True
        self.turn_can_end = False
        self.turn_start_face_up = self.count_face_up_cards()
        self.player_turns[self.current_player()] += 1

    def get_valid_options_for_card(self, r, c):
        options = []
        neighbors = []
        for nr, nc in adjacent_positions((r, c)):
            if self.face_up[nr][nc]:
                if nr == r - 1 and nc == c:
                    direction = "north"
                elif nr == r + 1 and nc == c:
                    direction = "south"
                elif nr == r and nc == c - 1:
                    direction = "west"
                elif nr == r and nc == c + 1:
                    direction = "east"
                else:
                    direction = ""
                neighbors.append(((nr, nc), direction))

        horizontal = [n for n, d in neighbors if d in ("east", "west")]
        vertical = [n for n, d in neighbors if d in ("north", "south")]

        if len(horizontal) >= 2:
            left = min(horizontal)
            right = max(horizontal)
            options.append(
                GuessOption(
                    type="in-between",
                    guess_options=("in-between", "outside"),
                    neighbors=(left, right),
                    orientation="horizontal",
                )
            )
        elif len(horizontal) == 1:
            options.append(
                GuessOption(
                    type="higher-lower",
                    guess_options=("higher", "same", "lower"),
                    neighbors=horizontal[0],
                    orientation="horizontal",
                )
            )

        if len(vertical) >= 2:
            top = min(vertical)
            bottom = max(vertical)
            options.append(
                GuessOption(
                    type="in-between",
                    guess_options=("in-between", "outside"),
                    neighbors=(top, bottom),
                    orientation="vertical",
                )
            )
        elif len(vertical) == 1:
            options.append(
                GuessOption(
                    type="higher-lower",
                    guess_options=("higher", "same", "lower"),
                    neighbors=vertical[0],
                    orientation="vertical",
                )
            )

        in_between_opts = [opt for opt in options if opt.type == "in-between"]
        return in_between_opts if in_between_opts else options

    def collect_connected_open_cards(self, start_pos):
        visited = set()
        stack = [start_pos]
        while stack:
            current = stack.pop()
            if current in visited:
                continue
            visited.add(current)
            for neighbor in adjacent_positions(current):
                nr, nc = neighbor
                if self.face_up[nr][nc] and neighbor not in visited:
                    stack.append(neighbor)
        return visited

    def resolve_higher_same_lower(self, r, c, neighbor, guess):
        card_id = self.card_grid[r][c]
        neighbor_id = self.card_grid[neighbor[0]][neighbor[1]]
        card_rank = get_rank_index(card_id)
        neighbor_rank = get_rank_index(neighbor_id)
        is_correct = (
            (guess == "higher" and card_rank > neighbor_rank)
            or (guess == "lower" and card_rank < neighbor_rank)
            or (guess == "same" and card_rank == neighbor_rank)
        )
        if is_correct:
            if guess == "same":
                current_player = self.current_player()
                for player in self.players:
                    if player != current_player:
                        self.drink_count[player] += 1
            self.finish_guess(r, c, True)
        else:
            self.finish_guess(r, c, False)

    def resolve_in_between(self, r, c, n1, n2, guess_in):
        card_id = self.card_grid[r][c]
        n1_id = self.card_grid[n1[0]][n1[1]]
        n2_id = self.card_grid[n2[0]][n2[1]]
        is_correct = is_between(card_id, n1_id, n2_id) == guess_in
        self.finish_guess(r, c, is_correct)

    def finish_guess(self, r, c, is_correct):
        current_player = self.current_player()
        if is_correct:
            self.face_up[r][c] = True
            self.correct_guess_count[current_player] += 1
            self.turn_can_end = True
            self.pending_removals = set()
            self.pending_penalty = 0
        else:
            connected = self.collect_connected_open_cards((r, c))
            total_removed = set(connected)
            total_removed.add((r, c))
            penalty = len(total_removed)
            self.pending_removals = total_removed
            self.pending_penalty = penalty
            self.wrong_guess_count[current_player] += 1
            self.drink_count[current_player] += penalty
            self.turn_can_end = False

    def confirm_removals(self):
        for rr, cc in self.pending_removals:
            cid = self.card_grid[rr][cc]
            if cid is not None:
                self.deck.append(cid)
            self.card_grid[rr][cc] = None
            self.face_up[rr][cc] = False

        self.must_select_adjacent_to_handle = HANDLE_POSITION in self.pending_removals
        self.pending_removals = set()
        self.pending_penalty = 0
        self.rng.shuffle(self.deck)
        self.redeal_spots()

    def check_game_end(self):
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c] and not self.face_up[r][c]:
                    return False
        return True

    def simulate_action(self, position, guess, orientation=None):
        r, c = position
        if not WINDOW_LAYOUT[r][c]:
            return {"reward": -10, "done": False, "debug": "Invalid position: not a card slot."}
        if self.face_up[r][c]:
            return {"reward": -10, "done": False, "debug": "Card already face-up."}
        if self.must_select_adjacent_to_handle and (r, c) not in adjacent_positions(HANDLE_POSITION):
            return {"reward": -10, "done": False, "debug": "Must select card adjacent to handle."}

        options = self.get_valid_options_for_card(r, c)
        if not options:
            return {"reward": -2, "done": False, "debug": "No valid guess options for this card."}

        selected_option = None
        if orientation:
            for opt in options:
                if opt.orientation == orientation:
                    selected_option = opt
                    break
        else:
            selected_option = options[0]

        if selected_option is None:
            return {"reward": -2, "done": False, "debug": "No valid option for given orientation."}

        if guess not in selected_option.guess_options:
            return {"reward": -2, "done": False, "debug": "Invalid guess for selected option."}

        if selected_option.type == "higher-lower":
            self.resolve_higher_same_lower(r, c, selected_option.neighbors, guess)
        elif selected_option.type == "in-between":
            neighbor1, neighbor2 = selected_option.neighbors
            self.resolve_in_between(r, c, neighbor1, neighbor2, guess == "in-between")
        else:
            return {"reward": -2, "done": False, "debug": "Unknown option type."}

        was_wrong = bool(self.pending_removals)
        penalty = self.pending_penalty if was_wrong else 0
        if was_wrong:
            self.confirm_removals()
            reward = -penalty
            debug_info = "Wrong guess."
        else:
            reward = 5
            debug_info = "Correct guess."

        done = self.check_game_end()
        if done and not was_wrong:
            reward = 200
        return {"reward": reward, "done": done, "debug": debug_info}
