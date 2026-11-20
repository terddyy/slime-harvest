# Asset reference — Cute Fantasy pack

Pack: "Cute Fantasy RPG" by Kenmi (premium). Copied to `assets/cute_fantasy/`.
License: use and modify freely, **do not redistribute** the PNGs (no public repo with
these files, no sharing the pack itself). Shipping them inside an exported game is fine.

All coordinates below are in **pixels** unless they say "cell", "row" or "col".
Rows/cols are 0-based. These layouts were checked by eye; if something looks wrong in
game, re-check the sheet (zoom it with nearest-neighbour scaling and draw a grid).

## Player (`Player/`)

The character is **layered**: every layer is a 576x3584 sheet with the same grid
(**9 cols x 56 rows, 64x64 frames**). Stack the layers as Sprite2Ds with the same frame.
Draw order used in game: base body, shoes, pants, shirt, hands, hair (then hat if any).

- Gayle uses the same layers (`Gayle.LAYERS`): `Hair_4_Ginger`, `Farmer_Shirt_1_Pink`, `Farmer_Pants_1_Purple`.
- `Player_Base/Player_Base_animations.png` — body
- `Feet/Shoes_1_<Color>.png`, `Legs/<Style>/...`, `Chest/<Style>/...`, `Hands/Hands_1_Bare.png`,
  `Head/Hair_N/...`, `Head/Plate_Helmet_N/...`, `Accessories/Farmer_Hat_1.png`

Feet of the character are at about (32, 40) inside each 64x64 frame.
Side-facing rows face **right**; flip horizontally for left.

| Rows (down, side, up) | Frames | Animation |
|---|---|---|
| 0, 1, 2 | 6 | idle |
| 3, 4, 5 | 6 | walk |
| 6, 9, 12 | 4 | sword attack 1 (slash) |
| 7, 10, 13 | 4 | sword attack 2 |
| 8, 11, 14 | 4 | sword attack 3 (thrust) |
| 15 (side) | 4 | death |
| 17, 18, 19 | 8 | roll / dodge |
| 29, 30, 31 | 6 | tool group 0 (axe) |
| 32, 33, 34 | 6 | tool group 1 (hoe) |
| 35, 36, 37 | 6 | tool group 2 (pickaxe) |
| 38, 39, 40 | 6 | tool group 3 (watering can) |

Other rows (16, 20–28, 41–55) are extra actions (jump, carry, idle variants) — not mapped yet.

### Tool overlays (`Player/Tools/Iron/`)
- `Iron_Sword.png` 256x576 = 4 cols x 9 rows of 64x64. **Sword row = player row − 6**
  (covers player rows 6–14).
- `Iron_Tools.png` 384x768 = 6 cols x 12 rows of 64x64. **Tool row = player row − 29**
  (covers player rows 29–40: axe, hoe, pickaxe, watering can).

## Tiles (`Tiles/`)

- `Grass/Grass_1_Middle.png` 16x16 plain grass.
- `Grass/Grass_Tiles_1.png` 256x160 (16x16 cells). Cells (5,9) (6,9) (7,9) = grass with tufts.
- `FarmLand/FarmLand_Tile.png` and `FarmLand_Wet_Tile.png`, 112x128 (7x8 cells), same layout.
  4-neighbour autotile used in `scripts/farm.gd` (mask N=1, E=2, S=4, W=8):
  - isolated (0,0)
  - vertical strip: top (0,1), middle (0,2), bottom (0,3)
  - horizontal strip: left (1,3), middle (2,3), right (3,3)
  - 3x3 block at cells (1..3, 0..2): corners, edges and centre (2,1)
  - cells (4..6, 0..4) and (0..3, 4..7) are inner-corner variants (8-neighbour), unused.

## Fruit trees (`Crops/`)
- `Fruit_Tree_Stages.png` 96x64 = 3 frames of 32x64: sapling, young tree, grown tree (no fruit). Feet ~ (16, 56).
- `Apple_Tree.png`, `Cherry_Tree.png`, `Peach_Tree.png`, `Pear_Tree.png` 32x64: grown tree with fruit.
- `Fruit_Trees_Fruit_Objects.png` 80x16 = 5 icons of 16x16: 0 grapes, 1 apple, 2 pear, 3 peach, 4 cherry (guessed, small).

