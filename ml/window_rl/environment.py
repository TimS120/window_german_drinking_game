"""Single-player training environment matching Flutter's public RL contract."""

from __future__ import annotations

from dataclasses import dataclass
import random

import numpy as np

from .contract import ACTION_SIZE, COLUMNS, FEATURE_SIZE, GUESS_TYPES, ORIENTATIONS, PASS_ACTION_INDEX, ROWS

LAYOUT = ((True, True, True, True, True, False), (True, False, True, False, True, False), (True, True, True, True, True, True), (True, False, True, False, True, False), (True, True, True, True, True, False))
HANDLE = (2, 5)
CORNERS = {(0, 0), (0, 4), (4, 0), (4, 4)}
HIGHER, SAME, LOWER, IN_BETWEEN, OUTSIDE = range(5)
HORIZONTAL, VERTICAL = range(2)


@dataclass(frozen=True)
class StepInfo:
    correct: bool = False
    drinks: int = 0
    passed: bool = False
    completed: bool = False


class WindowTrainingEnv:
    """PPO environment with Flutter-compatible observations and action masks.

    UI confirmations for same-rank and wrong guesses are resolved atomically:
    neither is a choice offered to the on-device model.
    """

    def __init__(self, reward_config: dict, max_steps: int = 1000, seed: int = 42):
        self.reward_config, self.max_steps = reward_config, int(max_steps)
        self.random = random.Random(seed)
        self.reset()

    def reset(self) -> np.ndarray:
        self.deck = list(range(36))
        self.random.shuffle(self.deck)
        self.cards = [[None for _ in range(COLUMNS)] for _ in range(ROWS)]
        self.face_up = [[False for _ in range(COLUMNS)] for _ in range(ROWS)]
        for row in range(ROWS):
            for column in range(COLUMNS):
                if LAYOUT[row][column]:
                    self.cards[row][column] = self.deck.pop()
                    self.face_up[row][column] = (row, column) in CORNERS or (row, column) == HANDLE
        self.must_select_adjacent_to_handle, self.turn_can_end = True, False
        self.drinks, self.steps = 0, 0
        return self.observation()

    def observation(self) -> np.ndarray:
        values: list[float] = []
        for row in range(ROWS):
            for column in range(COLUMNS):
                slot, shown, card = LAYOUT[row][column], LAYOUT[row][column] and self.face_up[row][column], self.cards[row][column]
                values.extend((float(slot), float(shown), (card // 4) / 8.0 if shown and card is not None else -1.0))
        values.extend((float(self.must_select_adjacent_to_handle), float(self.turn_can_end), 0.0, 0.0, 1.0 / 8.0))
        result = np.asarray(values, dtype=np.float32)
        assert result.shape == (FEATURE_SIZE,)
        return result

    def action_mask(self) -> np.ndarray:
        mask = np.zeros(ACTION_SIZE, dtype=np.bool_)
        for row in range(ROWS):
            for column in range(COLUMNS):
                for orientation, guesses in self._valid_options(row, column):
                    for guess in guesses:
                        mask[self._action_index(row, column, orientation, guess)] = True
        if self.turn_can_end:
            mask[PASS_ACTION_INDEX] = True
        return mask

    def step(self, action: int) -> tuple[np.ndarray, float, bool, StepInfo]:
        mask = self.action_mask()
        if action < 0 or action >= ACTION_SIZE or not mask[action]:
            raise ValueError(f"Illegal action {action}; callers must apply the mask.")
        self.steps += 1
        if action == PASS_ACTION_INDEX:
            self.turn_can_end = False
            return self._finish(float(self.reward_config["pass"]), StepInfo(passed=True))
        row, column, orientation, guess = self._decode_action(action)
        if self._is_correct(row, column, orientation, guess):
            self.face_up[row][column], self.must_select_adjacent_to_handle, self.turn_can_end = True, False, True
            completed = self._completed()
            reward = float(self.reward_config["correct_guess"]) + (float(self.reward_config["complete_game"]) if completed else 0.0)
            return self._finish(reward, StepInfo(correct=True, completed=completed), completed)
        self.face_up[row][column] = True
        removed = self._connected_open_cards((row, column))
        penalty = len(removed)
        self.drinks += penalty
        for removed_row, removed_column in removed:
            card = self.cards[removed_row][removed_column]
            if card is not None:
                self.deck.append(card)
            self.cards[removed_row][removed_column], self.face_up[removed_row][removed_column] = None, False
        self.must_select_adjacent_to_handle, self.turn_can_end = HANDLE in removed, False
        self.random.shuffle(self.deck)
        self._redeal()
        return self._finish(penalty * float(self.reward_config["wrong_drink"]), StepInfo(drinks=penalty))

    def _finish(self, reward: float, info: StepInfo, completed: bool = False):
        return self.observation(), reward, completed or self.steps >= self.max_steps, info

    @staticmethod
    def _action_index(row: int, column: int, orientation: int, guess: int) -> int:
        return (((row * COLUMNS + column) * ORIENTATIONS + orientation) * GUESS_TYPES) + guess

    @staticmethod
    def _decode_action(action: int) -> tuple[int, int, int, int]:
        guess, action = action % GUESS_TYPES, action // GUESS_TYPES
        orientation, action = action % ORIENTATIONS, action // ORIENTATIONS
        return action // COLUMNS, action % COLUMNS, orientation, guess

    def _valid_options(self, row: int, column: int) -> list[tuple[int, tuple[int, ...]]]:
        if not LAYOUT[row][column] or self.face_up[row][column] or (self.must_select_adjacent_to_handle and (row, column) not in self._adjacent(*HANDLE)):
            return []
        horizontal = [pos for pos in self._adjacent(row, column) if pos[0] == row and self.face_up[pos[0]][pos[1]]]
        vertical = [pos for pos in self._adjacent(row, column) if pos[1] == column and self.face_up[pos[0]][pos[1]]]
        options: list[tuple[int, tuple[int, ...]]] = []
        for orientation, neighbors in ((HORIZONTAL, horizontal), (VERTICAL, vertical)):
            if len(neighbors) >= 2:
                options.append((orientation, (IN_BETWEEN, OUTSIDE)))
            elif len(neighbors) == 1:
                options.append((orientation, (HIGHER, SAME, LOWER)))
        return [option for option in options if IN_BETWEEN in option[1]] or options

    def _is_correct(self, row: int, column: int, orientation: int, guess: int) -> bool:
        neighbors = [pos for pos in self._adjacent(row, column) if self.face_up[pos[0]][pos[1]] and ((orientation == HORIZONTAL and pos[0] == row) or (orientation == VERTICAL and pos[1] == column))]
        target_rank = self.cards[row][column] // 4
        if len(neighbors) == 1:
            rank = self.cards[neighbors[0][0]][neighbors[0][1]] // 4
            return (guess == HIGHER and target_rank > rank) or (guess == SAME and target_rank == rank) or (guess == LOWER and target_rank < rank)
        ranks = [self.cards[r][c] // 4 for r, c in neighbors]
        in_between = min(ranks) <= target_rank <= max(ranks)
        return (guess == IN_BETWEEN and in_between) or (guess == OUTSIDE and not in_between)

    def _adjacent(self, row: int, column: int) -> list[tuple[int, int]]:
        return [(r, c) for r, c in ((row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1)) if 0 <= r < ROWS and 0 <= c < COLUMNS and LAYOUT[r][c]]

    def _connected_open_cards(self, start: tuple[int, int]) -> set[tuple[int, int]]:
        found, pending = set(), [start]
        while pending:
            current = pending.pop()
            if current not in found:
                found.add(current)
                pending.extend(pos for pos in self._adjacent(*current) if self.face_up[pos[0]][pos[1]] and pos not in found)
        return found

    def _redeal(self) -> None:
        for row in range(ROWS):
            for column in range(COLUMNS):
                if LAYOUT[row][column] and self.cards[row][column] is None and self.deck:
                    self.cards[row][column] = self.deck.pop()
                    self.face_up[row][column] = (row, column) in CORNERS or (row, column) == HANDLE

    def _completed(self) -> bool:
        return all(not LAYOUT[row][column] or self.face_up[row][column] for row in range(ROWS) for column in range(COLUMNS))
