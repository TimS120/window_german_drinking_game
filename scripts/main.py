"""
Entry point for the Window Drinking Game application.
"""

import tkinter as tk
from config import DEVELOPMENT_MODE
from game import WindowGame
from utils import get_player_names


def main():
    """
    Initialize the Tkinter root window and start the game.
    """
    root = tk.Tk()
    if DEVELOPMENT_MODE:
        players = ["Alice", "Bob", "Charlie"]
    else:
        root.withdraw()
        players = get_player_names(root)
        if not players:
            players = ["Player1"]
        root.deiconify()
    game = WindowGame(root, players)
    root.mainloop()


if __name__ == "__main__":
    main()