## Crops (`Crops/Crops.png`)

112x704. Each crop is one **16x32 band**: crop *i* is at y = i*32.
Columns (16 px each): 0 sign, 1 seed bag, 2–5 growth stages (5 = ripe), 6 produce.
Plants are bottom-aligned in the band (tall plants use the top half).

Crop index: 0 wheat, 1 tomato, 2 carrot, 3 turnip/eggplant, 4 corn, 5 pumpkin, 6 parsnip,
7 cabbage, 8 cucumber, 9 chili, 10 red pepper, 11 orange pepper, 12 green pepper,
13 broccoli, 14 sunflower, 15 onion, 16 potato, 17 strawberry, 18 radish, 19 garlic,
20 leek, 21 grapes. (Names are best guesses from the art.)
In game (B2): radish 18, carrot 2, potato 16, tomato 1, cabbage 7, corn 4, eggplant 3, pumpkin 5,
strawberry 17, chili 9 (see `Crop.TYPES`).

## Enemies (`Enemies/`)

- `Slime/Slime_<Size>/Slime_<Size>_<Color>.png` (colors: Blue, Green, Pink, Red, Yellow).
  Every size is **8 cols x 4 rows**; only the frame size changes:
  - Small 128x64 = 16x16 frames. Body ~7 px wide, shadow bottom at y=15 → sprite offset (0, -7).
  - Medium 256x128 = 32x32 frames. Body ~11 px wide, shadow bottom at y=22 → offset (0, -6).
  - Big 512x256 = 64x64 frames. Body ~18 px wide, shadow bottom at y=42 → offset (0, -10).
  - Rows: 0 idle (4), 1 hop/move (8), 2 death (Small/Medium: 4-frame squish; **Big: 8 frames**,
    bursts into droplets), 3 hurt flash (4, white/normal alternating).
  - Used: Small Blue, Medium Green, Big Red (`scripts/slime.gd` STATS).
- `Skeleton/Skeleton_Bowman/Merged/Skeleton_Bowman.png` 192x416 = **6 cols x 13 rows of 32x32**.
  Bow is drawn in. Shadow bottom at y=25 → sprite offset (0, -9). Side rows face **right**.

  | Rows (down, side, up) | Frames | Animation |
  |---|---|---|
  | 0, 1, 2 | 6 | idle |
  | 3, 4, 5 | 6 | walk |
  | 6, 7, 8 | 6 | shoot: frame 0 = release (arrow leaving), 1–5 = recovering to rest. Played **backwards** in game so it reads as draw → release |
  | 9 | 4 | death (falls apart) |
  | 10, 11, 12 | 4 | hurt flash |

  `Separated/` has the same body sheet without the bow plus `Skeleton_Bowman_Bow.png` 192x288 — unused.
  Not used any more (skeletons were removed in Sprint 2).
- `Skeleton/Skeleton.png` 192x320, `Skeleton_Swordman.png` 256x512, `Skeleton_Mage.png` 256x416 —
  not mapped yet.

## NPCs (`NPCs (Premade)/`)

Cells are 64x64 (sheet width 384 = 6 columns). The figure is ~13x28 px, feet at y=41 inside the cell.
- Rows 0-6 of `Bartender_Bruno/Katy`, `Chef_Chloe` (384x448): row 0 = idle facing the camera (6 frames,
  a small bob). Rows 1-5 are other idle/walk directions and row 6 has 4 frames (sit/lie); not mapped yet.
- `Farmer_Bob/Buba` 384x832, `Lumberjack_Jack`, `Miner_Mike` 384x640, `Fisherman_Fin` 576x832: same
  top rows plus tool-action rows below. Not mapped.
- Used: `Chef_Chloe.png` row 0 for Azy (`Shopkeeper`).

## Other (`Other/`)

- `Skeleton_Mage_Projectile.png` 128x16 = 8 frames of 16x16, a purple fireball falling downward — unused.
- `Bow_Stages.png` 64x16 = 4 cells of 16x16 — not mapped.

## Objects

