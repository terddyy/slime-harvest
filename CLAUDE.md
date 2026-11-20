# Slime Harvest — guide for AI assistants

Top-down "farm by day, defend by night" game. Godot **4.7.2**, GDScript only.
Final school project; the owner is learning Godot, so keep code simple and readable.

Read first:
- `docs/GDD.md` — what the game is, rules, scope and the ordered list of next features.
- `docs/ASSETS.md` — sprite-sheet layouts (rows, frame sizes, cell coords). **Check it
  before using any sheet**, and add to it whenever you map a new sheet.

## Running

Godot is not on PATH. Executables:
```
GODOT="<path to Godot_v4.7.2-stable_win64_console.exe>"   # the real path is in CLAUDE.local.md (not in git)
```
- Import assets (needed after adding PNGs): `"$GODOT" --headless --path . --import`
- Run tests: `"$GODOT" --headless --path . --script res://tests/run_tests.gd`
- Export the Windows build (templates for 4.7.2 x86_64 are installed in
  `%APPDATA%/Godot/export_templates/4.7.2.stable/`; preset in `export_presets.cfg`):
  `"$GODOT" --headless --path . --export-release "Windows Desktop" export/windows/SlimeHarvest.exe`
  → one self-contained .exe (game data embedded). `export/` is git-ignored. Check it starts with
  `export/windows/SlimeHarvest.exe --write-movie <scratch>/f.png --fixed-fps 30 --quit-after 45`.
- Export the web build (preset "Web", thread support off so no COOP/COEP headers are needed;
  web_nothreads templates installed): `"$GODOT" --headless --path . --export-release "Web" export/web/index.html`.
  Try it with `python -m http.server 8060 --bind 127.0.0.1 --directory export/web`. Hosting on the
  owner's VPS (nginx, https://slimeharvest.imogen.dev) and the upload script: `deploy/README.md`. Code that can't work in a browser
  (quitting, window close) checks `OS.has_feature("web")`.
- Aim regression test (real input events, exit 1 on failure):
  `"$GODOT" --headless --path . res://tests/aim_test.tscn`
- Restore-everything playthrough by a bot (farms, keeps animals + orchard, buys projects in order;
  prints per-night numbers and the day each building was restored; exit 0 = farm saved, 1 = not
  saved after 40 days; ~20-60 s, results vary run to run, so run it twice):
  `"$GODOT" --headless --path . res://tests/playthrough.tscn --fixed-fps 60 --quit-after 600000 -- --mode=defend`
  (`--mode=idle` = nobody defends, stops after 7 nights (exit 0), shows how much an undefended field loses).
  Run it after any change to enemies, waves, economy, prices or the day/night flow. The bot
  waters for free and plants/harvests 1 tile per 6 s; the target is the farm saved in about 15-20 days.
  "Leaked AudioStreamPlaybackWAV" lines at exit are sounds still playing at quit (harmless).
- Smoke-run the game for ~5 s and print errors: `"$GODOT" --headless --path . --quit-after 300`
  (that starts on the title screen; add `res://scenes/main.tscn` before `--quit-after` to run the game itself)
- Screenshot frames: `"$GODOT" --path . --write-movie <scratch>/frame.png --fixed-fps 30 --quit-after 60`
  (opens a window briefly; writes frame00000000.png ...). Never write captures inside the repo.
  To stage a specific situation, make a temporary scene whose script (`extends Node`)
  instances `scenes/main.tscn` as a child, sets things up, and run that scene instead of
  the main one. Delete it afterwards.
- Gotcha: scripts run with `--script` can't compile anything that references the `Game`
  autoload (player.gd, main.gd, ...). Tests that need those must run as a scene.

Always run the tests and the smoke run after a change and fix any `SCRIPT ERROR` / `ERROR` lines.

## Layout

