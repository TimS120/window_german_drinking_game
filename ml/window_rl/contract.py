"""Stable Python counterpart of app/lib/rl_policy.dart."""

ROWS = 5
COLUMNS = 6
# A recurrent record stores only public information.  A visible card has its
# rank and suit; hidden cards never have an identity feature.
CARD_FEATURES = 2
BOARD_FEATURE_SIZE = ROWS * COLUMNS * CARD_FEATURES
REMOVED_FEATURE_SIZE = ROWS * COLUMNS * CARD_FEATURES
ACTION_FEATURE_SIZE = 5
OUTCOME_FEATURE_SIZE = 3
FLAG_FEATURE_SIZE = 2
HISTORY_FEATURE_SIZE = (
    BOARD_FEATURE_SIZE
    + ACTION_FEATURE_SIZE
    + OUTCOME_FEATURE_SIZE
    + REMOVED_FEATURE_SIZE
    + FLAG_FEATURE_SIZE
)
HISTORY_LENGTH = 16
MAX_HISTORY_LENGTH = 64
# Fixed critic-head capacity; single-player training uses physical seat zero.
PLAYER_COUNT = 4
# Retained for the readable reference environment during the contract
# transition; recurrent training consumes HISTORY_* tensors instead.
FEATURE_SIZE = ROWS * COLUMNS * 3 + 5
ORIENTATIONS = 2
GUESS_TYPES = 5
CARD_ACTION_SIZE = ROWS * COLUMNS * ORIENTATIONS * GUESS_TYPES
PASS_ACTION_INDEX = CARD_ACTION_SIZE
ACTION_SIZE = CARD_ACTION_SIZE + 1
# Bumped when the model/checkpoint layout changes, so an old policy cannot be
# mistakenly exported against the recurrent deployment contract.
CHECKPOINT_FORMAT = 4


def action_index(row: int, column: int, orientation: int, guess: int) -> int:
    """Maps an action to the policy-logit index used by Flutter."""
    return (((row * COLUMNS + column) * ORIENTATIONS + orientation) * GUESS_TYPES) + guess
