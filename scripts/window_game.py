import random, os, time, math
import tkinter as tk
from PIL import Image, ImageTk

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

DEVELOPMENT_MODE = True


def get_player_names(root):
    """Prompt the user to enter player names (comma separated)."""
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

# --- Helper for front images ---
suit_map = {"E": "Eichel", "B": "Blatt", "H": "Herz", "S": "Schelln"}
rank_map = {"6": "Sechs", "7": "Sieben", "8": "Acht", "9": "Neun", "10": "Zehn",
            "U": "Unter", "O": "Ober", "K": "Koenig", "A": "Ass"}

def card_id_to_front_filename(card_id):
    """
    Map card_id to the expected front image filename.
    For example, card_id 0 becomes "Eichel_Sechs.png".
    """
    rank = RANKS[card_id // 4]
    suit = SUITS[card_id % 4]
    return f"{suit_map[suit]}_{rank_map[rank]}.png"

# -------------------------------------------------------
# MAIN GAME CLASS
# -------------------------------------------------------
class WindowGame:
    def __init__(self, root, players):
        self.players = players
        self.confirm_window = None
        self.root = root
        self.root.title("Window Drinking Game")
        
        # Load images.
        workspace_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        # Load back image.
        back_file = os.path.join(workspace_path, "resources", "back", "back.png")
        img = Image.open(back_file)
        img = img.resize((150, 85), Image.LANCZOS)
        self.back_photo = ImageTk.PhotoImage(img)
        # Load front images into a dictionary.
        self.front_images = {}
        front_dir = os.path.join(workspace_path, "resources", "front")
        for file in os.listdir(front_dir):
            if file.endswith(".png"):
                file_path = os.path.join(front_dir, file)
                img = Image.open(file_path)
                img = img.resize((150, 85), Image.LANCZOS)
                self.front_images[file] = ImageTk.PhotoImage(img)
                
        # Players & initial statistics
        self.init_stats()

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

        # Create containers for the card buttons and store frames.
        self.buttons = []
        self.button_frames = []
        for r in range(len(WINDOW_LAYOUT)):
            btn_row = []
            frame_row = []
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c]:
                    # Each button is now inside a frame so we can change the frame border.
                    container = tk.Frame(self.frame_game, highlightthickness=0, bd=0)
                    container.grid(row=r, column=c, padx=5, pady=5)
                    b = tk.Button(container, text="",
                                  command=lambda rr=r, cc=c: self.on_card_click(rr, cc),
                                  highlightthickness=0)
                    b.pack()
                    btn_row.append(b)
                    frame_row.append(container)
                else:
                    btn_row.append(None)
                    frame_row.append(None)
            self.buttons.append(btn_row)
            self.button_frames.append(frame_row)

        # Instance variables for confirmation stages (must be set before update_ui is called).
        self.pending_removals = set()
        self.pending_new_cards = []
        self.confirm_button = None

        self.update_ui()
        # Record the starting count of face-up cards and count the turn.
        self.turn_start_face_up = self.count_face_up_cards()
        self.player_turns[self.current_player()] += 1

        # If a correct guess was made, turn can be ended.
        self.turn_can_end = False

    def init_stats(self):
        self.current_player_idx = 0
        self.drink_count = {p: 0 for p in self.players}
        self.player_correct_guesses = {p: 0 for p in self.players}
        self.player_changed_cards = {p: 0 for p in self.players}
        self.player_turns = {p: 0 for p in self.players}

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
        # Prevent card clicks if a confirmation button is active.
        if self.confirm_button is not None:
            return
        if self.face_up[r][c]:
            return
        if self.must_select_adjacent_to_handle and (r, c) not in adjacent_positions(HANDLE_POSITION):
            return
        # Only disable the End Turn button if turn-end is not allowed.
        if not self.turn_can_end:
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
            options.append(("higher-lower", "horizontal", horizontal[0]))

        if len(vertical) >= 2:
            top = min(vertical, key=lambda x: x[0])
            bottom = max(vertical, key=lambda x: x[0])
            options.append(("in-between", "vertical", (top, bottom)))
        elif len(vertical) == 1:
            options.append(("higher-lower", "vertical", vertical[0]))
        
        # Force in-between guess when available: if any option is "in-between", ignore "higher-lower" options.
        in_between_options = [opt for opt in options if opt[0] == "in-between"]
        if in_between_options:
            options = in_between_options

        if not options:
            return
        if len(options) == 1:
            opt = options[0]
            if opt[0] == "in-between":
                self.ask_in_between(r, c, opt[2][0], opt[2][1])
            elif opt[0] == "higher-lower":
                self.ask_higher_same_lower(r, c, opt[2])
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
                    return lambda: [self.ask_higher_same_lower(r, c, o[2]), choose_win.destroy()]
                tk.Button(choose_win, text=btn_text, command=make_callback()).pack(padx=5, pady=2)

    def ask_user_to_choose_boundaries(self, r, c, neighbors):
        """Ask the user to choose boundaries if two valid options exist."""
        choose_win = tk.Toplevel(self.root)
        choose_win.title("Choose Boundaries")
        choose_win.protocol("WM_DELETE_WINDOW", choose_win.destroy)
        tk.Label(choose_win, text="Select which two neighbors to use for in-between guess:").pack()
        def use_first_pair():
            self.ask_in_between(r, c, neighbors[0], neighbors[1])
            choose_win.destroy()
        def use_second_pair():
            self.ask_in_between(r, c, neighbors[1], neighbors[0])
            choose_win.destroy()
        tk.Button(choose_win, text="Option 1", command=use_first_pair).pack(side=tk.LEFT, padx=5)
        tk.Button(choose_win, text="Option 2", command=use_second_pair).pack(side=tk.RIGHT, padx=5)

    def ask_higher_same_lower(self, r, c, neighbor):
        """Open a window to ask for a higher, same, or lower guess."""
        guess_win = tk.Toplevel(self.root)
        guess_win.title("Guess Higher, Same, or Lower")
        guess_win.protocol("WM_DELETE_WINDOW", guess_win.destroy)
        tk.Label(guess_win, text="Is the selected card Higher, Same, or Lower than the neighbor?").pack()
        def guess_higher():
            self.resolve_higher_same_lower(r, c, neighbor, "higher")
            guess_win.destroy()
        def guess_same():
            self.resolve_higher_same_lower(r, c, neighbor, "same")
            guess_win.destroy()
        def guess_lower():
            self.resolve_higher_same_lower(r, c, neighbor, "lower")
            guess_win.destroy()
        tk.Button(guess_win, text="Higher", command=guess_higher).pack(side=tk.LEFT, padx=5)
        tk.Button(guess_win, text="Same", command=guess_same).pack(side=tk.LEFT, padx=5)
        tk.Button(guess_win, text="Lower", command=guess_lower).pack(side=tk.RIGHT, padx=5)

    def resolve_higher_same_lower(self, r, c, neighbor, guess):
        """Resolve a higher/same/lower guess against the neighbor card.
        
        For a correct 'same' guess, prompt a pop-up for confirmation that every other player has taken one swallow.
        """
        card_id = self.card_grid[r][c]
        neighbor_id = self.card_grid[neighbor[0]][neighbor[1]]
        card_rank = get_rank_index(card_id)
        neighbor_rank = get_rank_index(neighbor_id)
        if ((guess == "higher" and card_rank > neighbor_rank) or
            (guess == "lower" and card_rank < neighbor_rank) or
            (guess == "same" and card_rank == neighbor_rank)):
            if guess == "same":
                self.same_guess_confirmation(r, c)
            else:
                self.finish_guess(r, c, True)
        else:
            self.finish_guess(r, c, False)

    def same_guess_confirmation(self, r, c):
        """Prompt a pop-up to confirm that every other player has taken one swallow 
        after a correct 'same' guess. Upon confirmation, update drink counts accordingly.
        """
        popup = tk.Toplevel(self.root)
        popup.title("Confirm Swallow Drinking")
        current_player = self.current_player()
        msg = (
            f"Correct 'Same' guess!\n\n"
            f"All players except {current_player} must take one swallow.\n\n"
            "Confirm that everyone has taken their swallow."
        )
        tk.Label(popup, text=msg, padx=10, pady=10).pack()
        def confirm():
            for player in self.players:
                if player != current_player:
                    self.drink_count[player] += 1
            popup.destroy()
            self.finish_guess(r, c, True)
        tk.Button(popup, text="Confirm", command=confirm, padx=10, pady=10).pack()

    def ask_in_between(self, r, c, n1, n2):
        """Open a window to ask for an in-between/outside guess."""
        guess_win = tk.Toplevel(self.root)
        guess_win.title("Guess In-Between or Outside")
        guess_win.protocol("WM_DELETE_WINDOW", guess_win.destroy)
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
        """Resolve an in-between or outside guess using two neighbor cards."""
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
        """Handle the outcome of a guess.
        
        Correct guess: reveal the card, update statistics, and allow the player to end turn.
        Wrong guess: reveal the guessed card so the player can see it, then mark the card
        and connected open cards for removal with a red border and prompt confirmation via a pop-up.
        """
        current_player = self.current_player()
        if is_correct:
            # Correct guess: reveal card and update correct-guess counters.
            self.face_up[r][c] = True
            self.player_correct_guesses[current_player] += 1
            self.must_select_adjacent_to_handle = False
            self.turn_can_end = True  # Allow turn to end after a correct guess.
            self.update_ui()
            # Enable the "End Turn" button so the player may stop his turn.
            self.stop_turn_button.config(state=tk.NORMAL)
            if self.check_game_end():
                return
            self.info_label.config(text=f"{current_player}'s turn continues. You may end your turn using the button.")
        else:
            # Wrong guess: reveal the guessed card.
            self.face_up[r][c] = True
            self.update_ui()
            # Disable the End Turn button to prevent turn passing.
            self.stop_turn_button.config(state=tk.DISABLED)
            # Mark cards for removal.
            connected = self.collect_connected_open_cards((r, c))
            total_removed = set(connected)
            total_removed.add((r, c))
            penalty = len(total_removed)
            self.pending_removals = total_removed
            self.pending_penalty = penalty
            # Increase drink count for each removed card.
            self.drink_count[current_player] += penalty
            self.info_label.config(
                text="Wrong guess! Cards marked for removal. Click 'Confirm Removal' to proceed."
            )
            # Highlight the cards to be removed.
            for pos in self.pending_removals:
                rr, cc = pos
                if self.button_frames[rr][cc]:
                    self.button_frames[rr][cc].config(highlightthickness=3, highlightbackground="red")
            self.disable_card_buttons()
            # Create a pop-up window for removal confirmation.
            self.confirm_window = tk.Toplevel(self.root)
            self.confirm_window.title("Confirm Removal")
            tk.Label(
                self.confirm_window,
                text=f"Wrong guess! {current_player} must drink {penalty} drink(s). Confirm removal of marked cards."
            ).pack(padx=10, pady=10)
            self.confirm_button = tk.Button(
                self.confirm_window,
                text="Confirm Removal",
                command=self.confirm_removals
            )
            self.confirm_button.pack(padx=10, pady=10)
            # Ensure turn cannot be ended on a wrong guess.
            self.turn_can_end = False
            # Refresh the UI so that removal cards (as Labels) become clickable.
            self.update_ui()

    def confirm_removals(self):
        """After confirmation, remove the marked cards, add them back to the deck,
        and immediately redeal empty spots.
        Update the valid move flag and allow the game to continue.
        """
        # Remove red border from the frames.
        for pos in self.pending_removals:
            rr, cc = pos
            if self.button_frames[rr][cc]:
                self.button_frames[rr][cc].config(highlightthickness=0)
        # Remove the cards and add them back to the deck.
        for pos in self.pending_removals:
            rr, cc = pos
            cid = self.card_grid[rr][cc]
            if cid is not None:
                self.deck.append(cid)
            self.card_grid[rr][cc] = None
            self.face_up[rr][cc] = False

        # Update valid move flag: if the handle was among removed cards, enforce handle rule.
        if HANDLE_POSITION in self.pending_removals:
            self.must_select_adjacent_to_handle = True
        else:
            self.must_select_adjacent_to_handle = False
        if hasattr(self, 'confirm_window') and self.confirm_window is not None:
            self.confirm_window.destroy()
            self.confirm_window = None
        self.confirm_button = None
        random.shuffle(self.deck)
        # Redeal empty spots
        self.redeal_spots()
        # Clear any new cards flags to allow grey border highlighting.
        self.pending_new_cards = []
        self.pending_removals = set()
        self.update_ui()
        # Update the main info label to only indicate that the current player goes again.
        self.info_label.config(text=f"{self.current_player()} goes again.")

    def disable_card_buttons(self):
        """Override any disabling so that all card buttons remain enabled."""
        for r in range(len(self.buttons)):
            for c in range(len(self.buttons[r])):
                if self.buttons[r][c] is not None:
                    self.buttons[r][c].config(state=tk.NORMAL)


    def redeal_spots(self):
        """Redeal empty spots in the layout.
        Corners and handle are always redealt face-up, others face-down.
        Returns a list of positions where new cards were dealt.
        """
        new_cards = []
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
                        new_cards.append((r, c))
        return new_cards

    def check_game_end(self):
        """Check if all valid card slots are face-up; if so, end the game."""
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c]:
                    if not self.face_up[r][c]:
                        return False
        # Ensure the last action is visible in the stats table.
        self.update_ui()
        # Use the fireworks animation instead of the old one.
        self.show_real_fireworks_effect()
        return True

    def end_animation(self, callback, iteration=0):
        """Perform a simple end-animation on the game board and call the callback after finishing.

        The animation cycles through a few colors on the card buttons.
        """
        colors = ["yellow", "orange", "red", "purple"]
        if iteration < len(colors):
            for r in range(len(WINDOW_LAYOUT)):
                for c in range(len(WINDOW_LAYOUT[r])):
                    if WINDOW_LAYOUT[r][c] and self.buttons[r][c] is not None:
                        self.buttons[r][c].config(bg=colors[iteration])
            # Schedule the next animation step after 300ms.
            self.root.after(300, lambda: self.end_animation(callback, iteration + 1))
        else:
            # Reset buttons to their default background.
            for r in range(len(WINDOW_LAYOUT)):
                for c in range(len(WINDOW_LAYOUT[r])):
                    if WINDOW_LAYOUT[r][c] and self.buttons[r][c] is not None:
                        self.buttons[r][c].config(bg="SystemButtonFace")
            callback()

    def show_real_fireworks_effect(self):
        """Display a full-screen fireworks effect and then prompt for you won."""
        fireworks_win = tk.Toplevel(self.root)
        fireworks_win.overrideredirect(True)
        fireworks_win.attributes("-topmost", True)
        width = self.root.winfo_screenwidth()
        height = self.root.winfo_screenheight()
        fireworks_win.geometry(f"{width}x{height}+0+0")
        canvas = tk.Canvas(fireworks_win, bg="black", highlightthickness=0)
        canvas.pack(fill="both", expand=True)

        # Display "You Won" at the top center.
        canvas.create_text(width // 2, height // 8, text="You Won", fill="white",
                        font=("Arial", 100, "bold"))

        start_time = time.time()
        effect_duration = 5  # seconds

        def launch_rocket():
            """Launch a single rocket with trail and explosion effect."""
            rocket_x = random.randint(100, width - 100)
            rocket_y = height
            rocket_size = 5
            rocket = canvas.create_oval(
                rocket_x - rocket_size, rocket_y - rocket_size,
                rocket_x + rocket_size, rocket_y + rocket_size,
                fill="white", outline="white"
            )
            rocket_speed = random.randint(12, 15)
            explosion_height = random.randint(height // 4, height // 2)

            def animate_rocket():
                nonlocal rocket_y
                if rocket_y > explosion_height:
                    current_y = rocket_y
                    rocket_y -= rocket_speed
                    canvas.move(rocket, 0, -rocket_speed)
                    # Create a brief trail effect
                    trail = canvas.create_oval(
                        rocket_x - 2, current_y - 2,
                        rocket_x + 2, current_y + 2,
                        fill="yellow", outline=""
                    )
                    canvas.after(100, lambda: canvas.delete(trail))
                    canvas.after(20, animate_rocket)
                else:
                    canvas.delete(rocket)
                    create_explosion(rocket_x, rocket_y)
            animate_rocket()

        def create_explosion(x, y):
            """Create an explosion effect at (x, y) with particles."""
            num_particles = 20
            particles = []
            for _ in range(num_particles):
                angle = random.uniform(0, 2 * math.pi)
                speed = random.uniform(4, 10)
                dx = speed * math.cos(angle)
                dy = speed * math.sin(angle) - 10
                color = "#%06x" % random.randint(0, 0xFFFFFF)
                particle = {
                    "id": canvas.create_oval(x, y, x + 2, y + 2, fill=color, outline=color),
                    "x": x,
                    "y": y,
                    "dx": dx,
                    "dy": dy,
                    "life": random.randint(30, 60)
                }
                particles.append(particle)

            def animate_explosion():
                nonlocal particles
                alive_particles = []
                for particle in particles:
                    particle["x"] += particle["dx"]
                    particle["y"] += particle["dy"]
                    particle["dy"] += 0.5
                    canvas.coords(
                        particle["id"],
                        particle["x"],
                        particle["y"],
                        particle["x"] + 4,
                        particle["y"] + 4
                    )
                    particle["life"] -= 1
                    if particle["life"] > 0:
                        alive_particles.append(particle)
                    else:
                        canvas.delete(particle["id"])
                particles = alive_particles
                if particles:
                    canvas.after(30, animate_explosion)
            animate_explosion()

        def launch_burst():
            """Launch a burst of rockets with random delays."""
            for _ in range(10):
                delay = random.randint(0, 500)
                fireworks_win.after(delay, launch_rocket)

        def schedule_burst():
            """Schedule bursts until the effect duration is reached."""
            if time.time() - start_time < effect_duration:
                launch_burst()
                fireworks_win.after(1500, schedule_burst)

        schedule_burst()

        # End the fireworks effect after effect_duration + delay.
        fireworks_win.after((effect_duration + 1) * 1000, lambda: (fireworks_win.destroy(), self.end_game_popup()))

    def end_game_popup(self):
        """Show game over popup and prompt to start a new game."""
        from tkinter import messagebox  # Ensure messagebox is imported
        messagebox.showinfo("Game Over", "All cards are face-up! Game ends.")
        if messagebox.askyesno("Play Again?", "Start a new game?"):
            self.reset_game()
        else:
            self.root.quit()

    def reset_game(self):
        """Reset the game for a new round, including all player statistics."""
        self.init_stats()

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
        # Reset turn end flag.
        self.turn_can_end = False
        # Update the starting face-up count BEFORE refreshing the UI.
        self.turn_start_face_up = self.count_face_up_cards()
        self.update_ui()

    def current_player(self):
        """Return the current player's name."""
        return self.players[self.current_player_idx]

    def next_player(self):
        """Advance to the next player's turn.
        Record the new turn’s starting face-up count and increment the player's turn counter.
        """
        self.current_player_idx = (self.current_player_idx + 1) % len(self.players)
        self.info_label.config(text=f"{self.current_player()}'s turn.")
        self.turn_start_face_up = self.count_face_up_cards()
        self.player_turns[self.current_player()] += 1
        self.stop_turn_button.config(state=tk.DISABLED)
        # Reset turn end flag at start of turn.
        self.turn_can_end = False
        self.update_ui()

    def end_turn(self):
        """Called when the player clicks the 'End Turn' button.
        Compute the net change in face-up cards during the turn and update the stats.
        """
        current_player = self.current_player()
        delta = self.count_face_up_cards() - self.turn_start_face_up
        self.player_changed_cards[current_player] += delta
        self.next_player()

    def update_stats_table(self):
        """Update the stats table (displayed in the right-side frame) with real-time changes.

        The 'Changed Cards' column is updated continuously for the current player's turn.
        """
        # Clear previous table.
        for widget in self.frame_stats.winfo_children():
            widget.destroy()
        # Column headers.
        headers = ["Player", "Drinks", "Correct Guesses", "Changed Cards", "Turns"]
        for col, header in enumerate(headers):
            label = tk.Label(
                self.frame_stats,
                text=header,
                font=("Arial", 10, "bold"),
                borderwidth=1,
                relief="solid",
                padx=5,
                pady=2
            )
            label.grid(row=1, column=col, sticky="nsew")
        total_changed = 0
        # Rows: one per player.
        for i, player in enumerate(self.players):
            row = i + 2
            if player == self.current_player():
                # For the current player, add the difference since the turn began.
                if hasattr(self, "turn_start_face_up"):
                    delta = self.count_face_up_cards() - self.turn_start_face_up
                else:
                    delta = 0
                changed = self.player_changed_cards[player] + delta
            else:
                changed = self.player_changed_cards[player]
            total_changed += changed
            values = [
                player,
                self.drink_count[player],
                self.player_correct_guesses[player],
                changed,
                self.player_turns[player]
            ]
            for col, val in enumerate(values):
                label = tk.Label(
                    self.frame_stats,
                    text=str(val),
                    borderwidth=1,
                    relief="solid",
                    padx=5,
                    pady=2
                )
                label.grid(row=row, column=col, sticky="nsew")
        # Summary row.
        sum_row = len(self.players) + 2
        total_drinks = sum(self.drink_count[p] for p in self.players)
        total_correct = sum(self.player_correct_guesses[p] for p in self.players)
        totals = ["Total", total_drinks, total_correct, f"{total_changed} of 17", ""]
        for col, val in enumerate(totals):
            label = tk.Label(
                self.frame_stats,
                text=str(val),
                font=("Arial", 10, "bold"),
                borderwidth=1,
                relief="solid",
                padx=5,
                pady=2
            )
            label.grid(row=sum_row, column=col, sticky="nsew")

    def update_ui(self):
        """Update the grid buttons and info label, then refresh the stats table.
        
        Additionally, set a grey border on selectable (clickable) cards:
        - A card is selectable if it is face-down and either:
          * When the 'handle rule' applies, it is adjacent to the handle.
          * Otherwise, it has at least one face-up adjoining card.
        Cards that are face-up or not selectable do not get a grey border.
        Note: If a card is marked for removal (red) or is new (green), its border is not changed.
        """
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if not WINDOW_LAYOUT[r][c]:
                    continue
                container = self.button_frames[r][c]
                # Always use Button widget.
                if not isinstance(self.buttons[r][c], tk.Button):
                    self.buttons[r][c].destroy()
                    self.buttons[r][c] = tk.Button(
                        container, command=lambda rr=r, cc=c: self.on_card_click(rr, cc)
                    )
                    self.buttons[r][c].pack()
                widget = self.buttons[r][c]
                card_id = self.card_grid[r][c]
                if card_id is not None:
                    if self.face_up[r][c]:
                        filename = card_id_to_front_filename(card_id)
                        if filename in self.front_images:
                            widget.config(image=self.front_images[filename], text="")
                        else:
                            widget.config(text=card_id_to_label(card_id))
                    else:
                        widget.config(image=self.back_photo, text="")
                    # Ensure the widget is enabled and clickable.
                    widget.config(state=tk.NORMAL, command=lambda rr=r, cc=c: self.on_card_click(rr, cc))
                else:
                    widget.config(text=" ", image="", state=tk.DISABLED)
                # Highlight pending removal cards with a red border;
                # otherwise, apply grey border if the card is selectable.
                if (r, c) in self.pending_removals:
                    container.config(highlightthickness=3, highlightbackground="red")
                else:
                    if self.face_up[r][c]:
                        container.config(highlightthickness=0)
                    else:
                        # Determine if the card is selectable.
                        if self.must_select_adjacent_to_handle:
                            selectable = (r, c) in adjacent_positions(HANDLE_POSITION)
                        else:
                            selectable = any(self.face_up[nr][nc] for nr, nc in adjacent_positions((r, c)))
                        if selectable:
                            container.config(highlightthickness=3, highlightbackground="grey")
                        else:
                            container.config(highlightthickness=0)
        self.info_label.config(text=f"{self.current_player()}'s turn.")
        self.update_stats_table()

if __name__ == "__main__":
    root = tk.Tk()
    # If not in development mode, ask the user for player names.
    if DEVELOPMENT_MODE:
        players = ["Alice", "Bob", "Charlie"]
    else:
        # Hide main window until players are set.
        root.withdraw()
        players = get_player_names(root)
        if not players:
            players = ["Player1"]
        root.deiconify()
    game = WindowGame(root, players)
    root.mainloop()