```
project.godot        window 480x270 scaled x2, nearest filtering, autoloads Game, Audio
scenes/title.tscn    start scene (run/main_scene): title screen
scenes/main.tscn     game scene: Ground, Farm, Cursor, Entities(y-sorted: Player), NightTint, HUD, PauseMenu
scripts/save_game.gd  autoload "SaveGame": save file (user://save.json), systems register to_save/from_save
scripts/save_util.gd class SaveUtil: safe readers for save data
scripts/game.gd      autoload "Game": settings, clock (day/night), gold, seeds/crops per type, fence pieces,
                     upgrade levels + prices, end of run, input map, scene changes
scripts/world_layout.gd class WorldLayout: the 80x50 map as data (areas, ponds, paths, trees, rocks; tested)
scripts/ground_builder.gd class GroundBuilder: paints grass, dirt paths and ponds from WorldLayout
scripts/main.gd      builds the world from WorldLayout (trees, rocks, stall), creates the Spawner, Fences, Shop, Tutorial
                     and Feedback, tint, E key (shop/harvest)
scripts/audio.gd     autoload "Audio": sound effects (voice pool) + looping music with crossfade; buses Master/Music/SFX
scripts/settings.gd  class Settings: volumes, fullscreen, key bindings + rebind rules, user://settings.cfg (pure, tested); Game.settings
scripts/settings_menu.gd class SettingsMenu: volume sliders, fullscreen, key rebinding (title + pause menu)
scripts/farm.gd      class Farm (TileMapLayer): tilled/wet soil autotile + crops by cell
scripts/fences.gd    class Fences: built fences by cell (autotile, HP); slimes chew through them
scripts/sprinklers.gd class Sprinklers: late-game sprinklers by cell, water their 3x3 each sunrise (tested)
scripts/crop.gd      class Crop: crop type table (TYPES), growth stage, bites
scripts/credits.gd   class Credits: credits panel + title footer; developer/course names live here
scripts/credits_roll.gd class CreditsRoll (CanvasLayer): scrolling end credits (text from Credits.roll_lines())
scripts/story_panels.gd class StoryPanels (CanvasLayer): illustrated intro / ending panels, click/E/Space next, Esc skips
scripts/camera_zoom.gd class CameraZoom (Camera2D): follows the player; + / -, Ctrl+wheel, pinch zoom
scripts/player.gd    class Player: movement, layered sprite animation, tools, seed choice (no health)
scripts/farmhouse.gd class Farmhouse: farmhouse door + interior room (far off-map), bed sleeps to morning
scripts/sleep_rules.gd class SleepRules: when you can sleep, which crops slimes eat meanwhile (pure, tested)
scripts/shop.gd      class Shop (CanvasLayer): market stall panel, sell/buy seeds/upgrades, pauses
scripts/building_data.gd class BuildingData: art, plot and walls of each restorable building (pure data, tested)
scripts/building.gd  class Building: one building, ruin (sign, rubble, ghost) or restored (sprite, walls)
scripts/buildings.gd class Buildings: creates all buildings + the board signpost, syncs with Game.restored
scripts/restoration_board.gd class RestorationBoard (CanvasLayer): panel to pay for restoration projects, pauses
scripts/shopkeeper.gd class Shopkeeper (Node2D): Azy at the market stall, idle animation + name tag
scripts/spawner.gd   class Spawner: spawns each night's wave at the map edges, clears enemies at dawn
scripts/waves.gd     class Waves: per-night wave table + scaling for endless nights (pure data, tested)
scripts/orchard.gd    class Orchard: fruit trees in the orchard area (sapling, grow by day, fruit), saved
scripts/plant_cycle.gd class PlantCycle: what the Seeds tool cycles through, seeds then owned saplings (pure, tested)
scripts/restoration.gd class Restoration: restoration projects {id, name, cost, unlocks} (pure data, tested)
scripts/slime.gd     class Slime: small/medium/big; chase crops, eat, take hits, big splits (never hurts the player)
scripts/animal_types.gd class AnimalTypes: chicken/cow/sheep + egg/milk/wool data, buy rules (pure data, tested)
scripts/animal.gd    class Animal: wanders in its pen, product bubble, collect()
scripts/herd.gd      class Herd: spawns/collects/saves the animals (E or click)
scripts/hud.gd       class Hud (CanvasLayer): labels, hotbar, banner, restoration count, ending screen
scripts/tutorial.gd  class Tutorial (CanvasLayer): first-day tips box, listens to Farm/Game events, F1 hides
scripts/farm_goals.gd  class FarmGoals: ordered farm goals (quest-like recommendations) from a state snapshot (pure, tested)
scripts/goals_list.gd  class GoalsList (VBoxContainer): all goals, done ticked, current highlighted; the inventory's Goals tab
scripts/inventory_panel.gd class InventoryPanel (CanvasLayer): Tab / bag button / G; slides up; Backpack, Storage, Goals tabs; pauses
scripts/inventory_rows.gd class InventoryRows: backpack and storage rows + total value from Game.inventory_state() (pure, tested)
scripts/tutorial_steps.gd class TutorialSteps: tutorial steps + texts + guide targets (pure logic, tested)
scripts/guide_arrow.gd class GuideArrow (CanvasLayer): yellow arrow to where the current tip sends you
scripts/effects.gd   class Effects: particle puffs, sparkles, white hit flash, screen shake (static helpers)
scripts/feedback.gd  class Feedback: farm particles, night warning, off-screen enemy arrows
scripts/gayle.gd     class Gayle (CharacterBody2D): spouse helper, follows Imogen, waters by day, fights eating slimes at night
scripts/gayle_brain.gd class GayleBrain: pure target choice for Gayle (tested)
scripts/gayle_talk.gd class GayleTalk (CanvasLayer): E dialog, Follow / Stay toggle, pauses
scripts/cursor.gd    tile highlight in front of the player
scripts/loading_screen.gd class LoadingScreen (scenes/loading.tscn): title -> farm, loads main.tscn on a thread with bar + tip
scripts/loading_tips.gd class LoadingTips: tip list + progress percent (pure, tested)
html/shell.html   custom web shell (logo, progress bar, tip); boot splash = logo.png via project.godot
scripts/title.gd     title screen: farm backdrop with hopping slimes, Start / How to Play / Quit
scripts/pause_menu.gd class PauseMenu (CanvasLayer): Esc menu, pauses the tree
scripts/how_to_play.gd class HowToPlay: goal + controls panel (title and pause menu)
scripts/ui_style.gd  class UiStyle: shared menu theme, panels and buttons (static helpers)
tests/run_tests.gd   headless tests (SceneTree script, no addons)
tools/gen_audio.py   generates every WAV in assets/audio/ (Python stdlib only)
tools/gen_late_game_icons.py draws assets/generated/late_game_icons.png (wool + sprinkler, Pillow)
assets/generated/     our own generated art (logo, icon, prompts); tools/process_generated_art.py downsizes raw renders
assets/audio/        sfx/*.wav one-shots, music/*.wav loops (generated, don't hand-edit)
assets/cute_fantasy/ the art pack (do not rename files, paths are referenced in code)
docs/                design + asset docs
deploy/              VPS hosting: nginx.conf.example (live setup), Caddyfile.example, deploy.sh (export + upload over SSH), README
```

