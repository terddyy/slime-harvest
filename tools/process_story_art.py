"""Downscales the raw gpt-image story renders to the 320x180 panels in assets/generated/.

Usage: python tools/process_story_art.py <folder with raw_<name>.png files>
Names: intro_1..3, ending_1..3 (prompts are story_<name>.prompt.txt).
"""
import sys
from PIL import Image

NAMES = ["intro_1", "intro_2", "intro_3", "ending_1", "ending_2", "ending_3"]
SIZE = (320, 180)

for name in NAMES:
    img = Image.open(f"{sys.argv[1]}/raw_{name}.png").convert("RGB")
    img.resize(SIZE, Image.LANCZOS).save(f"assets/generated/story_{name}.png")
    print(name, SIZE)
