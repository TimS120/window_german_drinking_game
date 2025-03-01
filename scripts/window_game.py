import random
import tkinter as tk
from tkinter import messagebox

# -------------------------------------------------------
# CONSTANTS & DATA STRUCTURES
# -------------------------------------------------------
RANKS = ["6", "7", "8", "9", "10", "U", "O", "K", "A"]  # 6 < 7 < 8 < 9 < 10 < U < O < K < A
SUITS = ["E", "B", "H", "S"]  # Eichel (E), Blatt (B), Herz (H), Schelle (S)
NUM_CARDS = len(RANKS) * len(SUITS)  # Adapt if your deck differs.

# "Window" layout (5 rows, 6 columns), True = card slot, None = empty space:
WINDOW_LAYOUT = [
    [True, True, True, True, True, None],    # Row 0
    [True, None, True, None, True, None],    # Row 1
    [True, True, True, True, True, True],    # Row 2
    [True, None, True, None, True, None],    # Row 3
    [True, True, True, True, True, None]     # Row 4
]

# Corners (always face-up):
CORNER_POSITIONS = [(0,0), (0,4), (4,0), (4,4)]
# Handle (also face-up):
HANDLE_POSITION  = (2,5)

def card_id_to_label(card_id):
    """Convert card_id to a string like '8.E' or 'K.S'."""
    rank_index = card_id // 4
    suit_index = card_id % 4
    return f"{RANKS[rank_index]}.{SUITS[suit_index]}"

def create_deck():
    """Create a full list of card IDs [0..NUM_CARDS-1]."""
    return list(range(NUM_CARDS))

def get_rank_index(card_id):
    return card_id // 4

def is_between(card_id, boundary1, boundary2):
    """Check if card_id's rank is between boundary1's and boundary2's ranks (inclusive)."""
    r1 = get_rank_index(boundary1)
    r2 = get_rank_index(boundary2)
    low, high = sorted([r1, r2])
    r_card = get_rank_index(card_id)
    return low <= r_card <= high

def adjacent_positions(pos):
    """
    Return valid (up/down/left/right) neighbors of 'pos' that exist in WINDOW_LAYOUT 
    (i.e., not None).
    """
    r, c = pos
    neighbors = []
    for dr, dc in [(-1,0), (1,0), (0,-1), (0,1)]:
        nr, nc = r + dr, c + dc
        if 0 <= nr < len(WINDOW_LAYOUT) and 0 <= nc < len(WINDOW_LAYOUT[nr]):
            if WINDOW_LAYOUT[nr][nc] is not None:
                neighbors.append((nr, nc))
    return neighbors

