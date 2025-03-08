"""
Configuration constants and mappings for the Window Drinking Game.
"""

# Toggle development mode. If True, default player names are used.
DEVELOPMENT_MODE = False

# Card rank and suit definitions.
RANKS = ["6", "7", "8", "9", "10", "U", "O", "K", "A"]  # 6 < 7 < ... < A
SUITS = ["E", "B", "H", "S"]  # Eichel, Blatt, Herz, Schelle
NUM_CARDS = len(RANKS) * len(SUITS)

# Layout for the game board (5 rows x 6 columns). True = card slot; None = empty space.
WINDOW_LAYOUT = [
    [True,  True,  True,  True,  True,  None],
    [True,  None,  True,  None,  True,  None],
    [True,  True,  True,  True,  True,  True],
    [True,  None,  True,  None,  True,  None],
    [True,  True,  True,  True,  True,  None]
]

# Positions that are always face-up.
CORNER_POSITIONS = [(0, 0), (0, 4), (4, 0), (4, 4)]
HANDLE_POSITION = (2, 5)

# Mappings for card image file naming.
SUIT_MAP = {"E": "Eichel", "B": "Blatt", "H": "Herz", "S": "Schelln"}
RANK_MAP = {
    "6": "Sechs",
    "7": "Sieben",
    "8": "Acht",
    "9": "Neun",
    "10": "Zehn",
    "U": "Unter",
    "O": "Ober",
    "K": "Koenig",
    "A": "Ass"
}
