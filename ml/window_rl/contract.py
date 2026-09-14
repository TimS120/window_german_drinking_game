"""Stable Python counterpart of app/lib/rl_policy.dart."""

ROWS = 5
COLUMNS = 6
FEATURES_PER_CELL = 3
GLOBAL_FEATURES = 5
FEATURE_SIZE = ROWS * COLUMNS * FEATURES_PER_CELL + GLOBAL_FEATURES
ORIENTATIONS = 2
GUESS_TYPES = 5
CARD_ACTION_SIZE = ROWS * COLUMNS * ORIENTATIONS * GUESS_TYPES
PASS_ACTION_INDEX = CARD_ACTION_SIZE
ACTION_SIZE = CARD_ACTION_SIZE + 1
# Bumped when the action-space layout changes, so an old checkpoint cannot be
# mistakenly exported against a new Flutter contract.
CHECKPOINT_FORMAT = 2


def action_index(row: int, column: int, orientation: int, guess: int) -> int:
    """Maps an action to the policy-logit index used by Flutter."""
    return (((row * COLUMNS + column) * ORIENTATIONS + orientation) * GUESS_TYPES) + guess
