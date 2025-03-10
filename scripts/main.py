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
    game = WindowGame(root, players)
    root.mainloop()


if __name__ == "__main__":
    main()