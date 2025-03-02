import random
import tkinter as tk
from tkinter import messagebox

# -------------------------------------------------------
# CONSTANTS & DATA STRUCTURES
# -------------------------------------------------------
RANKS = ["6", "7", "8", "9", "10", "U", "O", "K", "A"]  # 6 < 7 < 8 < 9 < 10 < U < O < K < A
SUITS = ["E", "B", "H", "S"]  # Eichel (E), Blatt (B), Herz (H), Schelle (S)
NUM_CARDS = len(RANKS) * len(SUITS)

# "Window" layout (5 rows, 6 columns), True = card slot, None = empty space:
WINDOW_LAYOUT = [
    [True, True, True, True, True, None],    # Row 0
    [True, None, True, None, True, None],      # Row 1
    [True, True, True, True, True, True],       # Row 2
    [True, None, True, None, True, None],       # Row 3
    [True, True, True, True, True, None]        # Row 4
]

# Corners (always face-up):
CORNER_POSITIONS = [(0, 0), (0, 4), (4, 0), (4, 4)]
# Handle (also face-up):
HANDLE_POSITION  = (2, 5)

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
    for dr, dc in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
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

        # Players & initial statistics
        self.players = players
        self.current_player_idx = 0
        self.drink_count = {p: 0 for p in players}
        self.player_correct_guesses = {p: 0 for p in players}
        self.player_changed_cards = {p: 0 for p in players}
        self.player_turns = {p: 0 for p in players}

        # Flag to enforce that the move must be on a card adjacent to the handle.
        self.must_select_adjacent_to_handle = True

        # Create and shuffle deck
        self.deck = create_deck()
        random.shuffle(self.deck)

        # Prepare card grid and face-up grid
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

        # Build UI: top frame, center (game grid + stats table), and bottom frame.
        self.frame_top = tk.Frame(root)
        self.frame_top.pack(side=tk.TOP, fill=tk.X)
        # (Optional: add a title or instructions here)

        self.frame_center = tk.Frame(root)
        self.frame_center.pack(side=tk.TOP, fill=tk.BOTH, expand=True)

        self.frame_game = tk.Frame(self.frame_center)
        self.frame_game.pack(side=tk.LEFT, padx=5, pady=5)

        self.frame_stats = tk.Frame(self.frame_center)
        self.frame_stats.pack(side=tk.RIGHT, padx=5, pady=5)

        self.frame_bottom = tk.Frame(root)
        self.frame_bottom.pack(side=tk.BOTTOM, fill=tk.X)

        # Info label in bottom frame
        self.info_label = tk.Label(self.frame_bottom, text="", font=("Arial", 12))
        self.info_label.pack(side=tk.LEFT, padx=5)

        # Dedicated "End Turn" button, initially disabled.
        self.stop_turn_button = tk.Button(self.frame_bottom, text="End Turn", command=self.end_turn, state=tk.DISABLED)
        self.stop_turn_button.pack(side=tk.RIGHT, padx=5)

        # Create buttons for the card grid
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
        # Record the starting count of face-up cards and count the turn.
        self.turn_start_face_up = self.count_face_up_cards()
        self.player_turns[self.current_player()] += 1

    def deal_initial_cards(self):
        """Deal cards from the deck into the layout.
        Corners & handle are dealt face-up; others face-down."""
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c]:
                    if len(self.deck) == 0:
                        self.card_grid[r][c] = None
                        self.face_up[r][c] = False
                    else:
                        card = self.deck.pop()
                        self.card_grid[r][c] = card
                        if (r, c) in CORNER_POSITIONS or (r, c) == HANDLE_POSITION:
                            self.face_up[r][c] = True
                        else:
                            self.face_up[r][c] = False

    def count_face_up_cards(self):
        """Return the number of face-up cards in the grid."""
        count = 0
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c] and self.face_up[r][c]:
                    count += 1
        return count

    def on_card_click(self, r, c):
        """Handle clicking on a face-down card."""
        if self.face_up[r][c]:
            return
        if self.must_select_adjacent_to_handle and (r, c) not in adjacent_positions(HANDLE_POSITION):
            return
        self.stop_turn_button.config(state=tk.DISABLED)
        # Get face-up neighbors with their relative directions.
        neighbors = []
        for nr, nc in adjacent_positions((r, c)):
            if self.face_up[nr][nc]:
                # Determine cardinal direction
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
        
        # Group options by axis.
        options = []  # Each option: (guess_type, axis, details)
        horizontal = [n for n, d in neighbors if d in ("east", "west")]
        vertical = [n for n, d in neighbors if d in ("north", "south")]
        
        if len(horizontal) >= 2:
            left = min(horizontal, key=lambda x: x[1])
            right = max(horizontal, key=lambda x: x[1])
            options.append(("in-between", "horizontal", (left, right)))
        elif len(horizontal) == 1:
            # Single horizontal neighbor yields a higher/lower option.
            options.append(("higher-lower", "horizontal", horizontal[0]))
        
        if len(vertical) >= 2:
            top = min(vertical, key=lambda x: x[0])
            bottom = max(vertical, key=lambda x: x[0])
            options.append(("in-between", "vertical", (top, bottom)))
        elif len(vertical) == 1:
            options.append(("higher-lower", "vertical", vertical[0]))
        
        if not options:
            return
        if len(options) == 1:
            opt = options[0]
            if opt[0] == "in-between":
                self.ask_in_between(r, c, opt[2][0], opt[2][1])
            elif opt[0] == "higher-lower":
                self.ask_higher_lower(r, c, opt[2])
            return
        
        # If multiple options are available, let the player choose.
        choose_win = tk.Toplevel(self.root)
        choose_win.title("Choose Guess Option")
        tk.Label(choose_win, text="Select a guessing option:").pack(padx=5, pady=5)
        for opt in options:
            if opt[0] == "in-between":
                btn_text = f"In-between ({opt[1]} boundaries)"
                def make_callback(o=opt):
                    return lambda: [self.ask_in_between(r, c, o[2][0], o[2][1]), choose_win.destroy()]
                tk.Button(choose_win, text=btn_text, command=make_callback()).pack(padx=5, pady=2)
            elif opt[0] == "higher-lower":
                btn_text = f"Higher/Lower (neighbor at {opt[1]})"
                def make_callback(o=opt):
                    return lambda: [self.ask_higher_lower(r, c, o[2]), choose_win.destroy()]
                tk.Button(choose_win, text=btn_text, command=make_callback()).pack(padx=5, pady=2)

    def ask_user_to_choose_boundaries(self, r, c, neighbors):
        """Ask the user to choose boundaries if two valid options exist."""
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
        """Open a window to ask for a higher/lower guess."""
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
        if (guess == "higher" and card_rank > neighbor_rank) or (guess == "lower" and card_rank < neighbor_rank):
            self.finish_guess(r, c, True)
        else:
            self.finish_guess(r, c, False)

    def ask_in_between(self, r, c, n1, n2):
        """Open a window to ask for an in-between/outside guess."""
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

    def collect_connected_open_cards(self, start_pos):
        """Return all face-up cards connected (adjacent) to the start position."""
        visited = set()
        stack = []
        for neighbor in adjacent_positions(start_pos):
            nr, nc = neighbor
            if self.face_up[nr][nc]:
                visited.add(neighbor)
                stack.append(neighbor)
        while stack:
            current = stack.pop()
            for neighbor in adjacent_positions(current):
                if neighbor not in visited:
                    nr, nc = neighbor
                    if self.face_up[nr][nc]:
                        visited.add(neighbor)
                        stack.append(neighbor)
        return visited

    def finish_guess(self, r, c, is_correct):
        current_player = self.current_player()
        if is_correct:
            # Correct guess: reveal card and update correct-guess counters.
            self.face_up[r][c] = True
            self.player_correct_guesses[current_player] += 1
            self.must_select_adjacent_to_handle = False
            self.update_ui()
            # Enable the "End Turn" button so the player may stop his turn.
            self.stop_turn_button.config(state=tk.NORMAL)
            if self.check_game_end():
                return
            self.info_label.config(text=f"{current_player}'s turn continues. You may end your turn using the button.")
        else:
            # Wrong guess: remove the guessed card and all connected open cards.
            connected = self.collect_connected_open_cards((r, c))
            total_removed = set(connected)
            total_removed.add((r, c))
            penalty = len(total_removed)
            self.drink_count[current_player] += penalty
            for pos in total_removed:
                rr, cc = pos
                cid = self.card_grid[rr][cc]
                if cid is not None:
                    self.deck.append(cid)
                self.card_grid[rr][cc] = None
                self.face_up[rr][cc] = False
            if HANDLE_POSITION in total_removed:
                self.must_select_adjacent_to_handle = True
            else:
                self.must_select_adjacent_to_handle = False
            # On a wrong guess the turn must continue; disable "End Turn" button.
            self.stop_turn_button.config(state=tk.DISABLED)
            random.shuffle(self.deck)
            self.redeal_spots()
            self.update_ui()
            self.info_label.config(text=f"Wrong guess! {current_player} drinks {penalty}. {current_player} goes again.")

    def end_turn(self):
        """Called when the player clicks the 'End Turn' button.
        Compute the net change in face-up cards during the turn and update the stats."""
        current_player = self.current_player()
        delta = self.count_face_up_cards() - self.turn_start_face_up
        self.player_changed_cards[current_player] += delta
        self.next_player()

    def redeal_spots(self):
        """Redeal empty spots in the layout.
        Corners and handle are always redealt face-up, others face-down."""
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
        """Check if all valid card slots are face-up; if so, end the game."""
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c]:
                    if not self.face_up[r][c]:
                        return False
        messagebox.showinfo("Game Over", "All cards are face-up! Game ends.")
        if messagebox.askyesno("Play Again?", "Start a new game?"):
            self.reset_game()
        else:
            self.root.quit()
        return True

    def reset_game(self):
        """Reset the game for a new round."""
        self.deck = create_deck()
        random.shuffle(self.deck)
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c]:
                    self.card_grid[r][c] = None
                    self.face_up[r][c] = False
        self.deal_initial_cards()
        self.must_select_adjacent_to_handle = True
        self.stop_turn_button.config(state=tk.DISABLED)
        self.update_ui()
        self.turn_start_face_up = self.count_face_up_cards()

    def current_player(self):
        return self.players[self.current_player_idx]

    def next_player(self):
        """Advance to the next player's turn.
        Record the new turn’s starting face-up count and increment the player's turn counter."""
        self.current_player_idx = (self.current_player_idx + 1) % len(self.players)
        self.info_label.config(text=f"{self.current_player()}'s turn.")
        self.turn_start_face_up = self.count_face_up_cards()
        self.player_turns[self.current_player()] += 1
        self.stop_turn_button.config(state=tk.DISABLED)
        self.update_ui()

    def update_stats_table(self):
        """Update the stats table (displayed in the right-side frame)."""
        # Clear previous table.
        for widget in self.frame_stats.winfo_children():
            widget.destroy()
        # Column headers.
        headers = ["Player", "Drinks", "Correct Guesses", "Changed Cards", "Turns"]
        for col, header in enumerate(headers):
            label = tk.Label(self.frame_stats, text=header, font=("Arial", 10, "bold"),
                             borderwidth=1, relief="solid", padx=5, pady=2)
            label.grid(row=1, column=col, sticky="nsew")
        # Rows: one per player.
        for i, player in enumerate(self.players):
            row = i + 2
            values = [
                player,
                self.drink_count[player],
                self.player_correct_guesses[player],
                self.player_changed_cards[player],
                self.player_turns[player]
            ]
            for col, val in enumerate(values):
                label = tk.Label(self.frame_stats, text=str(val), borderwidth=1, relief="solid",
                                 padx=5, pady=2)
                label.grid(row=row, column=col, sticky="nsew")
        # Add a summary row below the last player.
        sum_row = len(self.players) + 2
        total_drinks = sum(self.drink_count[p] for p in self.players)
        total_correct = sum(self.player_correct_guesses[p] for p in self.players)
        total_changed = sum(self.player_changed_cards[p] for p in self.players)
        totals = ["Total", total_drinks, total_correct, f"{total_changed} of 17", ""]
        for col, val in enumerate(totals):
            label = tk.Label(self.frame_stats, text=str(val), font=("Arial", 10, "bold"),
                             borderwidth=1, relief="solid", padx=5, pady=2)
            label.grid(row=sum_row, column=col, sticky="nsew")

    def update_ui(self):
        """Update the grid buttons and info label, then refresh the stats table."""
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
        self.update_stats_table()

if __name__ == "__main__":
    root = tk.Tk()
    # Example: three players
    players = ["Alice", "Bob", "Charlie"]
    game = WindowGame(root, players)
    root.mainloop()
