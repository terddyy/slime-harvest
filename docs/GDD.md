# Slime Harvest — Game Design Document

Working title. Top-down 2D pixel-art game made in Godot 4.7 for a final project.

## Pitch

Farm by day, defend by night. You have a small field on a run-down farm.
During the day you till, plant, water and harvest crops, then sell them at the
market stall and buy seeds and upgrades. When night falls, slimes crawl out of the woods to eat your crops.
They never hurt you: only your crops (and fences) are at risk. Days never end; the goal is to earn gold and restore every building (see below).

## Core loop

```
DAY   : till -> plant -> water -> (crop grows) -> harvest -> sell -> buy seeds/upgrades/fences
        -> build fences around the field
NIGHT : slimes spawn at the map edges -> they go for crops
        -> fight them with the sword -> they vanish at dawn
REPEAT, forever (night waves keep growing)
```

## End of the run

- Days are endless. There is no losing: no health, no death, no game-over.
- Goal: restore every project in `Restoration.PROJECTS` (`scripts/restoration.gd`: id, name,
  cost, what it unlocks) by paying its gold cost with `Game.restore(id)`. The HUD shows "Farm n/N".
  Each repair shows a banner (`Game.project_restored`). The last one emits `Game.farm_restored`:
  the game pauses and plays three ending panels (`StoryPanels.ENDING`), then the scrolling credits
  (`CreditsRoll`), then "The farm is saved!" with Credits / Keep playing / Quit to Title, and play
  continues afterwards. Click / E / Space moves on, Esc skips a step.
- Story intro: a new game starts with three illustrated panels (`StoryPanels.INTRO`: why Imogen and Gayle came to the
  run-down family farm), then the first-day banner and tutorial. Esc skips. `Game.intro_seen` is saved, so Continue never
  repeats it (older saves count as seen); Restart from the pause menu is a new game and shows it again. Costs (150/300/450/800/1000/1400 = 4100 gold) were balanced in P1 with the
  bot playthrough: it saves the farm in roughly 13-21 days (average ~17), the goal for a normal player is 15-20.
