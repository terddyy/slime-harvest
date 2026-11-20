"""Turns the raw gpt-image renders into the game-ready files in assets/generated/.

Usage: python tools/process_generated_art.py <raw_logo.png> <raw_icon.png>
The logo render sits on flat magenta: that becomes transparent, the result is cropped
and downscaled (Lanczos) to its display size. The icon is downscaled to 256x256.
"""
import sys
from PIL import Image

LOGO_WIDTH = 160
ICON_SIZE = 256
OUT = "assets/generated/"


def key_out_magenta(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, _ = px[x, y]
            if r > 200 and b > 200 and g < 110:  # magenta, incl. anti-aliased fringe
                px[x, y] = (0, 0, 0, 0)
    return img


def make_logo(src: str) -> None:
    img = key_out_magenta(Image.open(src))
    img = img.crop(img.getchannel("A").getbbox())
    height = round(img.height * LOGO_WIDTH / img.width)
    img = img.resize((LOGO_WIDTH, height), Image.LANCZOS)
    img.save(OUT + "logo.png")
    print("logo", img.size)


def make_icon(src: str) -> None:
    img = Image.open(src).convert("RGBA").resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS)
    img.save(OUT + "icon.png")
    print("icon", img.size)


if __name__ == "__main__":
    make_logo(sys.argv[1])
    make_icon(sys.argv[2])