- `Trees/Big_Oak_Tree.png` 192x80 = 3 frames of 64x80: stump, tree with shadow, tree without shadow.
  Trunk base at (32, 62) in the frame.
- `Trees/Medium_Oak_Tree.png` 96x48 = 3 frames of 32x48. Trunk base at (16, 31).
- `Buildings/Buildings/Unique_Buildings/Stalls/Market_Stalls.png` 192x48 = 4 stalls of 48x48
  (red, green, blue, orange).

## Buildings (`scripts/building_data.gd`)

All in `Buildings/Buildings/` unless noted; the `_Red_Red` colour variants are used (Base/Green and Black/Blue exist too).
- `Houses/Wood/House_3_Wood_Base_Red.png` 144x128: farmhouse. Door (arched) centred at x=89, ground line y=112.
- `Unique_Buildings/Barn/Barn_Red_Red.png` 128x144: barn, double door centred x=64, ground y=131.
- `Unique_Buildings/Coop/Coop_Red_Red.png` 240x128 = 3 coops of 80x128 (barrels / crates / plain). The first (x 0..80) is used, ground y=126.
- `Unique_Buildings/Windmill/Windmill.png` 128x112: left 64x112 is the tower (ground y=108), right half is a static sail drawing (unused).
  `Windmill_Sail_Anim.png` 256x80 = 4 frames of 64x80, hub at the frame centre; put it at tower (32, 44) = 64 px above the foot.
- `Unique_Buildings/Greenhouse/GreenHouse_Wood.png` 384x128 = 4 views of 96x128: (0) glass with floor, (1) closed glass with door (used),
  (2) back wall, (3) outline only. Ground y=116.
- `Outdoor decoration/Well.png` 32x48: well, ground y=47.
- Also available, unused: Shed, Silo, Fisherman/Blacksmith houses, Inn, Church, Tents, other House_1..5 variants.
- `Outdoor decoration/Signs.png` 96x528, cells of 16 px: (0,1) 16x32 single board on a post (price signs, region 0,16,16,32);
  (3,1) post with two boards (restoration board, region 48,16,16,32).
- Rubble from `Outdoor_Decor.png`: stump (16,96), rocks (48,96) and (64,96), 16x16 each.

## Map tiles used by `GroundBuilder`

- `Tiles/Water/Water_Tile_1.png` 48x80 (3x5 cells): cells (0..2, 0..2) are a pond as a 3x3 rounded block
  (corners, edges, water centre at (1,1); the grass border is painted into the tile). Rows 3-4 are the inverse
  (a grass island in water), unused. `Water_Tile_1_Anim.png` is 8 frames of the same 48x80, unused (ponds are static).
- `Tiles/Grass/Grass_Tiles_1.png`: dirt path as a 3x3 block at cells (0..2, 5..7) (same layout, grass border baked in).
  The grass-with-edge block is at (0..2, 0..2); a brown-border variant at (3..5, 0..2).
- `Outdoor decoration/Outdoor_Decor.png` 144x416: boulder at (64,144) 16x16; bigger rocks around (64,176) 32x32;
  logs, stumps, bushes, flowers and lily pads fill the rest (not mapped).

## Outdoor decoration (`Outdoor decoration/`)

- `Fences.png` 64x64 = 4x4 cells of 16x16, a wooden fence **autotile** (used in
  `scripts/fences.gd`, 4-neighbour mask N=1, E=2, S=4, W=8). Same idea as the FarmLand
  sheet but the pieces sit in different cells:
  - single post (0,3)
  - vertical strip: top end (0,0), middle (0,1), bottom end (0,2)
  - horizontal strip: left end (1,0), middle (2,0), right end (3,0)
  - 3x3 block at cells (1..3, 1..3): corners, T pieces and the 4-way cross (2,2)
  The post stands at y 3..12 inside its cell (shadow to y 13); vertical rails run to the
  cell edges so neighbouring cells join up. Drawn exactly over its tile, y-sorted at
  (8, 14) like crops. Cell (2,0) doubles as the fence icon (hotbar, shop).
- `White_Fence.png` 80x80 (5x5 cells, white picket fence, looks like a similar autotile with
  extra vertical columns) and `Fence_Big.png` 64x64 (taller wooden posts and rails) —
  not mapped.

