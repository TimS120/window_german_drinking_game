"""
simulation_env.py

Simulation environment for the Window Drinking Game.

This module provides a Gym-like interface to the game mechanics.
It encapsulates game state, action validation, and reward computation
for reinforcement learning. The environment uses the existing UI for
debugging when observer mode is enabled.

It now includes:
- A fixed global action space (global keys) that the model always chooses from.
- A human input function (get_human_action) for interactive play via console.
- An extended human turn option that uses the existing UI dialogs. In this
  mode, when a human selects a move via the UI the action is captured and mapped
  to a global action number.
"""

import tkinter as tk
import random
from game import WindowGame
from config import WINDOW_LAYOUT, HANDLE_POSITION
from utils import adjacent_positions


def build_global_action_space():
    """
    Build a fixed global action space for the game.
    For each card slot in the layout, add actions for:
      - Higher, Same, Lower (no orientation needed)
      - In-between and Outside for both horizontal and vertical orientations

    Returns:
        list: A list of action dictionaries.
    """
    actions = []
    for r in range(len(WINDOW_LAYOUT)):
        for c in range(len(WINDOW_LAYOUT[r])):
            if WINDOW_LAYOUT[r][c]:
                # Higher, Same, Lower actions
                for guess in ["higher", "same", "lower"]:
                    actions.append({"position": (r, c), "guess": guess, "orientation": None})
                # In-between and Outside actions for horizontal and vertical orientations
                for guess in ["in-between", "outside"]:
                    for orientation in ["horizontal", "vertical"]:
                        actions.append({"position": (r, c), "guess": guess, "orientation": orientation})
    return actions


