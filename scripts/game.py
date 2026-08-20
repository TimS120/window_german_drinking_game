"""
Main game logic and UI implementation for the Window Drinking Game.
"""

import os
import random
import time
import math
import tkinter as tk
from PIL import Image, ImageTk

if __package__:
    from .config import WINDOW_LAYOUT, HANDLE_POSITION
    from .core_game import CoreWindowGame
    from .utils import (
        card_id_to_label,
        adjacent_positions,
        card_id_to_front_filename,
    )
else:
    from config import WINDOW_LAYOUT, HANDLE_POSITION
    from core_game import CoreWindowGame
    from utils import (
        card_id_to_label,
        adjacent_positions,
        card_id_to_front_filename,
    )


new_sizes = 0

class WindowGame:
    """
    Class representing the Window Drinking Game.
    """

    _ENGINE_ATTRIBUTES = {
        "players", "deck", "card_grid", "face_up", "pending_removals",
        "pending_penalty", "must_select_adjacent_to_handle", "turn_can_end",
        "turn_start_face_up", "current_player_idx", "drink_count",
        "correct_guess_count", "wrong_guess_count", "player_changed_cards",
        "player_turns",
    }

    def __getattr__(self, name):
        game = self.__dict__.get("game")
        if game is not None and name in self._ENGINE_ATTRIBUTES:
            return getattr(game, name)
        raise AttributeError(name)

    def __init__(self, root, players, advisor_config=None):
        """
        Initialize the game with the given players and UI.

        Args:
            root (tk.Tk): The main Tkinter window.
            players (list): List of player names.
        """
        self.root = root
        self.root.title("Window Drinking Game")
        self.game = CoreWindowGame(players=players)
        self.advisor = None
        self.advisor_formatter = None
        self.advisor_error = None
        self.advisor_config = (
            advisor_config
            if advisor_config is not None
            else self.load_default_advisor_config()
        )
        self.suggestion_position = None
        self.confirm_window = None
        self.ui_locked = False
        self.card_border_width = 3
        self.card_border_inactive_color = self.root.cget("bg")

        self.init_images()
        self.correct_wrong_guess_ratio = {p: 0 for p in self.players}
        self.build_ui()

        # For confirmation stages.
        self.pending_new_cards = []
        self.confirm_button = None

        self.initialize_advisor()
        self.update_ui()

    def init_images(self):
        """
        Load and process back and front images for the cards, resizing them dynamically
        based on the screen size.
        """
        workspace_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        back_file = os.path.join(workspace_path, "resources", "back", "back.png")
        
        # Get screen size
        screen_width = self.root.winfo_screenwidth()
        screen_height = self.root.winfo_screenheight()

        # Calculate proportional image size
        max_width = screen_width // 8  # TODO: Find way without workaround. Becaus the number 8 is arbitrary set because it fitted
        max_height = screen_height // 8  # TODO: Find way without workaround. Becaus the number 8 is arbitrary set because it fitted

        img = Image.open(back_file)
        img = img.rotate(90, expand=True)

        old_sizes = img.size
        width_ratio = old_sizes[0] / max_width
        height_ratio = old_sizes[1] / max_height

        global new_sizes
        if(width_ratio > height_ratio):
            new_sizes = (int(old_sizes[0] * (1 / width_ratio)), int(old_sizes[1] * (1 / width_ratio)))
        else:
            new_sizes = (int(old_sizes[0] * (1 / height_ratio)), int(old_sizes[1] * (1 / height_ratio)))

        img = img.resize(new_sizes, Image.LANCZOS)
        self.back_photo = ImageTk.PhotoImage(img)

        self.front_images = {}
        front_dir = os.path.join(workspace_path, "resources", "front")
        for file in os.listdir(front_dir):
            if file.endswith(".png"):
                file_path = os.path.join(front_dir, file)
                img = Image.open(file_path)
                img = img.rotate(90, expand=True)
                img = img.resize(new_sizes, Image.LANCZOS)
                self.front_images[file] = ImageTk.PhotoImage(img)

    def init_stats(self):
        """
        Initialize player statistics.
        """
        self.correct_wrong_guess_ratio = {p: 0 for p in self.players}
        self.game.init_stats()

    def init_grids(self):
        """
        Initialize the card grid and face-up status grid.
        """
        self.game.init_grids()

    def deal_initial_cards(self):
        """
        Deal cards from the deck into the layout.
        Corners and the handle are dealt face-up.
        """
        self.game.deal_initial_cards()

    def count_face_up_cards(self):
        """
        Count and return the number of face-up cards in the grid.

        Returns:
            int: Count of face-up cards.
        """
        return self.game.count_face_up_cards()

    def build_ui(self):
        """
        Build the user interface components.
        """
        # Configure grid layout
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)

        self.frame_top = tk.Frame(self.root)
        self.frame_top.pack(side=tk.TOP, fill=tk.X)

        self.frame_center = tk.Frame(self.root)
        self.frame_center.pack(side=tk.TOP, fill=tk.BOTH, expand=True)

        self.frame_game = tk.Frame(self.frame_center)
        self.frame_game.pack(side=tk.LEFT, padx=5, pady=5, fill=tk.BOTH, expand=True)
        self.card_border_inactive_color = self.frame_game.cget("bg")

        self.frame_stats = tk.Frame(self.frame_center)
        self.frame_stats.pack(side=tk.RIGHT, padx=5, pady=5, fill=tk.BOTH, expand=True)

        self.frame_bottom = tk.Frame(self.root)
        self.frame_bottom.pack(side=tk.BOTTOM, fill=tk.X)

        self.info_label = tk.Label(self.frame_bottom, text="", font=("Arial", 12))
        self.info_label.pack(side=tk.LEFT, padx=5)

        self.stop_turn_button = tk.Button(
            self.frame_bottom, text="End Turn", command=self.end_turn, state=tk.DISABLED
        )
        self.stop_turn_button.pack(side=tk.RIGHT, padx=5)

        self.reset_game_button = tk.Button(
            self.frame_bottom, text="Reset Game", command=self.confirm_reset_game
        )
        self.reset_game_button.pack(side=tk.RIGHT, padx=5)

        self.suggestion_button = tk.Button(
            self.frame_bottom,
            text="Show model suggestion",
            command=self.show_model_suggestion,
            state=tk.NORMAL,
        )
        self.suggestion_button.pack(side=tk.RIGHT, padx=5)

        # Make all frames expandable
        self.frame_center.columnconfigure(0, weight=3)
        self.frame_center.columnconfigure(1, weight=1)
        self.frame_center.rowconfigure(0, weight=1)

        # Initialize buttons before adjusting their size
        self.initialize_card_buttons()

        # Adjust button sizes dynamically
        self.adjust_button_sizes()

    @staticmethod
    def load_default_advisor_config():
        """Load desktop advisor settings even when WindowGame is used directly."""
        import json

        repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
        config_path = os.path.join(repo_root, "configs", "simulation_config.json")
        try:
            with open(config_path, encoding="utf-8-sig") as config_file:
                return json.load(config_file).get("advisor", {})
        except (OSError, ValueError):
            return {}

    def initialize_advisor(self):
        """Load the configured model and prepare advice for the initial board."""
        if not self.advisor_config.get("enabled", False):
            self.advisor_error = "Model suggestions are disabled in simulation_config.json."
            self.suggestion_button.config(state=tk.NORMAL)
            return
        try:
            if __package__:
                from .advisor import AdvisorSession, format_suggestion
            else:
                from advisor import AdvisorSession, format_suggestion
            self.advisor = AdvisorSession(
                model_path=self.advisor_config.get("model_path"),
                deterministic=self.advisor_config.get("deterministic", True),
            )
            self.advisor_formatter = format_suggestion
            self.advisor.reset(self.game)
            self.advisor_error = None
            self.suggestion_button.config(state=tk.NORMAL)
        except Exception as exc:
            self.advisor = None
            self.advisor_error = str(exc)
            self.suggestion_button.config(state=tk.NORMAL)
            self.info_label.config(text=f"Model advisor unavailable: {exc}")

    def record_advisor_transition(self, event):
        """Feed exactly one completed, actual user transition to model memory."""
        if self.advisor is None:
            return
        try:
            self.advisor.observe_transition(self.game, event)
        except Exception as exc:
            self.advisor_error = str(exc)
            self.advisor = None
            self.suggestion_button.config(state=tk.NORMAL)
            self.info_label.config(text=f"Model advisor unavailable: {exc}")

    def show_model_suggestion(self):
        """Display cached advice without changing game or recurrent state."""
        if self.advisor is None:
            if self.advisor_config.get("enabled", False):
                self.initialize_advisor()
        if self.advisor is None:
            self.info_label.config(
                text=f"Model advisor unavailable: {self.advisor_error or 'not configured'}"
            )
            return
        suggestion = self.advisor.current_suggestion()
        self.suggestion_position = suggestion["position"] if suggestion else None
        self.info_label.config(text=self.advisor_formatter(suggestion))
        self.update_ui()

    def clear_suggestion_display(self):
        self.suggestion_position = None

    def initialize_card_buttons(self):
        """
        Initialize the buttons grid before adjusting sizes.
        """
        self.buttons = []
        self.button_frames = []
        for r in range(len(WINDOW_LAYOUT)):
            btn_row = []
            frame_row = []
            for c in range(len(WINDOW_LAYOUT[r])):
                if WINDOW_LAYOUT[r][c]:
                    container = tk.Frame(
                        self.frame_game,
                        highlightthickness=self.card_border_width,
                        highlightbackground=self.card_border_inactive_color,
                        highlightcolor=self.card_border_inactive_color,
                        bd=0
                    )
                    container.grid(row=r, column=c, padx=5, pady=5)
                    b = tk.Button(
                        container,
                        text="",
                        command=lambda rr=r, cc=c: self.on_card_click(rr, cc),
                        highlightthickness=0,
                    )
                    b.pack()
                    btn_row.append(b)
                    frame_row.append(container)
                else:
                    btn_row.append(None)
                    frame_row.append(None)
            self.buttons.append(btn_row)
            self.button_frames.append(frame_row)

    def adjust_button_sizes(self):
        """
        Adjust button sizes based on screen resolution without cropping images.
        """
        if not hasattr(self, "buttons") or not self.buttons:
            return

        for r in range(len(self.buttons)):
            for c in range(len(self.buttons[r])):
                if self.buttons[r][c]:
                    self.buttons[r][c].config(width=new_sizes[0], height=new_sizes[1])

    def on_card_click(self, r, c):
        """
        Handle clicking on a card at grid position (r, c).

        Args:
            r (int): Row index.
            c (int): Column index.
        """
        if self.ui_locked or self.confirm_button is not None or self.face_up[r][c]:
            return
        if self.must_select_adjacent_to_handle and (r, c) not in adjacent_positions(HANDLE_POSITION):
            return
        if not self.turn_can_end:
            self.stop_turn_button.config(state=tk.DISABLED)

        options = self.game.get_valid_options_for_card(r, c)
        if not options:
            return

        if not self.lock_user_interaction():
            return

        if len(options) == 1:
            opt = options[0]
            if opt.type == "in-between":
                self.ask_in_between(
                    r, c, opt.neighbors[0], opt.neighbors[1], opt.orientation
                )
            elif opt.type == "higher-lower":
                self.ask_higher_same_lower(r, c, opt.neighbors, opt.orientation)
            return

        choose_win = tk.Toplevel(self.root)
        choose_win.title("Choose Guess Option")
        self.make_modal(choose_win)
        closed_without_choice = {"done": False}

        def close_choose_window():
            if closed_without_choice["done"]:
                return
            closed_without_choice["done"] = True
            choose_win.destroy()
            self.unlock_user_interaction()

        choose_win.protocol("WM_DELETE_WINDOW", close_choose_window)
        tk.Label(choose_win, text="Select a guessing option:").pack(padx=5, pady=5)
        for opt in options:
            if opt.type == "in-between":
                btn_text = f"In-between ({opt.orientation} boundaries)"
                def make_callback(o=opt):
                    def callback():
                        if closed_without_choice["done"]:
                            return
                        closed_without_choice["done"] = True
                        choose_win.destroy()
                        self.ask_in_between(
                            r, c, o.neighbors[0], o.neighbors[1], o.orientation
                        )
                    return callback
                tk.Button(choose_win, text=btn_text, command=make_callback()).pack(padx=5, pady=2)
            elif opt.type == "higher-lower":
                btn_text = f"Higher/Lower ({opt.orientation} neighbor)"
                def make_callback(o=opt):
                    def callback():
                        if closed_without_choice["done"]:
                            return
                        closed_without_choice["done"] = True
                        choose_win.destroy()
                        self.ask_higher_same_lower(
                            r, c, o.neighbors, o.orientation
                        )
                    return callback
                tk.Button(choose_win, text=btn_text, command=make_callback()).pack(padx=5, pady=2)

    def ask_higher_same_lower(self, r, c, neighbor, orientation):
        """
        Open a prompt window to ask the user for a Higher/Same/Lower guess.

        Args:
            r (int): Row index of the card.
            c (int): Column index of the card.
            neighbor (tuple): The neighbor card position.
        """
        guess_win = tk.Toplevel(self.root)
        guess_win.title("Guess Higher, Same, or Lower")
        self.make_modal(guess_win)
        resolved = {"done": False}

        def close_without_guess():
            if resolved["done"]:
                return
            resolved["done"] = True
            guess_win.destroy()
            self.unlock_user_interaction()

        guess_win.protocol("WM_DELETE_WINDOW", close_without_guess)
        tk.Label(guess_win, text="Is the selected card Higher, Same, or Lower than the neighbor?").pack()

        def make_choice(choice):
            if resolved["done"]:
                return
            resolved["done"] = True
            guess_win.destroy()
            self.resolve_higher_same_lower(r, c, neighbor, choice, orientation)

        tk.Button(
            guess_win,
            text="Higher",
            command=lambda: make_choice("higher")
        ).pack(side=tk.LEFT, padx=5)
        tk.Button(
            guess_win,
            text="Same",
            command=lambda: make_choice("same")
        ).pack(side=tk.LEFT, padx=5)
        tk.Button(
            guess_win,
            text="Lower",
            command=lambda: make_choice("lower")
        ).pack(side=tk.RIGHT, padx=5)

    def resolve_higher_same_lower(self, r, c, neighbor, guess, orientation=None):
        """
        Resolve a higher/same/lower guess against the neighbor card.

        Args:
            r (int): Row index of the selected card.
            c (int): Column index of the selected card.
            neighbor (tuple): Position of the neighbor card.
            guess (str): The guess type ("higher", "same", or "lower").
        """
        self.commit_user_action((r, c), guess, orientation)

    def same_guess_confirmation(self, result):
        """
        Prompt for confirmation that every other player has taken a swallow after a correct 'same' guess.

        Args:
            r (int): Row index of the selected card.
            c (int): Column index of the selected card.
        """
        popup = tk.Toplevel(self.root)
        popup.title("Confirm Swallow Drinking")
        self.make_modal(popup)
        current_player = self.current_player()
        msg = (
            f"Correct 'Same' guess!\n\n"
            f"All players except {current_player} must take one swallow.\n\n"
            "Confirm that everyone has taken their swallow."
        )
        tk.Label(popup, text=msg, padx=10, pady=10).pack()
        def confirm():
            popup.destroy()
            self.handle_committed_action(result)
        popup.protocol("WM_DELETE_WINDOW", lambda: None)
        tk.Button(popup, text="Confirm", command=confirm, padx=10, pady=10).pack()

    def ask_in_between(self, r, c, n1, n2, orientation):
        """
        Open a window to ask for an In-Between or Outside guess.

        Args:
            r (int): Row index of the card.
            c (int): Column index of the card.
            n1 (tuple): Position of first neighbor.
            n2 (tuple): Position of second neighbor.
        """
        guess_win = tk.Toplevel(self.root)
        guess_win.title("Guess In-Between or Outside")
        self.make_modal(guess_win)
        resolved = {"done": False}

        def close_without_guess():
            if resolved["done"]:
                return
            resolved["done"] = True
            guess_win.destroy()
            self.unlock_user_interaction()

        guess_win.protocol("WM_DELETE_WINDOW", close_without_guess)
        tk.Label(guess_win, text="Is the card In-Between or Outside these two?").pack()

        def make_choice(is_in_between):
            if resolved["done"]:
                return
            resolved["done"] = True
            guess_win.destroy()
            self.resolve_in_between(r, c, n1, n2, is_in_between, orientation)

        tk.Button(
            guess_win,
            text="In-Between",
            command=lambda: make_choice(True)
        ).pack(side=tk.LEFT, padx=10)
        tk.Button(
            guess_win,
            text="Outside",
            command=lambda: make_choice(False)
        ).pack(side=tk.RIGHT, padx=10)

    def resolve_in_between(self, r, c, n1, n2, guess_in, orientation=None):
        """
        Resolve an in-between/outside guess.

        Args:
            r (int): Row index of the card.
            c (int): Column index of the card.
            n1 (tuple): Position of first neighbor.
            n2 (tuple): Position of second neighbor.
            guess_in (bool): True if guessing "in-between", False for "outside".
        """
        guess = "in-between" if guess_in else "outside"
        self.commit_user_action((r, c), guess, orientation)

    def commit_user_action(self, position, guess, orientation=None):
        """Commit only the action the user actually selected."""
        self.clear_suggestion_display()
        result = self.game.begin_action(position, guess, orientation)
        if "event" not in result:
            self.info_label.config(text=result.get("debug", "Invalid action."))
            self.unlock_user_interaction()
            return
        if guess == "same" and result["event"]["correct"]:
            self.same_guess_confirmation(result)
            return
        self.handle_committed_action(result)

    def handle_committed_action(self, result):
        """Render a committed core transition or its pending removal stage."""
        event = result["event"]
        if result.get("awaiting_confirmation"):
            current_player = self.current_player()
            penalty = event["penalty"]
            self.update_ui()
            self.stop_turn_button.config(state=tk.DISABLED)
            self.info_label.config(
                text="Wrong guess! Cards marked for removal. Confirm removal to proceed."
            )
            self.disable_card_buttons()
            self.confirm_window = tk.Toplevel(self.root)
            self.confirm_window.title("Confirm Removal")
            self.make_modal(self.confirm_window)
            tk.Label(
                self.confirm_window,
                text=(
                    f"Wrong guess! {current_player} must drink {penalty} drink(s). "
                    "Confirm removal of marked cards."
                ),
            ).pack(padx=10, pady=10)
            self.confirm_button = tk.Button(
                self.confirm_window,
                text="Confirm Removal",
                command=self.confirm_removals,
            )
            self.confirm_button.pack(padx=10, pady=10)
            self.confirm_window.protocol("WM_DELETE_WINDOW", lambda: None)
            return

        self.record_advisor_transition(event)
        self.update_ui()
        if result["done"]:
            self.unlock_user_interaction()
            self.show_real_fireworks_effect()
            return
        self.info_label.config(
            text=(
                f"{self.current_player()}'s turn continues. "
                "You may end your turn using the button."
            )
        )
        self.unlock_user_interaction()

    def collect_connected_open_cards(self, start_pos):
        return self.game.collect_connected_open_cards(start_pos)

    def confirm_removals(self):
        """
        Confirm removal of the marked cards, add them back to the deck,
        redeal empty spots, and update the game state.
        """
        removed_positions = set(self.pending_removals)
        for pos in removed_positions:
            rr, cc = pos
            if self.button_frames[rr][cc]:
                self.button_frames[rr][cc].config(
                    highlightbackground=self.card_border_inactive_color,
                    highlightcolor=self.card_border_inactive_color
                )
        result = self.game.confirm_action_removals()
        if self.confirm_window is not None:
            self.confirm_window.destroy()
            self.confirm_window = None
        self.confirm_button = None
        self.pending_new_cards = []
        self.record_advisor_transition(result["event"])
        self.update_ui()
        self.info_label.config(text=f"{self.current_player()} goes again.")
        self.unlock_user_interaction()

    def disable_card_buttons(self):
        """
        Disable all card buttons.
        """
        for r in range(len(self.buttons)):
            for c in range(len(self.buttons[r])):
                if self.buttons[r][c] is not None:
                    self.buttons[r][c].config(state=tk.DISABLED)
        if hasattr(self, "suggestion_button"):
            self.suggestion_button.config(state=tk.DISABLED)

    def lock_user_interaction(self):
        """
        Lock card interactions while a decision popup is active.
        """
        if self.ui_locked:
            return False
        self.ui_locked = True
        self.disable_card_buttons()
        self.stop_turn_button.config(state=tk.DISABLED)
        return True

    def unlock_user_interaction(self):
        """
        Unlock card interactions after popup flow is finished or canceled.
        """
        if not self.ui_locked:
            return
        self.ui_locked = False
        self.update_ui()
        self.suggestion_button.config(state=tk.NORMAL)
        if self.turn_can_end and self.confirm_button is None:
            self.stop_turn_button.config(state=tk.NORMAL)

    def make_modal(self, window):
        """
        Configure a popup as modal so background widgets cannot be clicked.
        """
        window.transient(self.root)
        window.grab_set()
        window.focus_force()

    def redeal_spots(self):
        """
        Redeal empty spots in the layout.
        Corners and handle are always redealt face-up.

        Returns:
            list: Positions where new cards were dealt.
        """
        return self.game.redeal_spots()

    def check_game_end(self):
        """
        Check whether all valid card slots are face-up.
        If so, trigger the fireworks effect and end the game.

        Returns:
            bool: True if the game has ended; False otherwise.
        """
        return self.game.check_game_end()

    def end_animation(self, callback, iteration=0):
        """
        Perform a simple end-animation by cycling button colors, then call a callback.

        Args:
            callback (callable): Function to call after animation ends.
            iteration (int, optional): Current iteration count. Defaults to 0.
        """
        colors = ["yellow", "orange", "red", "purple"]
        if iteration < len(colors):
            for r in range(len(WINDOW_LAYOUT)):
                for c in range(len(WINDOW_LAYOUT[r])):
                    if WINDOW_LAYOUT[r][c] and self.buttons[r][c] is not None:
                        self.buttons[r][c].config(bg=colors[iteration])
            self.root.after(300, lambda: self.end_animation(callback, iteration + 1))
        else:
            for r in range(len(WINDOW_LAYOUT)):
                for c in range(len(WINDOW_LAYOUT[r])):
                    if WINDOW_LAYOUT[r][c] and self.buttons[r][c] is not None:
                        self.buttons[r][c].config(bg="SystemButtonFace")
            callback()

    def show_real_fireworks_effect(self):
        """
        Display a full-screen fireworks effect and then prompt for game end.
        """
        fireworks_win = tk.Toplevel(self.root)
        fireworks_win.overrideredirect(True)
        fireworks_win.attributes("-topmost", True)
        width = self.root.winfo_screenwidth()
        height = self.root.winfo_screenheight()
        fireworks_win.geometry(f"{width}x{height}+0+0")
        canvas = tk.Canvas(fireworks_win, bg="black", highlightthickness=0)
        canvas.pack(fill="both", expand=True)
        canvas.create_text(width // 2, height // 8, text="You Won", fill="white",
                           font=("Arial", 100, "bold"))
        start_time = time.time()
        effect_duration = 5  # seconds

        def launch_rocket():
            """
            Launch a single rocket with trail and explosion effect.
            """
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
            """
            Create an explosion effect at (x, y) using particles.
            """
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
            """
            Launch a burst of rockets with random delays.
            """
            for _ in range(10):
                delay = random.randint(0, 500)
                fireworks_win.after(delay, launch_rocket)

        def schedule_burst():
            """
            Schedule bursts until the effect duration is reached.
            """
            if time.time() - start_time < effect_duration:
                launch_burst()
                fireworks_win.after(1500, schedule_burst)

        schedule_burst()
        fireworks_win.after((effect_duration + 1) * 1000,
                            lambda: (fireworks_win.destroy(), self.end_game_popup()))

    def end_game_popup(self):
        """
        Display an end-game popup and prompt to start a new game.
        """
        from tkinter import messagebox
        messagebox.showinfo("Game Over", "All cards are face-up! Game ends.")
        if messagebox.askyesno("Play Again?", "Start a new game?"):
            self.reset_game()
        else:
            self.root.quit()

    def reset_game(self):
        """
        Reset the game state for a new round, including statistics and card grids.
        """
        self.game.reset_game()
        self.correct_wrong_guess_ratio = {p: 0 for p in self.players}
        self.clear_suggestion_display()
        if self.advisor is not None:
            self.advisor.reset(self.game)
        self.stop_turn_button.config(state=tk.DISABLED)
        self.update_ui()

    def confirm_reset_game(self):
        """
        Ask the user before resetting the whole game and all statistics.
        """
        from tkinter import messagebox

        if messagebox.askyesno(
            "Reset Game?",
            "Start a new game and reset all statistics?"
        ):
            self.reset_game()
            self.info_label.config(text="New game started.")

    def current_player(self):
        """
        Return the current player's name.

        Returns:
            str: The name of the current player.
        """
        return self.game.current_player()

    def next_player(self):
        """
        Advance to the next player's turn, updating statistics and UI.
        """
        self.game.next_player()
        self.info_label.config(text=f"{self.current_player()}'s turn.")
        self.stop_turn_button.config(state=tk.DISABLED)
        self.update_ui()

    def end_turn(self):
        """
        End the current player's turn by computing the net change in face-up cards and moving to the next player.
        """
        self.game.end_turn()
        self.info_label.config(text=f"{self.current_player()}'s turn.")
        self.stop_turn_button.config(state=tk.DISABLED)
        self.update_ui()

    def update_stats_table(self):
        """
        Update the statistics table in the UI with real-time game data.
        """
        for widget in self.frame_stats.winfo_children():
            widget.destroy()

        headers = ["Player", "Drinks", "Correct Guesses", "Wrong guesses", "Correct to wrong ratio", "Changed Cards", "Turns"]
        screen_width = self.root.winfo_screenwidth()
        font_size = max(10, int(screen_width * 0.008))  # Scale font size

        for col, header in enumerate(headers):
            label = tk.Label(
                self.frame_stats,
                text=header,
                font=("Arial", font_size, "bold"),
                borderwidth=1,
                relief="solid",
                padx=5,
                pady=2
            )
            label.grid(row=1, column=col, sticky="nsew")
        total_changed = 0
        for i, player in enumerate(self.players):
            row = i + 2
            if player == self.current_player():
                delta = self.count_face_up_cards() - self.turn_start_face_up if hasattr(self, "turn_start_face_up") else 0
                changed = self.player_changed_cards[player] + delta
            else:
                changed = self.player_changed_cards[player]
            total_changed += changed

            self.correct_wrong_guess_ratio[player] = self.correct_guess_count[player] / self.wrong_guess_count[player] if self.wrong_guess_count[player] != 0 else self.correct_guess_count[player]

            values = [
                player,
                self.drink_count[player],
                self.correct_guess_count[player],
                self.wrong_guess_count[player],
                f"{self.correct_wrong_guess_ratio[player]:.2f}",
                self.player_changed_cards[player],
                self.player_turns[player]
            ]
            for col, val in enumerate(values):
                label = tk.Label(
                    self.frame_stats,
                    text=str(val),
                    font=("Arial", font_size),
                    borderwidth=1,
                    relief="solid",
                    padx=5,
                    pady=2
                )
                label.grid(row=row, column=col, sticky="nsew")
        sum_row = len(self.players) + 2
        total_drinks = sum(self.drink_count[p] for p in self.players)
        total_correct = sum(self.correct_guess_count[p] for p in self.players)
        total_wrong = sum(self.wrong_guess_count[p] for p in self.players)
        average_ratio = sum(self.correct_wrong_guess_ratio[p] for p in self.players) / len(self.players)
        totals = ["Total", total_drinks, total_correct, total_wrong, f"{average_ratio:.2f}", f"{total_changed} of 17", ""]
        for col, val in enumerate(totals):
            label = tk.Label(
                self.frame_stats,
                text=str(val),
                font=("Arial", font_size, "bold"),
                borderwidth=1,
                relief="solid",
                padx=5,
                pady=2
            )
            label.grid(row=sum_row, column=col, sticky="nsew")

    def update_ui(self):
        """
        Update the UI components (card grid and stats table) based on the current game state.
        Ensures images are properly resized and assigned to buttons, and highlights selectable cards.
        """
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if not WINDOW_LAYOUT[r][c]:
                    continue

                container = self.button_frames[r][c]
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

                    state = tk.DISABLED if self.ui_locked else tk.NORMAL
                    widget.config(state=state, command=lambda rr=r, cc=c: self.on_card_click(rr, cc))
                else:
                    widget.config(text=" ", image="", state=tk.DISABLED)

                # Restore the highlight frame around selectable cards
                if (r, c) in self.pending_removals:
                    container.config(highlightbackground="red", highlightcolor="red")
                elif self.face_up[r][c]:
                    container.config(
                        highlightbackground=self.card_border_inactive_color,
                        highlightcolor=self.card_border_inactive_color
                    )
                else:
                    # Ensure only adjacent selectable cards are highlighted
                    is_selectable = (r, c) in adjacent_positions(HANDLE_POSITION) if self.must_select_adjacent_to_handle else any(
                        self.face_up[nr][nc] for nr, nc in adjacent_positions((r, c))
                    )
                    if is_selectable:
                        container.config(highlightbackground="grey", highlightcolor="grey")  # Highlight selectable cards
                    else:
                        container.config(
                            highlightbackground=self.card_border_inactive_color,
                            highlightcolor=self.card_border_inactive_color
                        )  # Hide highlight while keeping geometry

        # Ensure the statistics table updates
        self.update_stats_table()
        if self.suggestion_position is not None:
            r, c = self.suggestion_position
            if (r, c) not in self.pending_removals and self.button_frames[r][c]:
                self.button_frames[r][c].config(
                    highlightbackground="blue", highlightcolor="blue"
                )