## Icons (`Icons/Outline/`, 16x16 cells)

- `Tool_Icons_Outline.png` (10 cells): 0 bow, 1 shovel, 2 pickaxe, 3 axe, 4 sword, 5 hoe,
  6 watering can, 7 fishing rod, 8 lantern/hammer, 9 torch.
- `Food_Icons_Outline.png` 8x12 cells. Produce is in even columns with its seed bag in the
  next column. Used in game: tomato (0,4) + seeds (1,4), carrot (2,4) + seeds (3,4),
  pumpkin (0,6) + seeds (1,6), corn (0,7) + seeds (1,7), radish (2,8) + (3,8), potato (0,10) + (1,10),
  cabbage (2,5) + (3,5), eggplant (4,7) + (5,7), chili (4,6) + (5,6), strawberry (0,11) + (1,11).
  Other crops in rows 3-11 (wheat (0,3), grapes (0,5)...); rows 0-2 are meat, mushrooms, fish.
- `Resources_Icons_Outline.png` 6x6 cells. Gold bar (2,2). Rows 0-3: ore, crystal and bar per colour; rows 4-5: wood, bone, etc.
- No heart or coin icon in the pack.

## Farmhouse interior (B2)

All from `Buildings/`; regions are in pixels.
- `Houses_Interiors/Interior_Walls.png` 224x96: wood plank wall filler tile (48,48,16,16) (stone 64,48; brick 80,48).
- `Houses_Interiors/Wood_Floor_Tiles.png` 128x128: 16x16 floor tiles; plank floor used = (16,32).
- `House_Decor/Beds.png` 112x192: rows of 32px, one colour per row (orange, teal, green, pink, yellow, red).
  Double bed facing down = (0, row*32, 32, 32); used: green (0,64,32,32).
- `House_Decor/BookShelves.png` 192x112: full bookshelf (16,0,32,32).
- `House_Decor/windows.png` 80x128: 16px-wide windows, 32px rows; (0,0,16,24) sky-tint window.
- `House_Decor/Doors.png` 176x384: 32px rows; (0,0,16,32) brown wooden door.

## Animals (`Animals/Chicken/Chicken_01.png`, `Animals/Cow/Cow_01.png`)

Both sheets are 8 columns of **32x32** frames (chicken 256x512, cow 256x480); rows hold different
animations, only the first columns are filled. Other files (Chicken_02..18, Rooster, Cow_02..09) are colour variants with the same layout.
- Chicken (head faces right; feet/shadow bottom at y=24, centre x=16): row 0 idle (2 frames), row 1 walk (6),
  row 2 turn/peck frames (8), row 6 sleeping with "z" (8).
- Cow (head faces left; feet bottom at y=27, centre x=16): row 0 idle side (2), rows 1-2 idle front/back,
  row 3 walk side (8), rows 4-5 walk front/back (8), row 10 sleeping (8).
- Product icons used in bubbles and the shop: egg (6,1) and milk bottle (7,0) in `Food_Icons_Outline.png`.

## Generated art (`assets/generated/`)

Made with the gpt-image skill; unlike the pack these files are ours and are tracked in git.
Each has its prompt next to it (`<name>.prompt.txt`). Raw renders are big, so
`tools/process_generated_art.py <raw_logo> <raw_icon>` makes the game-ready files (Lanczos downscale).

- `logo.png` (160x78, transparent): "Slime Harvest" logo. Rendered on flat magenta, which the script keys out.
  Used on the title screen (`scripts/title.gd`, `LOGO`), shown at 1:1 so it stays crisp under nearest filtering.
- `icon.png` (256x256): slime + carrot app icon. `config/icon` in `project.godot` and `application/icon`
  in `export_presets.cfg` point at it (replaces the old pack-derived `assets/icon.png`).
- No separate title-screen illustration: the pack farm backdrop already fills the screen.
- Loading screens reuse `logo.png`: desktop boot splash (`boot_splash/image` in `project.godot`, bg color = `UiStyle.OUTLINE_COLOR`),
  web shell `html/shell.html` (logo embedded as base64), and `scenes/loading.tscn` between title and farm.