class SimulatedWindowGame(WindowGame):
    """
    A subclass of WindowGame that overrides interactive UI prompts
    to enable simulation.
    In human mode, the existing UI dialogs are used to capture the move.
    """

    def __init__(self, root, players, observer=False):
        """
        Initialize the simulated game.

        Args:
            root (tk.Tk): Tkinter root.
            players (list): List of player names.
            observer (bool): If True, the UI is updated for observation.
        """
        self.observer = observer
        # Initialize the game (this builds the UI as well).
        super().__init__(root, players)
        # Mark simulation mode to bypass non–UI dialogs (for simulation, not human UI).
        self.simulation_mode = True

        # For human UI mode, create variables to capture the human move.
        if observer:
            self.human_action = None
            self.human_action_var = tk.StringVar(value="")

    def set_human_action(self, action):
        """
        Store the human-selected action and wake any waiting turn.
        Args:
            action (dict): The action dictionary.
        """
        self.human_action = action
        self.human_action_var.set("done")

    def human_turn(self):
        """
        Wait for a human move via the UI.
        Returns:
            dict: The action dictionary selected by the human.
        """
        # Reset the stored action.
        self.human_action = None
        self.human_action_var.set("")
        # The human will click a card and select an option.
        self.root.wait_variable(self.human_action_var)
        return self.human_action

    def get_valid_options_for_card(self, r, c):
        """
        Compute valid guess options for the card at position (r, c).

        Returns:
            list: Each option is a dict with keys:
                  - "type": Either "higher-lower" or "in-between"
                  - "guess_options": List of valid guesses
                                     (["higher", "same", "lower"] or ["in-between", "outside"])
                  - "neighbors": For "higher-lower", a single neighbor tuple.
                                 For "in-between", a tuple with two neighbor positions.
                  - "orientation": "horizontal" or "vertical" (if applicable).
        """
        options = []
        # Collect adjacent face-up neighbors.
        neighbors = []
        for nr, nc in adjacent_positions((r, c)):
            if self.face_up[nr][nc]:
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
        # Separate by orientation.
        horizontal = [n for n, d in neighbors if d in ("east", "west")]
        vertical = [n for n, d in neighbors if d in ("north", "south")]

        if len(horizontal) >= 2:
            left = min(horizontal)
            right = max(horizontal)
            options.append({
                "type": "in-between",
                "guess_options": ["in-between", "outside"],
                "neighbors": (left, right),
                "orientation": "horizontal"
            })
        elif len(horizontal) == 1:
            options.append({
                "type": "higher-lower",
                "guess_options": ["higher", "same", "lower"],
                "neighbors": horizontal[0],
                "orientation": "horizontal"
            })

        if len(vertical) >= 2:
            top = min(vertical)
            bottom = max(vertical)
            options.append({
                "type": "in-between",
                "guess_options": ["in-between", "outside"],
                "neighbors": (top, bottom),
                "orientation": "vertical"
            })
        elif len(vertical) == 1:
            options.append({
                "type": "higher-lower",
                "guess_options": ["higher", "same", "lower"],
                "neighbors": vertical[0],
                "orientation": "vertical"
            })

        # If any in-between options exist, they take precedence.
        in_between_opts = [opt for opt in options if opt["type"] == "in-between"]
        if in_between_opts:
            options = in_between_opts

        return options

    def ask_higher_same_lower(self, r, c, neighbor):
        """
        Display a UI prompt for a Higher/Same/Lower guess.
        Instead of directly resolving, it captures the move as an action.
        Args:
            r (int): Row index of the card.
            c (int): Column index of the card.
            neighbor (tuple): The neighbor card position.
        """
        guess_win = tk.Toplevel(self.root)
        guess_win.title("Guess Higher, Same, or Lower")
        guess_win.protocol("WM_DELETE_WINDOW", guess_win.destroy)
        tk.Label(guess_win, text="Is the selected card Higher, Same, or Lower than the neighbor?").pack(padx=10, pady=10)

        def make_choice(guess):
            action = {"position": (r, c), "guess": guess, "orientation": None}
            self.set_human_action(action)
            guess_win.destroy()

        tk.Button(guess_win, text="Higher", command=lambda: make_choice("higher")).pack(side=tk.LEFT, padx=5, pady=5)
        tk.Button(guess_win, text="Same", command=lambda: make_choice("same")).pack(side=tk.LEFT, padx=5, pady=5)
        tk.Button(guess_win, text="Lower", command=lambda: make_choice("lower")).pack(side=tk.RIGHT, padx=5, pady=5)

    def ask_in_between(self, r, c, n1, n2):
        """
        Display a UI prompt for an In-Between or Outside guess.
        Captures the move as an action.
        Args:
            r (int): Row index of the card.
            c (int): Column index of the card.
            n1 (tuple): First neighbor position.
            n2 (tuple): Second neighbor position.
        """
        guess_win = tk.Toplevel(self.root)
        guess_win.title("Guess In-Between or Outside")
        guess_win.protocol("WM_DELETE_WINDOW", guess_win.destroy)
        tk.Label(guess_win, text="Is the card In-Between or Outside these two?").pack(padx=10, pady=10)

        def make_choice(guess):
            # Determine orientation based on neighbor positions.
            orientation = "horizontal" if n1[0] == n2[0] else "vertical"
            action = {"position": (r, c), "guess": guess, "orientation": orientation}
            self.set_human_action(action)
            guess_win.destroy()

        tk.Button(guess_win, text="In-Between", command=lambda: make_choice("in-between")).pack(side=tk.LEFT, padx=10, pady=10)
        tk.Button(guess_win, text="Outside", command=lambda: make_choice("outside")).pack(side=tk.RIGHT, padx=10, pady=10)

    # In human mode, we use the UI dialogs above. Otherwise, in simulation mode, we use the non–interactive versions.
    # (The interactive methods above override the base class's behavior.)

    def simulate_action(self, position, guess, orientation=None):
        """
        Simulate an action on the game using the provided parameters.
        This method is used when the move is provided programmatically.
        Args:
            position (tuple): (r, c) position of the selected card.
            guess (str): Guess type.
            orientation (str, optional): "horizontal" or "vertical" if needed.

        Returns:
            dict: Contains keys "reward", "done", and "debug" info.
        """
        r, c = position
        if not WINDOW_LAYOUT[r][c]:
            return {"reward": -0.5, "done": False, "debug": "Invalid position: not a card slot."}
        if self.face_up[r][c]:
            return {"reward": -0.5, "done": False, "debug": "Card already face-up."}
        if self.must_select_adjacent_to_handle and (r, c) not in adjacent_positions(HANDLE_POSITION):
            return {"reward": -0.5, "done": False, "debug": "Must select card adjacent to handle."}

        options = self.get_valid_options_for_card(r, c)
        if not options:
            return {"reward": -0.5, "done": False, "debug": "No valid guess options for this card."}
        # Select option based on orientation if provided.
        selected_option = None
        if orientation:
            for opt in options:
                if opt.get("orientation") == orientation:
                    selected_option = opt
                    break
        else:
            selected_option = options[0]

        if guess not in selected_option["guess_options"]:
            return {"reward": -0.5, "done": False, "debug": "Invalid guess for selected option."}

        # Save current face-up count for reward calculation.
        initial_face_up = self.count_face_up_cards()
        if selected_option["type"] == "higher-lower":
            neighbor = selected_option["neighbors"]
            self.resolve_higher_same_lower(r, c, neighbor, guess)
        elif selected_option["type"] == "in-between":
            neighbor1, neighbor2 = selected_option["neighbors"]
            guess_in = True if guess == "in-between" else False
            self.resolve_in_between(r, c, neighbor1, neighbor2, guess_in)
        else:
            return {"reward": -5, "done": False, "debug": "Unknown option type."}

        # Check if the guess was wrong before auto-confirming removals.
        was_wrong = bool(self.pending_removals)
        penalty = self.pending_penalty if was_wrong and hasattr(self, "pending_penalty") else 0

        # If the handle was removed, increase penalty by 1.5 times.
        if was_wrong and HANDLE_POSITION in self.pending_removals:
            penalty = penalty * 1.5

        if self.pending_removals:
            self.auto_confirm_removals()

        if was_wrong:
            reward = -penalty
            debug_info = "Wrong guess."
        else:
            reward = 1
            debug_info = "Correct guess."

        done = self.check_game_end()

        # If the game is finished, assign a finishing reward 20 times a normal correct guess.
        if done and not was_wrong:
            reward = 20

        if self.observer:
            self.update_ui()
            self.root.update_idletasks()
            self.root.update()

        return {"reward": reward, "done": done, "debug": debug_info}

    def auto_confirm_removals(self):
        """
        Automatically confirm removals without UI interaction.
        """
        self.confirm_removals()

    def same_guess_confirmation(self, r, c):
        """
        Automatically confirm 'same' guess by updating drink counts.
        """
        current_player = self.current_player()
        for player in self.players:
            if player != current_player:
                self.drink_count[player] += 1
        self.finish_guess(r, c, True)