# -------------------------------------------------------
# MAIN GAME CLASS
# -------------------------------------------------------
class WindowGame:
    def __init__(self, root, players):
        self.root = root
        self.root.title("Window Drinking Game")

        # Players & scoreboard
        self.players = players
        self.current_player_idx = 0
        self.drink_count = {p: 0 for p in players}

        # Create and shuffle deck
        self.deck = create_deck()
        random.shuffle(self.deck)

        # Prepare card ID grid and face-up grid
        self.card_grid = []
        self.face_up = []
        for row in WINDOW_LAYOUT:
            card_row = []
            face_row = []
            for cell in row:
                if cell is None:
                    card_row.append(None)
                    face_row.append(False)
                else:
                    card_row.append(None)  # will fill later
                    face_row.append(False)
            self.card_grid.append(card_row)
            self.face_up.append(face_row)

        # Deal initial cards
        self.deal_initial_cards()

        # Build UI
        self.frame_top = tk.Frame(root)
        self.frame_top.pack(side=tk.TOP, fill=tk.X)

        self.frame_game = tk.Frame(root)
        self.frame_game.pack(side=tk.TOP)

        self.frame_bottom = tk.Frame(root)
        self.frame_bottom.pack(side=tk.BOTTOM, fill=tk.X)

        # Scoreboard
        self.score_label = tk.Label(self.frame_top, text="", font=("Arial", 12, "bold"))
        self.score_label.pack()

        # Info label
        self.info_label = tk.Label(self.frame_bottom, text="", font=("Arial", 12))
        self.info_label.pack()

        # Create buttons for each valid slot
        self.buttons = []
        for r in range(len(WINDOW_LAYOUT)):
            btn_row = []
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c]:
                    b = tk.Button(self.frame_game, text="", width=6, height=3,
                                  command=lambda rr=r, cc=c: self.on_card_click(rr, cc))
                    b.grid(row=r, column=c, padx=5, pady=5)
                    btn_row.append(b)
                else:
                    btn_row.append(None)
            self.buttons.append(btn_row)

        self.update_ui()

    def deal_initial_cards(self):
        """
        Deal cards from the deck into the layout.
        Corners & handle => face-up; others => face-down.
        """
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c]:
                    if len(self.deck) == 0:
                        self.card_grid[r][c] = None
                        self.face_up[r][c] = False
                    else:
                        card = self.deck.pop()
                        self.card_grid[r][c] = card
                        # If corner or handle, face-up
                        if (r, c) in CORNER_POSITIONS or (r, c) == HANDLE_POSITION:
                            self.face_up[r][c] = True
                        else:
                            self.face_up[r][c] = False

    def on_card_click(self, r, c):
        """Handle clicking on a face-down card."""
        if self.face_up[r][c]:
            # Already face-up, ignore
            return

        # Identify face-up neighbors
        neighbors = [(nr, nc) for (nr, nc) in adjacent_positions((r, c)) if self.face_up[nr][nc]]

        if len(neighbors) == 1:
            self.ask_higher_lower(r, c, neighbors[0])
        elif len(neighbors) == 2:
            (n1r, n1c), (n2r, n2c) = neighbors
            same_row = (n1r == n2r)
            same_col = (n1c == n2c)
            if same_row or same_col:
                # Straight line => in-between guess
                self.ask_in_between(r, c, neighbors[0], neighbors[1])
            else:
                # Around the corner => must choose
                self.ask_user_to_choose_boundaries(r, c, neighbors)
        else:
            messagebox.showinfo("Invalid", "Cannot guess here (needs 1 or 2 face-up neighbors).")

    def ask_user_to_choose_boundaries(self, r, c, neighbors):
        """If neighbors are 'around the corner,' ask which pair to use."""
        choose_win = tk.Toplevel(self.root)
        choose_win.title("Choose Boundaries")

        tk.Label(choose_win, text="Select which two neighbors to use for in-between guess:").pack()

        def use_first_pair():
            self.ask_in_between(r, c, neighbors[0], neighbors[1])
            choose_win.destroy()

        def use_second_pair():
            self.ask_in_between(r, c, neighbors[1], neighbors[0])
            choose_win.destroy()

        tk.Button(choose_win, text="Option 1", command=use_first_pair).pack(side=tk.LEFT, padx=5)
        tk.Button(choose_win, text="Option 2", command=use_second_pair).pack(side=tk.RIGHT, padx=5)

    def ask_higher_lower(self, r, c, neighbor):
        guess_win = tk.Toplevel(self.root)
        guess_win.title("Guess Higher or Lower")

        tk.Label(guess_win, text="Is the selected card Higher or Lower than neighbor?").pack()

        def guess_higher():
            self.resolve_higher_lower(r, c, neighbor, "higher")
            guess_win.destroy()

        def guess_lower():
            self.resolve_higher_lower(r, c, neighbor, "lower")
            guess_win.destroy()

        tk.Button(guess_win, text="Higher", command=guess_higher).pack(side=tk.LEFT, padx=10)
        tk.Button(guess_win, text="Lower", command=guess_lower).pack(side=tk.RIGHT, padx=10)

    def resolve_higher_lower(self, r, c, neighbor, guess):
        card_id = self.card_grid[r][c]
        neighbor_id = self.card_grid[neighbor[0]][neighbor[1]]
        card_rank = get_rank_index(card_id)
        neighbor_rank = get_rank_index(neighbor_id)

        if (guess == "higher" and card_rank > neighbor_rank) or \
           (guess == "lower" and card_rank < neighbor_rank):
            self.finish_guess(r, c, True)
        else:
            self.finish_guess(r, c, False)

    def ask_in_between(self, r, c, n1, n2):
        guess_win = tk.Toplevel(self.root)
        guess_win.title("Guess In-Between or Outside")

        tk.Label(guess_win, text="Is the card In-Between or Outside these two?").pack()

        def guess_in():
            self.resolve_in_between(r, c, n1, n2, True)
            guess_win.destroy()

        def guess_out():
            self.resolve_in_between(r, c, n1, n2, False)
            guess_win.destroy()

        tk.Button(guess_win, text="In-Between", command=guess_in).pack(side=tk.LEFT, padx=10)
        tk.Button(guess_win, text="Outside", command=guess_out).pack(side=tk.RIGHT, padx=10)

    def resolve_in_between(self, r, c, n1, n2, guess_in):
        card_id = self.card_grid[r][c]
        n1_id = self.card_grid[n1[0]][n1[1]]
        n2_id = self.card_grid[n2[0]][n2[1]]

        in_range = is_between(card_id, n1_id, n2_id)
        is_correct = (in_range == guess_in)
        self.finish_guess(r, c, is_correct)

    def finish_guess(self, r, c, is_correct):
        if is_correct:
            # Reveal card
            self.face_up[r][c] = True
            self.update_ui()

            # Check if all face-up => game over
            if self.check_game_end():
                return

            # Ask if player continues
            if messagebox.askyesno("Correct!", "Guess is correct! Continue your turn?"):
                self.info_label.config(text=f"{self.current_player()}'s turn continues.")
            else:
                self.next_player()
        else:
            # Wrong guess => count adjacent face-up
            neighbors = [(nr, nc) for (nr, nc) in adjacent_positions((r, c)) if self.face_up[nr][nc]]
            penalty = len(neighbors)
            self.drink_count[self.current_player()] += penalty

            # Remove guessed + neighbors
            to_remove = neighbors + [(r,c)]
            for (rr, cc) in to_remove:
                cid = self.card_grid[rr][cc]
                if cid is not None:
                    self.deck.append(cid)
                self.card_grid[rr][cc] = None
                self.face_up[rr][cc] = False

            random.shuffle(self.deck)
            self.redeal_spots()

            # Same player goes again
            self.update_ui()
            self.info_label.config(
                text=f"Wrong guess! {self.current_player()} drinks {penalty}.\n"
                     f"{self.current_player()} goes again."
            )

    def redeal_spots(self):
        """
        Refill empty spots in the layout. 
        Corners & handle => face-up, others => face-down.
        """
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c]:
                    if self.card_grid[r][c] is None and len(self.deck) > 0:
                        card = self.deck.pop()
                        self.card_grid[r][c] = card
                        if (r, c) in CORNER_POSITIONS or (r, c) == HANDLE_POSITION:
                            self.face_up[r][c] = True
                        else:
                            self.face_up[r][c] = False

    def check_game_end(self):
        """Check if all card slots are face-up."""
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c]:
                    if not self.face_up[r][c]:
                        return False
        # All face-up => game ends
        messagebox.showinfo("Game Over", "All cards are face-up! Game ends.")
        if messagebox.askyesno("Play Again?", "Start a new game?"):
            self.reset_game()
        else:
            self.root.quit()
        return True

    def reset_game(self):
        """Reset everything for a new game."""
        self.deck = create_deck()
        random.shuffle(self.deck)
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c]:
                    self.card_grid[r][c] = None
                    self.face_up[r][c] = False
        self.deal_initial_cards()
        self.update_ui()

    def current_player(self):
        return self.players[self.current_player_idx]

    def next_player(self):
        self.current_player_idx = (self.current_player_idx + 1) % len(self.players)
        self.info_label.config(text=f"{self.current_player()}'s turn.")

    def update_ui(self):
        # Update scoreboard
        score_text = " | ".join([f"{p}: {self.drink_count[p]} drinks" for p in self.players])
        self.score_label.config(text=f"Scoreboard: {score_text}")

        # Update buttons
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c]:
                    card_id = self.card_grid[r][c]
                    if card_id is not None:
                        if self.face_up[r][c]:
                            self.buttons[r][c].config(text=card_id_to_label(card_id), state=tk.DISABLED)
                        else:
                            self.buttons[r][c].config(text="X", state=tk.NORMAL)
                    else:
                        self.buttons[r][c].config(text=" ", state=tk.DISABLED)

        self.info_label.config(text=f"{self.current_player()}'s turn.")


# -------------------------------------------------------
# MAIN
# -------------------------------------------------------
if __name__ == "__main__":
    root = tk.Tk()
    # Example: three players
    players = ["Alice", "Bob", "Charlie"]
    game = WindowGame(root, players)
    root.mainloop()
