#
# Script with the base functionality of toggling between clickable button with image and non-clickable
#

import tkinter as tk
from PIL import Image, ImageTk
import os

def on_button_click():
    print("Image button clicked!")

def toggle_button_state():
    if img_button['state'] == tk.NORMAL:
        img_button.config(state=tk.DISABLED)
        state_label.config(text="Button state: DISABLED")
    else:
        img_button.config(state=tk.NORMAL)
        state_label.config(text="Button state: NORMAL")

# Create the main Tkinter window first
root = tk.Tk()
root.title("Tkinter Image Button Test")

# Path to the image file (ensure test.png is in the same folder)
image_path = "test.png"
if not os.path.exists(image_path):
    print("Error: test.png not found. Please place an image file named 'test.png' in the same folder.")
    exit(1)

# Load and resize image using PIL (after creating the root window)
img = Image.open(image_path).convert("RGB")
img = img.resize((200, 200), Image.LANCZOS)
photo = ImageTk.PhotoImage(img)

# Create a frame to organize widgets
frame = tk.Frame(root, padx=20, pady=20)
frame.pack()

# Create an image button (initially enabled)
img_button = tk.Button(frame, image=photo, command=on_button_click, state=tk.NORMAL)
img_button.pack(pady=10)

# Create a button to toggle the state of the image button
toggle_btn = tk.Button(frame, text="Toggle Button State", command=toggle_button_state)
toggle_btn.pack(pady=5)

# Create a label to show the current state
state_label = tk.Label(frame, text="Button state: NORMAL")
state_label.pack(pady=5)

# Also show the same image in a Label for comparison (labels don't dim images)
image_label = tk.Label(frame, image=photo)
image_label.pack(pady=10)

root.mainloop()
