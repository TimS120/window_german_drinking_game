"""Batched, tensor-only Window simulator for high-throughput PPO rollouts.

The public :class:`WindowTrainingEnv` remains the readable reference model.
This implementation holds every mutable game state on one torch device.  In
particular, no observation, mask, action, reward, or state crosses the PCIe
boundary while training on CUDA.
"""

from __future__ import annotations

import torch

from .contract import ACTION_SIZE, ACTION_FEATURE_SIZE, BOARD_FEATURE_SIZE, COLUMNS, FEATURE_SIZE, GUESS_TYPES, HISTORY_FEATURE_SIZE, HISTORY_LENGTH, MAX_HISTORY_LENGTH, ORIENTATIONS, OUTCOME_FEATURE_SIZE, PASS_ACTION_INDEX, PLAYER_COUNT, REMOVED_FEATURE_SIZE, ROWS
from .environment import CORNERS, HANDLE, LAYOUT


HIGHER, SAME, LOWER, IN_BETWEEN, OUTSIDE = range(5)
HORIZONTAL, VERTICAL = range(2)


class BatchedWindowEnv:
    """Many independent Window games stored in batched torch tensors."""

    def __init__(self, reward_config: dict, num_envs: int, max_steps: int, device: torch.device, seed: int, history_length: int = HISTORY_LENGTH, player_count: int = 4) -> None:
        if num_envs < 1:
            raise ValueError("num_envs must be at least 1")
        if not 1 <= history_length <= MAX_HISTORY_LENGTH:
            raise ValueError(f"history_length must be between 1 and {MAX_HISTORY_LENGTH}")
        if player_count != PLAYER_COUNT:
            raise ValueError(f"This training environment is fixed to {PLAYER_COUNT} players.")
        self.device = device
        self.num_envs = int(num_envs)
        self.max_steps = int(max_steps)
        self.history_length = int(history_length)
        self.player_count = int(player_count)
        self.correct_reward = float(reward_config["correct_guess"])
        self.wrong_reward = float(reward_config["wrong_drink"])
        self.pass_reward = float(reward_config["pass"])
        self.complete_reward = float(reward_config["complete_game"])
        self.generator = torch.Generator(device=device)
        self.generator.manual_seed(seed)

        self.layout = torch.tensor(LAYOUT, dtype=torch.bool, device=device)
        self.corner_or_handle = torch.zeros((ROWS, COLUMNS), dtype=torch.bool, device=device)
        for row, column in (*CORNERS, HANDLE):
            self.corner_or_handle[row, column] = True
        self.handle_adjacency = torch.zeros((ROWS, COLUMNS), dtype=torch.bool, device=device)
        for row, column in ((1, 5), (3, 5), (2, 4)):
            self.handle_adjacency[row, column] = True
        self.row_index = torch.arange(ROWS, device=device).view(ROWS, 1).expand(ROWS, COLUMNS)
        self.column_index = torch.arange(COLUMNS, device=device).view(1, COLUMNS).expand(ROWS, COLUMNS)
        self.cards = torch.empty((self.num_envs, ROWS, COLUMNS), dtype=torch.long, device=device)
        self.face_up = torch.empty((self.num_envs, ROWS, COLUMNS), dtype=torch.bool, device=device)
        self.deck = torch.empty((self.num_envs, 36), dtype=torch.long, device=device)
        self.deck_size = torch.empty(self.num_envs, dtype=torch.long, device=device)
        self.must_select_adjacent = torch.empty(self.num_envs, dtype=torch.bool, device=device)
        self.turn_can_end = torch.empty(self.num_envs, dtype=torch.bool, device=device)
        self.steps = torch.empty(self.num_envs, dtype=torch.long, device=device)
        self.drinks = torch.empty(self.num_envs, dtype=torch.long, device=device)
        self.current_player = torch.empty(self.num_envs, dtype=torch.long, device=device)
        self.player_drinks = torch.empty((self.num_envs, self.player_count), dtype=torch.long, device=device)
        self.last_player_rewards = torch.zeros((self.num_envs, self.player_count), dtype=torch.float32, device=device)
        self.last_actors = torch.zeros(self.num_envs, dtype=torch.long, device=device)
        self.history = torch.zeros((self.num_envs, self.history_length, HISTORY_FEATURE_SIZE), dtype=torch.float32, device=device)
        self.reset()

    def _random_permutations(self, count: int) -> torch.Tensor:
        # argsort of independent uniforms is a permutation per environment.
        return torch.rand((count, 36), device=self.device, generator=self.generator).argsort(dim=1)

    def reset(self, indices: torch.Tensor | None = None) -> torch.Tensor:
        if indices is None:
            indices = torch.arange(self.num_envs, device=self.device)
        count = indices.numel()
        if count == 0:
            return self.observation()
        permutations = self._random_permutations(count)
        self.cards[indices] = -1
        self.face_up[indices] = False
        slots = self.layout.flatten().nonzero(as_tuple=False).squeeze(1)
        board = self.cards.flatten(1)
        board[indices[:, None], slots] = permutations[:, : slots.numel()]
        faces = self.face_up.flatten(1)
        faces[indices[:, None], self.corner_or_handle.flatten().nonzero(as_tuple=False).squeeze(1)] = True
        self.deck[indices] = -1
        self.deck[indices, : 36 - slots.numel()] = permutations[:, slots.numel() :]
        self.deck_size[indices] = 36 - slots.numel()
        self.must_select_adjacent[indices] = True
        self.turn_can_end[indices] = False
        self.steps[indices] = 0
        self.drinks[indices] = 0
        self.current_player[indices] = 0
        self.player_drinks[indices] = 0
        self.last_player_rewards[indices] = 0
        self.history[indices] = 0
        self._append_current_record(indices)
        return self.observation()

    def observation(self) -> torch.Tensor:
        shown = self.face_up & self.layout
        rank = torch.where(shown, self.cards.clamp_min(0).to(torch.float32).div(32.0), -torch.ones((), device=self.device))
        cells = torch.stack((self.layout.expand(self.num_envs, -1, -1).to(torch.float32), shown.to(torch.float32), rank), dim=-1).flatten(1)
        globals_ = torch.stack((
            self.must_select_adjacent.to(torch.float32),
            self.turn_can_end.to(torch.float32),
            torch.zeros(self.num_envs, device=self.device),
            torch.zeros(self.num_envs, device=self.device),
            torch.full((self.num_envs,), 1.0 / 8.0, device=self.device),
        ), dim=1)
        result = torch.cat((cells, globals_), dim=1)
        assert result.shape == (self.num_envs, FEATURE_SIZE)
        return result

    def _public_cards(self, cards: torch.Tensor | None = None, face_up: torch.Tensor | None = None) -> torch.Tensor:
        cards = self.cards if cards is None else cards
        face_up = self.face_up if face_up is None else face_up
        visible = face_up & self.layout
        ranks = torch.where(visible, cards.clamp_min(0).div(4, rounding_mode="floor").to(torch.float32).div(8), torch.full_like(cards, -1, dtype=torch.float32))
        suits = torch.where(visible, cards.clamp_min(0).remainder(4).to(torch.float32).div(3), torch.full_like(cards, -1, dtype=torch.float32))
        invalid = ~self.layout
        ranks[:, invalid] = -2
        suits[:, invalid] = -2
        return torch.stack((ranks, suits), dim=-1).flatten(1)

    def _append_current_record(self, indices: torch.Tensor | None = None) -> None:
        if indices is None:
            indices = torch.arange(self.num_envs, device=self.device)
        if indices.numel() == 0:
            return
        record = torch.zeros((indices.numel(), HISTORY_FEATURE_SIZE), dtype=torch.float32, device=self.device)
        record[:, :BOARD_FEATURE_SIZE] = self._public_cards()[indices]
        flags_start = BOARD_FEATURE_SIZE + ACTION_FEATURE_SIZE + OUTCOME_FEATURE_SIZE + REMOVED_FEATURE_SIZE
        record[:, flags_start] = self.must_select_adjacent[indices].to(torch.float32)
        record[:, flags_start + 1] = self.turn_can_end[indices].to(torch.float32)
        self.history[indices, -1] = record

    def history_observation(self) -> torch.Tensor:
        return self.history

    def _finish_history_event(self, actions: torch.Tensor, correct: torch.Tensor, wrong: torch.Tensor, is_pass: torch.Tensor, removed_cards: torch.Tensor) -> None:
        action_start = BOARD_FEATURE_SIZE
        outcome_start = action_start + ACTION_FEATURE_SIZE
        removed_start = outcome_start + OUTCOME_FEATURE_SIZE
        encoded = actions.clamp_max(PASS_ACTION_INDEX - 1)
        guess = encoded.remainder(GUESS_TYPES).to(torch.float32).div(GUESS_TYPES - 1)
        encoded = encoded.div(GUESS_TYPES, rounding_mode="floor")
        orientation = encoded.remainder(ORIENTATIONS).to(torch.float32)
        encoded = encoded.div(ORIENTATIONS, rounding_mode="floor")
        row = encoded.div(COLUMNS, rounding_mode="floor").to(torch.float32).div(ROWS - 1)
        column = encoded.remainder(COLUMNS).to(torch.float32).div(COLUMNS - 1)
        fields = torch.stack(((actions == PASS_ACTION_INDEX).to(torch.float32), row, column, orientation, guess), dim=1)
        fields[is_pass, 1:] = 0
        self.history[:, -1, action_start : action_start + ACTION_FEATURE_SIZE] = fields
        self.history[:, -1, outcome_start] = correct.to(torch.float32)
        self.history[:, -1, outcome_start + 1] = wrong.to(torch.float32)
        self.history[:, -1, outcome_start + 2] = is_pass.to(torch.float32)
        self.history[:, -1, removed_start : removed_start + REMOVED_FEATURE_SIZE] = self._public_cards(removed_cards, removed_cards >= 0)
        self.history = torch.roll(self.history, shifts=-1, dims=1)
        self.history[:, -1] = 0
        self._append_current_record()

    @staticmethod
    def _shift(values: torch.Tensor, row_offset: int, column_offset: int) -> torch.Tensor:
        """Return values at (row + row_offset, column + column_offset)."""
        result = torch.zeros_like(values)
        source_rows = slice(max(0, row_offset), ROWS + min(0, row_offset))
        target_rows = slice(max(0, -row_offset), ROWS - max(0, row_offset))
        source_columns = slice(max(0, column_offset), COLUMNS + min(0, column_offset))
        target_columns = slice(max(0, -column_offset), COLUMNS - max(0, column_offset))
        result[:, target_rows, target_columns] = values[:, source_rows, source_columns]
        return result

    def _oriented_neighbors(self, values: torch.Tensor, orientation: int) -> tuple[torch.Tensor, torch.Tensor]:
        if orientation == HORIZONTAL:
            return self._shift(values, 0, -1), self._shift(values, 0, 1)
        return self._shift(values, -1, 0), self._shift(values, 1, 0)

    def action_mask(self) -> torch.Tensor:
        eligible = self.layout & ~self.face_up
        eligible &= ~self.must_select_adjacent[:, None, None] | self.handle_adjacency
        options = torch.zeros((self.num_envs, ROWS, COLUMNS, ORIENTATIONS, GUESS_TYPES), dtype=torch.bool, device=self.device)
        has_between = torch.zeros((self.num_envs, ROWS, COLUMNS), dtype=torch.bool, device=self.device)
        counts: list[torch.Tensor] = []
        for orientation in (HORIZONTAL, VERTICAL):
            first, second = self._oriented_neighbors(self.face_up, orientation)
            count = first.to(torch.long) + second.to(torch.long)
            counts.append(count)
            has_between |= count >= 2
            options[..., orientation, IN_BETWEEN] = eligible & (count >= 2)
            options[..., orientation, OUTSIDE] = eligible & (count >= 2)
        for orientation, count in enumerate(counts):
            higher_lower = eligible & (count == 1) & ~has_between
            options[..., orientation, HIGHER] = higher_lower
            options[..., orientation, SAME] = higher_lower
            options[..., orientation, LOWER] = higher_lower
        passes = self.turn_can_end.unsqueeze(1)
        return torch.cat((options.flatten(1), passes), dim=1).reshape(self.num_envs, ACTION_SIZE)

    def _connected(self, start: torch.Tensor) -> torch.Tensor:
        """Connected face-up component for one start cell per environment."""
        found = start
        # The playable graph has 22 cells; after at most 21 expansions, its
        # component is complete.  This fixed loop stays on the CUDA device.
        for _ in range(21):
            neighbors = self._shift(found, -1, 0) | self._shift(found, 1, 0) | self._shift(found, 0, -1) | self._shift(found, 0, 1)
            found |= neighbors & self.face_up & self.layout
        return found

    def _shuffle_and_redeal(self, removed: torch.Tensor) -> None:
        removed_count = removed.sum(dim=(1, 2)).to(torch.long)
        removed_cards = torch.where(removed, self.cards, -torch.ones((), dtype=torch.long, device=self.device)).flatten(1)
        order = torch.arange(ROWS * COLUMNS, device=self.device).unsqueeze(0).expand(self.num_envs, -1)
        removed_order = torch.where(removed.flatten(1), order, order + ROWS * COLUMNS).argsort(dim=1)
        compact_removed = removed_cards.gather(1, removed_order)[:, : ROWS * COLUMNS]
        deck_positions = torch.arange(36, device=self.device)[None, :]
        append_rank = deck_positions - self.deck_size[:, None]
        append_here = (append_rank >= 0) & (append_rank < removed_count[:, None])
        appended_cards = compact_removed.gather(1, append_rank.clamp(0, ROWS * COLUMNS - 1))
        self.deck = torch.where(append_here, appended_cards, self.deck)
        self.deck_size += removed_count

        shuffle_key = torch.rand((self.num_envs, 36), device=self.device, generator=self.generator)
        shuffle_key.masked_fill_(deck_positions >= self.deck_size[:, None], 2.0)
        # Keep decks for correct/pass actions in exactly the same order without
        # a host-side conditional or CUDA synchronization.
        identity_key = deck_positions.to(torch.float32) / 36.0
        shuffle_key = torch.where(removed_count[:, None] > 0, shuffle_key, identity_key)
        self.deck = self.deck.gather(1, shuffle_key.argsort(dim=1))
        self.cards[removed] = -1
        self.face_up[removed] = False

        missing = self.layout & (self.cards == -1)
        missing_count = missing.sum(dim=(1, 2)).to(torch.long)
        cell_order = torch.arange(ROWS * COLUMNS, device=self.device).unsqueeze(0).expand(self.num_envs, -1)
        missing_order = torch.where(missing.flatten(1), cell_order, cell_order + ROWS * COLUMNS).argsort(dim=1)
        targets = missing_order[:, : ROWS * COLUMNS]
        draw_positions = self.deck_size[:, None] - 1 - torch.arange(ROWS * COLUMNS, device=self.device)
        drawn = self.deck.gather(1, draw_positions.clamp_min(0))
        valid_draws = torch.arange(ROWS * COLUMNS, device=self.device)[None, :] < missing_count[:, None]
        flat_cards = self.cards.flatten(1)
        flat_faces = self.face_up.flatten(1)
        existing = flat_cards.gather(1, targets)
        flat_cards.scatter_(1, targets, torch.where(valid_draws, drawn, existing))
        flat_faces.scatter_(1, targets, torch.where(valid_draws, self.corner_or_handle.flatten()[targets], flat_faces.gather(1, targets)))
        self.deck_size -= missing_count

    def step(self, actions: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor]:
        """Advance every environment; returns observation, reward, done, drinks, completed."""
        actions = actions.to(device=self.device, dtype=torch.long)
        if actions.shape != (self.num_envs,):
            raise ValueError(f"Expected actions shape ({self.num_envs},), got {tuple(actions.shape)}")
        mask = self.action_mask()
        if not bool(mask.gather(1, actions[:, None]).all()):
            raise ValueError("Illegal action; callers must apply action_mask().")
        self.steps += 1
        acting_player = self.current_player.clone()
        self.last_actors = acting_player
        self.last_player_rewards.zero_()
        is_pass = actions == PASS_ACTION_INDEX
        reward = torch.full((self.num_envs,), self.pass_reward, dtype=torch.float32, device=self.device)
        reward[~is_pass] = 0.0
        completed = torch.zeros(self.num_envs, dtype=torch.bool, device=self.device)
        drinks = torch.zeros(self.num_envs, dtype=torch.long, device=self.device)
        self.turn_can_end[is_pass] = False
        self.current_player[is_pass] = (self.current_player[is_pass] + 1) % self.player_count

        card_actions = ~is_pass
        # Pass has no card payload; decode it as a harmless dummy action.
        encoded = torch.where(is_pass, torch.zeros_like(actions), actions)
        guess = encoded.remainder(GUESS_TYPES)
        encoded = encoded.div(GUESS_TYPES, rounding_mode="floor")
        orientation = encoded.remainder(ORIENTATIONS)
        encoded = encoded.div(ORIENTATIONS, rounding_mode="floor")
        row, column = encoded.div(COLUMNS, rounding_mode="floor"), encoded.remainder(COLUMNS)
        batch = torch.arange(self.num_envs, device=self.device)
        target_rank = self.cards[batch, row, column].div(4, rounding_mode="floor")
        selected_faces = []
        selected_ranks = []
        for direction in ((0, -1), (0, 1), (-1, 0), (1, 0)):
            shifted_faces = self._shift(self.face_up, *direction)
            shifted_cards = self._shift(self.cards, *direction)
            selected_faces.append(shifted_faces[batch, row, column])
            selected_ranks.append(shifted_cards[batch, row, column].clamp_min(0).div(4, rounding_mode="floor"))
        horizontal_face = torch.stack(selected_faces[:2], dim=1)
        vertical_face = torch.stack(selected_faces[2:], dim=1)
        horizontal_rank = torch.stack(selected_ranks[:2], dim=1)
        vertical_rank = torch.stack(selected_ranks[2:], dim=1)
        faces = torch.where(orientation[:, None] == HORIZONTAL, horizontal_face, vertical_face)
        ranks = torch.where(orientation[:, None] == HORIZONTAL, horizontal_rank, vertical_rank)
        neighbor_count = faces.sum(dim=1)
        one_rank = (ranks * faces.to(torch.long)).sum(dim=1)
        low = torch.where(faces, ranks, torch.full_like(ranks, 99)).min(dim=1).values
        high = torch.where(faces, ranks, torch.full_like(ranks, -1)).max(dim=1).values
        correct_one = ((guess == HIGHER) & (target_rank > one_rank)) | ((guess == SAME) & (target_rank == one_rank)) | ((guess == LOWER) & (target_rank < one_rank))
        in_between = (target_rank >= low) & (target_rank <= high)
        correct_many = ((guess == IN_BETWEEN) & in_between) | ((guess == OUTSIDE) & ~in_between)
        correct = card_actions & torch.where(neighbor_count == 1, correct_one, correct_many)
        wrong = card_actions & ~correct

        self.face_up[batch[correct], row[correct], column[correct]] = True
        self.must_select_adjacent[correct] = False
        self.turn_can_end[correct] = True
        completed = (self.face_up | ~self.layout).all(dim=(1, 2)) & correct
        reward[correct] = self.correct_reward + completed[correct].to(torch.float32) * self.complete_reward

        start = torch.zeros_like(self.face_up)
        start[batch[wrong], row[wrong], column[wrong]] = True
        self.face_up[batch[wrong], row[wrong], column[wrong]] = True
        removed = self._connected(start) & wrong[:, None, None]
        drinks = removed.sum(dim=(1, 2)).to(torch.long)
        reward[wrong] = drinks[wrong].to(torch.float32) * self.wrong_reward
        self.drinks += drinks
        self.player_drinks[batch, acting_player] += drinks
        same_correct = correct & (guess == SAME)
        if self.player_count > 1:
            other_players = torch.arange(self.player_count, device=self.device)[None, :] != acting_player[:, None]
            self.player_drinks += (same_correct[:, None] & other_players).to(torch.long)
            self.last_player_rewards -= (same_correct[:, None] & other_players).to(torch.float32)
        self.last_player_rewards[batch, acting_player] += reward
        handle_removed = removed[:, HANDLE[0], HANDLE[1]]
        self.must_select_adjacent[wrong] = handle_removed[wrong]
        self.turn_can_end[wrong] = False
        removed_cards = torch.where(removed, self.cards, -torch.ones((), dtype=torch.long, device=self.device))
        self._shuffle_and_redeal(removed)
        done = completed | (self.steps >= self.max_steps)
        self._finish_history_event(actions, correct, wrong, is_pass, removed_cards)
        return self.observation(), reward, done, drinks, completed