- Buildings: each project is a building on its plot (`scripts/building_data.gd`, `building.gd`, `buildings.gd`).
  Not restored = sign with name and price, rubble and a faint blue ghost of the building. Restored = the full
  building with walls (the windmill's sails spin). The farmhouse door is at the bottom middle of its plot.
- The restoration board is a signpost west of the farmhouse (`WorldLayout.BOARD_CELL`). E next to it opens the
  panel (`scripts/restoration_board.gd`): every project with price and what it unlocks; pick one to pay for it.
  Each row shows the cost and "Need Ng more" when you can't afford it. Standing near a ruined plot shows a hint
  ("restore for Ng at the board by the farmhouse"), and the first time you can pay for the cheapest unrestored
  project a one-time banner says so (not repeated, not shown for what you could already afford on load).
  The game is paused while it is open.

## Controls

| Key | Action |
|---|---|
| WASD / arrows | Move |
| Settings (title and pause menu) | Volumes (master/music/effects), fullscreen (not in the browser) and key rebinding, saved in `user://settings.cfg`. Click a key, press the new one; Esc cancels; a key that is already used is swapped with the other action. Esc and Enter can't be bound. Controls in this table are the defaults |
| + / - keys, Ctrl + mouse wheel, or touchpad pinch | Zoom in / out (`CameraZoom.ZOOM_STEPS`, 0.65x to 2x; kept across restarts) |
| Mouse wheel, or click a hotbar slot | Next / previous tool, or pick that tool (clicking Seeds again switches seed type) |
| 1 / 2 / 3 / 4 / 5 / 6 | Select Hoe / Watering can / Seeds / Sword / Fence / Sprinkler |
| Q, or 3 again | Seeds selected: switch to the next seed type or fruit sapling you have |
| Mouse | Aim: the highlighted tile follows the mouse, up to `Player.TOOL_REACH` (2) tiles away; further away it picks the nearest reachable tile in that direction |
| Left click | Use the selected tool on the highlighted tile (the player turns toward it). Clicking a ripe crop with any tool but the sword harvests it. Hold and drag to water/till/plant tile after tile |
| Space or J | Use the selected tool on the tile in front of the player, wherever the mouse is. Hold to keep going: hold and run along a row to water/till/plant it. You can always keep moving while using any tool |
| 5, then Space | Build a fence on grass, or pick a fence back up |
| E or right click | Harvest a ripe crop on the highlighted tile, talk to Azy (opens the shop) at the market stall, open the restoration board at the signpost by the farmhouse, go through the farmhouse door, sleep at the bed, collect eggs/milk from animals, talk to Gayle when next to her, or in the orchard: pick fruit / plant a sapling |
| Gayle dialog: mouse or Enter | Follow me / Stay here, Bye (Esc or E also closes it) |
| Shop: arrows + Enter, or mouse | Pick and buy an item |
| Shop / board: Esc or E | Close it |
| Board: arrows + Enter, or mouse | Restore the selected building |
| Esc | Pause menu (Resume, Restart, How to Play, Settings, Quit to Title); the music pauses too and resumes from the same spot |
| F1 | Hide the first-day tips |
| Tab, or click the Bag button right of the hotbar | Open / close the inventory (pauses; slides up above the hotbar) |
| Inventory: Left / Right or click a tab | Switch between Backpack, Storage and Goals; click seeds or fences in the Backpack to equip them; Esc closes |
| G, or click the "Next:" line under the Farm counter | Open the inventory on its Goals tab (G again or Esc closes) |
| N | Debug: skip to the next day/night phase |

## Rules (current numbers live in code, see `scripts/game.gd`, `crop.gd`, `farm.gd`, `slime.gd`, `fences.gd`)

### Time
- Day lasts `Game.DAY_LENGTH` (90 s), night lasts `Game.NIGHT_LENGTH` (45 s).
- Screen tint: white by day, orange at dusk, dark blue at night.

### Farming
- Hoe turns grass into tilled soil (not on trees, rocks, the stall, ponds, dirt paths, building plots, pens, the orchard or the map border).
- The map is 80x50 tiles, described in `scripts/world_layout.gd` (home, south and east fields; plots for the barn,
  farmhouse, well, greenhouse, windmill, coop; cow and chicken pens; orchard; a pond; dirt roads). Ponds block walking.
- Hoe on tilled soil without a crop turns it back into grass (soil with a crop is never changed).
  Hold and drag: the first tile of the hold decides, grass = till every tile passed, empty soil =
  untill every tile passed. Un-tilling does not count for the tutorial's tilling tip.
- Watering can makes tilled soil wet (darker tile).
- Seeds plant the selected crop type on empty tilled soil. You start with 6 carrot
  seeds and nothing else (`Game.START_SEEDS`).
- Every `Farm.GROW_INTERVAL` (8 s) is a farm tick. A crop counts the ticks its soil is
  wet; after its `grow_ticks` it gets a chance to grow (`Crop.try_grow`). Growing uses up
  the tile's water, so you water once per stage.
- Every crop has 4 visible stages; the last stage is ripe and can be harvested with E.
- Orchard (south-east area): buy a sapling (apple 60g, cherry 80g, peach 100g, pear 120g) at the stall, equip it (3 / Q, or click it in the
  Tab backpack; the Seeds slot then shows the sapling) and click or press Space on a free orchard tile, or face one and
  press E (trees keep one cell apart). Outside the orchard the hint says "Saplings grow in the orchard - follow the
  arrow" and the guide arrow points there (by day). A sign marks the orchard's west edge. It is a sapling at day 0, young after 1 day, grown
  after 3 days, then gives 3 fruit every 3 days (fruit sells for 20/28/36/44g each). Trees grow at every dawn; slimes
  ignore them. Numbers are constants in `scripts/orchard.gd`.
- Harvested crops go into your bag (counted per type). Sell them at the stall.
- Crop types (`Crop.TYPES`). Grow time = 3 stages x `grow_ticks` x 8 s of wet soil:

| Crop | Seed | Sells for | grow_ticks | Grow time | Profit |
|---|---|---|---|---|---|
| Radish | 3g | 8g | 1 | 24 s | 5g |
| Carrot | 5g | 15g | 1 | 24 s | 10g |
| Potato | 10g | 28g | 2 | 48 s | 18g |
| Tomato | 15g | 40g | 2 | 48 s | 25g |
| Cabbage | 20g | 56g | 3 | 72 s | 36g |
| Corn | 25g | 70g | 3 | 72 s | 45g |
| Eggplant | 32g | 90g | 4 | 96 s (more than a day) | 58g |
| Pumpkin | 40g | 120g | 4 | 96 s (more than a day) | 80g |
| Strawberry* | 55g | 170g | 5 | 120 s (more than a day) | 115g |
| Chili* | 75g | 240g | 6 | 144 s (more than a day) | 165g |

\* Greenhouse crops: their seeds can only be bought once the greenhouse is restored (`requires` in `Crop.TYPES`; locked rows are dimmed in the shop).

  Slow crops pay more per watering but cost more up front and are more likely to be
  standing in the field when the slimes come.

### Shop (E at the market stall)
- Azy, the shopkeeper, stands next to the stall with a name tag. E near Azy or the counter opens the shop.
- Opens a panel and pauses the game. Sell all crops, buy seeds, buy upgrades, buy fences.
- Upgrades (`Game.UPGRADE_PRICES`, levels reset on restart):

| Upgrade | Levels | Prices |
|---|---|---|
| Sword | damage 1 -> 2 -> 3 | 50g, 120g |
| Watering can | 1 tile -> row of 3 across your facing -> 3x3 in front | 60g, 150g |
| Fences | a bundle of 5 fence pieces, any time | 10g (`Game.FENCE_BUNDLE_PRICE`) |

  Both upgrades together cost 380g.

### Animals (`scripts/animal_types.gd`, `animal.gd`, `herd.gd`)
- Bought in the shop, needs the building restored first and room in the pen (`AnimalTypes.TYPES`):

| Animal | Needs | Pen | Price | Max | Gives | Sells for |
|---|---|---|---|---|---|---|
| Chicken | chicken coop | `pen_chickens` | 40g | 4 | egg | 6g |
| Cow | barn | `pen_cows` | 120g | 3 | milk | 18g |
| Sheep (late game) | greenhouse | `pen_cows` (shared with the cows) | 200g | 3 | wool | 30g |

- They wander inside their pen. Each gives one product per day: ready on the day after it was bought or
  last collected (`Game.day` past `collected_day`), shown as a bubble over the animal.
- Collect with E next to the animal or a left click on it (Imogen within ~3 tiles). Products go in the bag
  and are sold with the crops ("Sell goods"). Slimes ignore animals. Saved (`Game.animals`, `Game.products_in_bag`, `herd`).

### Fences
- You start with 3 fence pieces (`Game.START_FENCES`); more come in bundles of 5 for 10g.
- Fence tool (5): Space on the highlighted tile builds a fence there if it is grass inside
  the farm area (not tilled, not a tree or the stall, no fence yet). Space on a fence picks
  it back up and gives the piece back (a damaged fence comes back as new). The cursor is
  green when you can build or pick up.
- Fences connect to their neighbours (posts and rails). Nothing can be tilled or planted
  on a fence tile.
- The player walks through fences, so you can't trap yourself.
- Ground enemies can't. A slime whose next step would enter a fence tile stops and bites
  the fence every `Slime.FENCE_BITE_INTERVAL` (1 s). A fence has `Fences.MAX_HP` (8) HP;
  a bite does the slime's `fence_damage` (small 1, medium 2, big 4), so one fence holds a
  small slime 8 s, a medium 4 s and a big one 2 s. A broken fence disappears in a puff of
  wood chips. Slimes still go straight for their target (no pathfinding), so a ring of
  fences is a wall they must chew through while you come over with the sword.
- Fences stay up between nights.

### Sprinklers (late game: `scripts/sprinklers.gd`)
- Azy sells sprinklers for `Sprinklers.PRICE` (90g) once the greenhouse is restored, i.e. after the farm is saved.
  They go in the bag (hotbar slot 6, inventory Backpack).
- Sprinkler tool (6): Space on grass inside the farm area (same rule as a fence) places one; Space on a sprinkler
  picks it up. The cursor previews the 3x3 area it waters. Nothing can be tilled on a sprinkler tile.
- Every sunrise (also after sleeping through the night) each sprinkler waters the 3x3 tiles around it
  (`Sprinklers.water_all()`), so the soil is wet again each morning. Slimes ignore sprinklers.
- Saved: placed ones in `sprinklers`, the bag in `Game.sprinkler_pieces`.

### Night defense
- Enemies spawn at the map edge, away from the player (`scripts/spawner.gd`).
- Nights 1-7 have a fixed wave (`Waves.NIGHTS` in `scripts/waves.gd`); later nights are scaled by `Waves.wave()` (see Waves below): how many of each enemy
  and the seconds between spawns. The order inside a night is shuffled. First spawn comes
  `Waves.FIRST_DELAY` (2 s) after nightfall; every wave finishes spawning before dawn.
- Slimes only go for the nearest crop (and chew through fences in the way). They ignore the
  player and never hurt them. With no crops left a slime just stands still until dawn.
- A slime eats a crop in `Crop.BITES_TO_EAT` bites.
- The sword always swings the way the player faces (the last direction walked), whether
  you click or press Space; holding the button keeps swinging. You keep running at full
  speed while swinging (facing stays locked until the swing ends). It hits every enemy in a wide
  arc in front (up to `Player.SWORD_RANGE` 32 px, about 80 degrees to each side, so the
  front diagonals count) plus anything pressed against the player (`SWORD_HUG` 12 px).
  Killing one drops gold.
  The sword does 1 damage, more with upgrades.
- At dawn all remaining enemies vanish (no gold).

#### Enemy roster (numbers in `Slime.STATS`)

| Enemy | HP | Speed | Gold | Notes |
|---|---|---|---|---|
| Small slime (blue) | 1 | 38 | 1 | fast, dies in one hit |
| Slime (green) | 3 | 26 | 3 | the v1 slime |
| Big slime (red) | 6 | 17 | 4 | splits into 2 small slimes when it dies |

Skeletons (archers) were removed in Sprint 2.

#### Waves

| Night | Small | Slime | Big | Seconds between spawns |
|---|---|---|---|---|
| 1 | 4 | 4 | – | 4.5 |
| 2 | 5 | 5 | – | 3.6 |
| 3 | 4 | 6 | 1 | 3.2 |
| 4 | 6 | 6 | 2 | 2.6 |
| 5 | 6 | 7 | 2 | 2.4 |
| 6 | 6 | 8 | 3 | 2.1 |
| 7 | 8 | 9 | 4 | 1.7 |

After night 7 every night adds 1 small and 1 medium slime every 2 nights and 1 big slime every
2 nights (growth stops `Waves.MAX_EXTRA_NIGHTS` = 20 nights past 7). The spawn interval shrinks
(`Waves.SPAWN_WINDOW` / enemies) so every wave still spawns before dawn.

### Farmhouse and sleeping (`farmhouse.gd`, `sleep_rules.gd`)
- E at the farmhouse door (bottom middle of `farmhouse_plot`) fades into a room drawn far off the map;
  E at the room's door goes back out. The house is always lit. A save made indoors loads you outside the door.
- Bed (E): fade out, skip to the next morning (day +1, auto-save at dawn), fade in. Allowed at night or
  once half the day has passed (`SleepRules.SLEEP_FROM_DAY_PROGRESS`), otherwise "Too early to sleep".
- While you sleep each crop not enclosed by fences has a 30% chance (`SleepRules.EAT_CHANCE`) to be eaten.
  Enclosed = a 4-neighbour flood fill from the crop can't reach the edge of the play area without crossing a fence.

### Gayle, the helper (`scripts/gayle.gd`, `gayle_brain.gd`, `gayle_talk.gd`)
- Imogen's spouse. Same layered sprite as Imogen with ginger hair, a pink shirt and purple pants.
- Follows Imogen (starts walking beyond 34 px, stops at 22 px). She is on physics layer 2, so she never blocks
  Imogen, but trees, ponds and the stall stop her. If she is stuck for 2 s or farther than 180 px she appears
  next to Imogen.
- Day: every 4 s (`Gayle.WATER_INTERVAL`) she waters the nearest dry crop within 4 tiles (`GayleBrain.WATER_REACH`).
- Night: she walks to the nearest slime that is eating a crop (within 150 px of Imogen) and hits it for 1 damage
  every second, weaker than Imogen's sword (1 + upgrades). Slimes ignore her.
- E next to her opens a short dialog: a line and a Follow me / Stay here toggle. In Stay mode she keeps her spot,
  still waters nearby crops by day and only hits slimes within 40 px at night.

### Saving
- One file, `user://save.json` (JSON, `"version": 1`). No database: the game is single-player and offline.
- Saved: day and clock, gold, seeds, crops in the bag, upgrades, fence pieces, restored buildings,
  tilled/wet soil, crops (type, stage, bites, wet ticks), fences (cell + HP), player position,
  facing, tool and seed, camera zoom, Gayle (position + Follow/Stay).
- Auto-save every dawn, on "Quit to Title" and when the window is closed. A night is never saved:
  a save made at night resumes just before the next dusk.
- Title: Continue (only if a valid save exists) and New Game (asks before deleting an existing save).
- A missing, damaged or other-version file counts as no save.

### First-day tips (tutorial)
- A small box at the top of the screen (`scripts/tutorial.gd`, steps in
  `scripts/tutorial_steps.gd`) walks a new player through:
  till (1 + Space) -> water (2) -> plant (3) -> wait/water until ripe -> harvest (E) -> sell (E at the stall) -> open the restoration board (E at the signpost)
  -> talk to Gayle (E) -> sleep in the farmhouse bed (E).
- Each tip moves on when the real thing happens (Farm signals `tilled`, `watered`, `planted`,
  `crop_ripened`, `harvested`, `Game.crops_sold`, `RestorationBoard.opened`, `GayleTalk.opened`, `Game.slept`). Doing a step early still counts.
- Guide arrow (`scripts/guide_arrow.gd`): when a tip sends the player somewhere (sell -> Azy,
  board -> the signpost, talk -> Gayle, sleep -> the farmhouse door, or the bed once inside), a
  yellow arrow bounces above that place. If the place is off-screen, the arrow sits at the screen
  edge and points towards it. Inside the farmhouse every other tip points at the exit. The arrow
  goes away with the tips (F1, done) and at night.
- At night, until the tips are done, the box shows a sword tip instead; the farming tip comes
  back in the morning.
- After the last step (sleeping), a last tip warns about the night and the sword (4), stays 8 s
  (`Tutorial.NIGHT_TIP_TIME`) and the box hides.
- F1 hides the tips. Once finished or hidden they stay off until the game is closed;
  a restart doesn't show them again.

### Farm goals (`scripts/farm_goals.gd`, `goals_list.gd`)
Recommendations, not requirements: no rewards, nothing is blocked, done goals stay ticked.
- `FarmGoals.build(Game.goal_state())` returns the ordered list (pure logic, tested):
  plant and harvest -> sell to Azy -> Well -> Farmhouse -> sleep in the farmhouse -> Chicken coop
  -> buy a chicken -> Barn -> buy a cow -> plant a fruit sapling in the orchard -> build a fence
  -> Windmill -> Greenhouse -> "Farm saved!" -> (late game) buy a sheep -> place a sprinkler -> raise a flock of 3 sheep.
  Each goal has a text, progress/target, done flag and
  a guide target ("where").
- Restore goals read "Restore the Well 80/150g" and become "Restore the Well - go to the board!"
  once the gold is there.
- Firsts that can't be derived from state (harvested, sold, slept, planted a fruit tree, built a
  fence, placed a sprinkler) are `Game.milestones`, saved in the save file. Older saves are guessed from what is restored.
