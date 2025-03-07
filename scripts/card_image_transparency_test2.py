import tkinter as tk
from PIL import Image, ImageTk
import os

def on_click():
    print("Button clicked!")

def toggle():
    global widget
    # If widget is currently a Button, destroy it and create a Label instead.
    if isinstance(widget, tk.Button):
        widget.destroy()
        widget = tk.Label(frame, image=photo)
        widget.pack(pady=10)
        toggle_btn.config(text="Make Clickable")
    else:
        # If widget is a Label, replace it with a Button.
        widget.destroy()
        widget = tk.Button(frame, image=photo, command=on_click)
        widget.pack(pady=10)
        toggle_btn.config(text="Make Non-Clickable")

# Create main window
root = tk.Tk()
root.title("Toggle Clickable / Non-Clickable Image Test")

# Check for test image (test.png) in the same folder.
image_path = "test.png"
if not os.path.exists(image_path):
    print("Please place a file named 'test.png' in this folder.")
    exit(1)

# Load and resize the image with PIL.
img = Image.open(image_path).convert("RGB")
img = img.resize((200, 200), Image.LANCZOS)
photo = ImageTk.PhotoImage(img)

# Create a frame to hold the widget.
frame = tk.Frame(root, padx=20, pady=20)
frame.pack()

# Initially create the widget as a Button.
widget = tk.Button(frame, image=photo, command=on_click)
widget.pack(pady=10)

# Create a toggle button that swaps the widget.
toggle_btn = tk.Button(root, text="Make Non-Clickable", command=toggle)
toggle_btn.pack(pady=10)

root.mainloop()
