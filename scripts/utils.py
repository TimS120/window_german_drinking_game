"""Utility functions for the Window Drinking Game."""

try:
    from config import RANKS, SUITS, NUM_CARDS, WINDOW_LAYOUT, HANDLE_POSITION
except ImportError:
    from .config import RANKS, SUITS, NUM_CARDS, WINDOW_LAYOUT, HANDLE_POSITION


def get_player_names(root):
    """
    Prompt the user to enter player names (comma separated).

    Args:
        root (tk.Tk): The main Tkinter window.

    Returns:
        list: List of player names.
    """
    player_names = []

    def submit():
        names = entry.get()
        if names.strip() != "":
            player_names.extend([name.strip() for name in names.split(",") if name.strip()])
        top.destroy()

    top = tk.Toplevel(root)
    top.title("Player Setup")
    tk.Label(top, text="Enter player names (comma separated):").pack(padx=10, pady=10)
    entry = tk.Entry(top, width=40)
    entry.pack(padx=10, pady=10)
    tk.Button(top, text="Submit", command=submit).pack(padx=10, pady=10)
    top.grab_set()
    root.wait_window(top)
    return player_names


def card_id_to_label(card_id):
    """
    Convert a card ID to a label string (e.g., '8.E' or 'K.S').

    Args:
        card_id (int): The card identifier.

    Returns:
        str: Card label.
    """
    rank_index = card_id // 4
    suit_index = card_id % 4
    return f"{RANKS[rank_index]}.{SUITS[suit_index]}"


def create_deck():
    """
    Create a complete deck of card IDs.

    Returns:
        list: List of integers representing card IDs.
    """
    return list(range(NUM_CARDS))


def get_rank_index(card_id):
    """
    Get the rank index for a given card.

    Args:
        card_id (int): The card identifier.

    Returns:
        int: The rank index.
    """
    return card_id // 4


def is_between(card_id, boundary1, boundary2):
    """
    Check if the rank of card_id is between those of boundary1 and boundary2 (inclusive).

    Args:
        card_id (int): Card ID to check.
        boundary1 (int): First boundary card ID.
        boundary2 (int): Second boundary card ID.

    Returns:
        bool: True if card rank is between the boundaries; False otherwise.
    """
    r1 = get_rank_index(boundary1)
    r2 = get_rank_index(boundary2)
    low, high = sorted([r1, r2])
    r_card = get_rank_index(card_id)
    return low <= r_card <= high


def adjacent_positions(pos):
    """
    Return valid adjacent positions (up, down, left, right) in the game layout.

    Args:
        pos (tuple): A (row, column) tuple.

    Returns:
        list: List of adjacent (row, column) positions that are valid card slots.
    """
    r, c = pos
    neighbors = []
    for dr, dc in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
        nr, nc = r + dr, c + dc
        if 0 <= nr < len(WINDOW_LAYOUT) and 0 <= nc < len(WINDOW_LAYOUT[nr]):
            if WINDOW_LAYOUT[nr][nc] is not None:
                neighbors.append((nr, nc))
    return neighbors


def card_id_to_front_filename(card_id):
    """
    Map a card ID to its front image filename (e.g., 'c1_v1.png').

    Card IDs are rank-major: the first four cards share value 1 and use
    colours 1 through 4; the next four use value 2, and so on.

    Args:
        card_id (int): The card identifier.

    Returns:
        str: The front image filename.
    """
    colour = card_id % len(SUITS) + 1
    value = card_id // len(SUITS) + 1
    return f"c{colour}_v{value}.png"
    import tkinter as tk