- HUD: one line under "Farm 0/6" shows "Next: <first unfinished goal>" (hidden while the first-day
  tips are up). Click it or press G for the full list (`GoalsList`, shown on the inventory's Goals tab).
- Guide arrow: once the tips are finished or hidden, the arrow points at the current goal's place
  (board when a restoration is affordable, Azy for purchases, the orchard once you hold a sapling,
  the farmhouse for sleeping), by day only.

### Inventory (`scripts/inventory_panel.gd`, `inventory_rows.gd`)
A panel that slides up from the bottom, above the hotbar (never over it). Tab or the "Bag / Tab"
button next to the hotbar opens and closes it; it pauses like the shop and the music keeps playing.
It does nothing while the shop, board, pause menu or ending screen has the game paused.
- Backpack: things you use, each with its icon and count: seeds per crop type, fruit saplings, fence
  pieces, plus your gold. Clicking a seed type equips it (Seeds tool + that type); clicking fences
  selects the Fence tool; a sapling click equips it on the Seeds tool; all close the panel. The equipped
  one is highlighted.
- Storage: things you sell: crops, fruit, eggs, milk with count and value, and the total
  ("Worth 230g - sell at Azy's stall").
- Goals: the farm goals list (G and the HUD tracker open the panel on this tab).
- Left / Right or a click on a tab switches pages; empty pages say "Nothing here yet".
- The rows are pure data (`InventoryRows.backpack/storage/storage_total` from `Game.inventory_state()`, tested).

### Feedback (game feel)
Particles are a few square pixels in the pack's palette (`scripts/effects.gd`).

| Event | Effect | Triggered in |
|---|---|---|
| Tilling / un-tilling | dirt clumps kick up | `feedback.gd` on `Farm.tilled` / `Farm.untilled` |
| Watering | a few water drops fall on each wet tile | `feedback.gd` on `Farm.watered` |
| Crop ripe | looping sparkles on the crop until harvested | `crop.gd` |
| Crop eaten | leaf puff | `crop.gd` (`bite()` that finishes it) |
| Enemy hit | flashes white (`Effects.FLASH_TIME` 0.15 s) | `slime.gd` `take_hit` |
| Enemy dies or vanishes at dawn | puff in its colours | `slime.gd` `_start_dying` |
| Last 10 s of the day (`Game.NIGHT_WARNING_TIME`) | banner "Night is coming!", clock and time bar pulse red | `feedback.gd`, `hud.gd` |
| Night: a slime eating a crop off-screen | blinking red arrow at the screen edge pointing at it | `feedback.gd` (`EdgeArrows`) |

## Scope

### v1 (built)
One map, one crop (carrot), one enemy (green slime), HUD, end screen.

### Ideas for later (pick in order, one at a time)
1. ~~Sound effects and music.~~ — done: procedural SFX + day/night music (`tools/gen_audio.py`).
2. ~~More crops with different grow times and prices~~ — done: 10 crops (see the table in Rules; Sprint 3 B2).
3. ~~Upgrades at the stall~~ — done: shop with sword, watering can (hearts and heal removed in Sprint 2).
4. ~~Fences the player can build to slow slimes (Outdoor decoration/Fences.png).~~ — done:
   fence tool (5), bundles at the stall, slimes chew through them.
5. ~~Stronger enemies on later nights: big slimes, skeletons (bow/mage).~~ Done (slime sizes,
   per-night waves). Skeletons were removed again in Sprint 2.
6. ~~Title screen and pause menu.~~ (built)
7. ~~Save/load.~~ Done (Sprint 2 F3), see "Saving" below.
8. ~~Animals (chickens give eggs).~~ Done (Sprint 2 B3): chickens and cows, see "Animals".
9. ~~Late-game content.~~ Done (Sprint 3 B3): sheep and sprinklers, see "Animals" and "Sprinklers".

## Art direction

- Everything uses the Cute Fantasy pack (16x16 tiles, 64x64 character frames).
- AI-generated art (ChatGPT) is only for things the pack lacks: title screen art,
  logo, UI portraits. See `CLAUDE.md` -> "Generated art" for the rules.