## Audio

All sounds are generated chiptune-style by `tools/gen_audio.py` (no audio in the art pack).
- Regenerate after editing the script: `python tools/gen_audio.py`, then re-import
  (`"$GODOT" --headless --path . --import`). Mono 16-bit 22050 Hz; total ~2.4 MB.
- New sound: add a function and an entry in `SFX` / `MUSIC` in the script, run it, re-import.
- `Audio.play_sfx("name", pitch_variation := 0.0)` plays `assets/audio/sfx/name.wav`
  (0.1 = random pitch 0.9x-1.1x). `Audio.play_music("name")` crossfades to
  `assets/audio/music/name.wav` and loops it (loop set in code, no-op if already playing).
  `Audio.stop_music()` fades it out. A missing name only prints a warning.
- Hook sounds with one-line calls next to the event they belong to.
- Headless runs use a dummy audio driver. If music is still playing when Godot quits
  (e.g. `--quit-after`), Godot prints "ObjectDB instances leaked" / "resources still in
  use" for the music stream. That's an engine shutdown quirk, not a bug in our code.

## Conventions

- Static typing everywhere (`var x: int`, `-> void`). Constants in `UPPER_SNAKE_CASE` at the top.
- Each gameplay script has `class_name` and builds its own child nodes in `_ready()`.
  Scenes stay minimal so the files are easy for both humans and AI to edit.
- Systems talk through signals or the `Game` autoload; don't reach into another node's
  private `_vars`.
- Tile cells are `Vector2i`; world positions are `Vector2`. Tile size is 16.
- A node's `position` is its **feet** (bottom-centre). Sprites are offset upward so
  y-sorting in `Entities` works.
- Enemies are duck-typed: every enemy joins group `"enemies"` and has `take_hit(damage, from)`,
  `body_center() -> Vector2`, `vanish()` and `signal killed(world_pos, gold)`. A new enemy type
  only needs those plus a case in `Spawner.spawn()` and an entry in `Waves.KINDS`.
  Ground enemies get `fences` from the Spawner and must not step onto a fence tile
  (check `fences.blocks(from, to)` before moving).
- Hit detection uses simple distance checks, not physics areas. Only the player and
  obstacles (trees, stall) use physics bodies.
- Tuning numbers are constants in the script that owns them. If you change one,
  update `docs/GDD.md` if the rule is described there.
- One feature at a time, in the order of the GDD's "Ideas for later" list unless the owner
  says otherwise. Keep each change small.

## Generated art (ChatGPT / other image models)

The pack covers the game world. Only generate what it lacks (title art, logo, portraits).
- Save as PNG with transparency into `assets/generated/<name>.png`.
- In-world sprites must be on a 16 px grid, pixel art, no anti-aliasing, and match the
  pack's palette. If generated art doesn't look like the pack, don't use it in the world.
- Note the prompt used next to the file (`<name>.prompt.txt`) so it can be regenerated.

## Licensing

The Cute Fantasy PNGs can't be redistributed. If this becomes a git repo, keep it **private**
or add `assets/cute_fantasy/` to `.gitignore`.