class WindowGameEnv:
    """
    Simulation environment for the Window Drinking Game with a Gym-like interface.
    """

    def __init__(self, players=["Alice", "Bob", "Charlie"], observer=True):
        """
        Initialize the simulation environment.

        Args:
            players (list): List of player names.
            observer (bool): If True, the UI is used for debugging/human play.
        """
        self.root = tk.Tk()
        # The window is initially hidden; if observer is True, we show it.
        self.root.withdraw()
        if observer:
            self.root.deiconify()
        self.game = SimulatedWindowGame(self.root, players, observer=observer)
        # Build the fixed global action space.
        self.global_action_space = build_global_action_space()

    def reset(self):
        """
        Reset the game environment.

        Returns:
            dict: Initial state representation.
        """
        self.game.reset_game()
        return self._get_state()

    def step(self, action):
        """
        Apply an action (dict) and update the game state.

        Args:
            action (dict): Must contain:
                           - "position": (r, c) tuple.
                           - "guess": One of "higher", "same", "lower", "in-between", "outside".
                           - "orientation": Optional ("horizontal" or "vertical").

        Returns:
            tuple: (state, reward, done, debug_info)
        """
        result = self.game.simulate_action(action["position"], action["guess"], action.get("orientation"))
        state = self._get_state()
        reward = result["reward"]
        done = result["done"]
        debug_info = result["debug"]
        return state, reward, done, debug_info

    def step_global(self, action_index):
        """
        Apply an action using a global action key (by index) from the fixed action space.

        Args:
            action_index (int): Index in the global action space.

        Returns:
            tuple: (state, reward, done, debug_info)
        """
        global_action = self.global_action_space[action_index]
        return self.step(global_action)

    def human_turn(self):
        """
        Wait for a human move via the UI.
        Returns:
            tuple: (global_action_index, action_dict) where global_action_index is the index in the global action space.
        """
        action = self.game.human_turn()
        # Map the chosen action to its global action number.
        for i, act in enumerate(self.global_action_space):
            if (act["position"] == action["position"] and
                act["guess"] == action["guess"] and
                act.get("orientation") == action.get("orientation")):
                return i, action
        return None, action

    def _get_state(self):
        """
        Obtain the current state representation.

        Returns:
            dict: Contains the card grid, face-up status, current player, and deck size.
        """
        state = {
            "card_grid": self.game.card_grid,
            "face_up": self.game.face_up,
            "current_player": self.game.current_player(),
            "deck_size": len(self.game.deck)
        }
        return state

    def get_valid_actions(self):
        """
        Compute and return all valid actions for the current state.
        This method is maintained for debugging but the agent will use global keys.
       
        Returns:
            list: A list of valid action dictionaries.
        """
        valid_actions = []
        for r in range(len(WINDOW_LAYOUT)):
            for c in range(len(WINDOW_LAYOUT[r])):
                if not WINDOW_LAYOUT[r][c]:
                    continue
                if self.game.face_up[r][c]:
                    continue
                if self.game.must_select_adjacent_to_handle and (r, c) not in adjacent_positions(HANDLE_POSITION):
                    continue
                options = self.game.get_valid_options_for_card(r, c)
                for opt in options:
                    for guess in opt["guess_options"]:
                        action = {
                            "position": (r, c),
                            "guess": guess,
                            "orientation": opt.get("orientation")
                        }
                        valid_actions.append(action)
        return valid_actions


