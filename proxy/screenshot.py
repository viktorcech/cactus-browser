"""
Paste screenshot from clipboard and save to file.
Usage: python screenshot.py
Saves clipboard image to D:\viktor\vbxe-browser\screenshot.png
"""
from tkinter import Tk
from PIL import ImageGrab
import sys

try:
    img = ImageGrab.grabclipboard()
    if img:
        path = r"D:\viktor\vbxe-browser\screenshot.png"
        img.save(path)
        print(f"Saved to {path}")
    else:
        print("No image in clipboard. Press PrintScreen first, then run this.")
except ImportError:
    print("Need Pillow: pip install Pillow")
except Exception as e:
    print(f"Error: {e}")
