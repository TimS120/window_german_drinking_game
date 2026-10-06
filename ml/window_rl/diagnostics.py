"""Public-fact diagnostics only: never inputs, rewards, or action filters."""
import torch
from .contract import BOARD_FEATURE_SIZE, COLUMNS, PASS_ACTION_INDEX, ROWS


def obviously_impossible_guesses(history: torch.Tensor, actions: torch.Tensor) -> torch.Tensor:
    """Detect strict rank-boundary errors and outside a full inclusive range."""
    encoded = actions.clamp_max(PASS_ACTION_INDEX - 1)
    guess = encoded % 5
    orientation = (encoded // 5) % 2
    cell = encoded // 10
    row, column = cell // COLUMNS, cell % COLUMNS
    ranks = history[:, -1, :BOARD_FEATURE_SIZE].reshape(-1, ROWS * COLUMNS, 2)[:, :, 0]
    adjacent = []
    for direction in (-1, 1):
        neighbor_row = row + direction * (orientation == 1)
        neighbor_column = column + direction * (orientation == 0)
        inside = (neighbor_row >= 0) & (neighbor_row < ROWS) & (neighbor_column >= 0) & (neighbor_column < COLUMNS)
        index = (neighbor_row * COLUMNS + neighbor_column).clamp(0, ROWS * COLUMNS - 1)
        rank = ranks.gather(1, index[:, None]).squeeze(1)
        adjacent.append(torch.where(inside, rank, -torch.ones_like(rank)))
    first, second = adjacent
    visible = (first >= 0).long() + (second >= 0).long()
    high = torch.maximum(first, second)
    low = torch.minimum(first, second)
    impossible = ((visible == 1) & (((guess == 0) & (high == 1)) | ((guess == 2) & (high == 0))))
    impossible |= (visible == 2) & (guess == 4) & (low == 0) & (high == 1)
    return impossible & (actions != PASS_ACTION_INDEX)
