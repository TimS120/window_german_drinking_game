"""Encode public contract fixtures exactly as the app pads deployed histories."""
import numpy as np

from .contract import BOARD_FEATURE_SIZE, LEGACY_HISTORY_FEATURE_SIZE


def encode_fixture_history(fixture: dict, length: int, feature_size: int) -> np.ndarray:
    width = fixture.get('featureSize', LEGACY_HISTORY_FEATURE_SIZE)
    records = np.asarray(fixture['history'], dtype=np.float32).reshape(-1, width)
    count = min(length, records.shape[0])
    history = np.zeros((1, length, feature_size), dtype=np.float32)
    if count:
        history[0, -count:, :LEGACY_HISTORY_FEATURE_SIZE] = records[-count:, :LEGACY_HISTORY_FEATURE_SIZE]
        if feature_size > LEGACY_HISTORY_FEATURE_SIZE:
            players = len(fixture['state']['players'])
            valid = np.abs(records[-count:, :BOARD_FEATURE_SIZE]).sum(axis=1) > 0
            # Left padding must stay entirely zero, including table context.
            history[0, -count:, LEGACY_HISTORY_FEATURE_SIZE + players - 1] = valid.astype(np.float32)
    return history
