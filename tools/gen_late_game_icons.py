"""Draws assets/generated/late_game_icons.png: three 16x16 cells, left to right
  0 wool icon, 1 sprinkler icon (both with the pack's black outline + cream halo), 2 sprinkler as placed in the world.
Pixel art drawn from ASCII masks (Pillow only). Run: python tools/gen_late_game_icons.py"""
from PIL import Image

OUT = "assets/generated/late_game_icons.png"
BLACK = (0, 0, 0, 255)
CREAM = (249, 230, 207, 255)
COLORS = {
    "W": (255, 255, 255, 255), "L": (192, 203, 220, 255), "D": (139, 155, 180, 255),
    "M": (90, 105, 136, 255), "N": (71, 83, 107, 255),
    "B": (102, 176, 179, 255), "C": (234, 249, 250, 255), "E": (56, 97, 109, 255),
}

WOOL = [
    "...WWWW.....",
    "..WWWWWWW...",
    ".WWWWWWWWWW.",
    ".WWWWWWWWWWL",
    "WWWWWWWWWWLL",
    "WWWWWWWWWLLD",
    "WWWWWWWWLLDD",
    ".WWWWWWLLLD.",
    "..WWWLLLLD..",
    "...LLLLDD...",
]
SPRINKLER = [
    "..C..CC..C..",
    ".B..CBBC..B.",
    "...B.LL.B...",
    "....LMML....",
    ".....MM.....",
    ".....MM.....",
    ".....MN.....",
    "....MMMN....",
    "...LMMMMN...",
    "...MMMMNN...",
]


def draw(rows: list[str], halo: bool) -> Image.Image:
    cell = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    ox, oy = 2, 3
    fill = {}
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != ".":
                fill[(x + ox, y + oy)] = COLORS[ch]
    outline = {p for (px, py) in fill for p in _around(px, py) if p not in fill}
    ring = {p for (px, py) in outline for p in _around(px, py) if p not in fill and p not in outline}
    if halo:
        for p in ring:
            _put(cell, p, CREAM)
    for p in outline:
        _put(cell, p, BLACK)
    for p, color in fill.items():
        _put(cell, p, color)
    return cell


def _around(x: int, y: int):
    return [(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (dx or dy)]


def _put(cell: Image.Image, p: tuple[int, int], color) -> None:
    if 0 <= p[0] < 16 and 0 <= p[1] < 16:
        cell.putpixel(p, color)


sheet = Image.new("RGBA", (48, 16), (0, 0, 0, 0))
sheet.paste(draw(WOOL, True), (0, 0))
sheet.paste(draw(SPRINKLER, True), (16, 0))
sheet.paste(draw(SPRINKLER, False), (32, 0))
sheet.save(OUT)
print("wrote", OUT)