def get_human_action(env):
    """
    Display valid actions from the global action space in the console and return the human-selected action.
    This is the older textual input option.
    Args:
        env (WindowGameEnv): The simulation environment.

    Returns:
        dict: The chosen action dictionary, or None if no valid action is selected.
    """
    actions = env.global_action_space
    print("Global Action Space:")
    for i, action in enumerate(actions):
        pos = action["position"]
        guess = action["guess"]
        orient = action.get("orientation", "N/A")
        print(f"{i}: Position: {pos}, Guess: {guess}, Orientation: {orient}")
    try:
        choice = int(input("Enter the global action index: "))
        if 0 <= choice < len(actions):
            return actions[choice]
        else:
            print("Invalid selection.")
            return None
    except ValueError:
        print("Please enter a valid number.")
        return None


if __name__ == "__main__":
    mode = input("Select mode: [H]uman UI, [C]onsole Human, or [G]lobal AI action? ").strip().upper()
    env = WindowGameEnv(observer=True)
    initial_state = env.reset()
    print("Initial state:", initial_state)

    done = False
    while not done:
        if mode == "H":
            # Use the UI-based human turn.
            global_index, action = env.human_turn()
            if global_index is None:
                print("Could not map action to a global key.")
                continue
            print(f"Human selected global action index: {global_index}")
        elif mode == "C":
            # Use console-based human input.
            action = get_human_action(env)
            if action is None:
                print("No valid action selected, exiting loop.")
                break
        else:
            print("Available global actions (indices): 0 to", len(env.global_action_space) - 1)
            try:
                action_index = int(input("Enter global action index: "))
                action = env.global_action_space[action_index]
            except ValueError:
                print("Please enter a valid number.")
                continue
        state, reward, done, debug = env.step(action)
        print("Action taken:", action)
        print("New state:", state)
        print("Reward:", reward, "Done:", done, "Debug:", debug)

    env.root.mainloop()
