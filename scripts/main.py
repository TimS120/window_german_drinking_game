"""
Entry point for the Window Drinking Game app.
"""

import json
import os
import sys


def _restart_with_project_venv():
    """Use the repository's pinned runtime regardless of the IDE interpreter."""
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    venv_python = os.path.join(repo_root, ".venv", "Scripts", "python.exe")
    current_python = os.path.normcase(os.path.realpath(sys.executable))
    expected_python = os.path.normcase(os.path.realpath(venv_python))

    if current_python == expected_python:
        return
    if not os.path.isfile(venv_python):
        raise RuntimeError(
            "The project virtual environment is missing. Expected Python at "
            f"{venv_python}."
        )

    os.execv(
        venv_python,
        [venv_python, os.path.abspath(__file__), *sys.argv[1:]],
    )


# This must happen before importing the UI, which imports PyTorch and RLlib.
if __name__ == "__main__":
    _restart_with_project_venv()


import tkinter as tk

if __package__:
    from .config import DEVELOPMENT_MODE
    from .game import WindowGame
    from .utils import get_player_names
else:
    from config import DEVELOPMENT_MODE
    from game import WindowGame
    from utils import get_player_names


def main():
    """
    Initialize the Tkinter root window and start the game.
    """
    root = tk.Tk()

    screen_width = root.winfo_screenwidth()
    screen_height = root.winfo_screenheight()
    window_width = int(screen_width * 0.8)
    window_height = int(screen_height * 0.8)
    x_position = (screen_width - window_width) // 2
    y_position = (screen_height - window_height) // 2
    root.geometry(f"{window_width}x{window_height}+{x_position}+{y_position}")

    if DEVELOPMENT_MODE:
        players = ["Alice", "Bob", "Charlie"]
    else:
        root.withdraw()
        players = get_player_names(root)
        if not players:
            players = ["Player1"]
        root.deiconify()
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    simulation_config_path = os.path.join(
        repo_root, "configs", "simulation_config.json"
    )
    with open(simulation_config_path, encoding="utf-8-sig") as config_file:
        simulation_config = json.load(config_file)

    game = WindowGame(
        root,
        players,
        advisor_config=simulation_config.get("advisor", {}),
    )
    root.mainloop()


if __name__ == "__main__":
    main()
