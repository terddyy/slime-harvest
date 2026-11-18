# Slime Harvest

A cozy top-down farming game made with **Godot 4.7**. Imogen and Gayle arrive at a run-down
family farm: grow crops, raise chickens and cows, plant an orchard, sell at Azy's market stall,
and restore every building on the farm. At night, slimes come to eat your crops.

**Play it in the browser:** https://slimeharvest.imogen.dev
(Windows download: https://slimeharvest.imogen.dev/download/SlimeHarvest.exe)

Final Project, BS Computer Science 4, by **Imogen Inocentes** ([imogen.dev](https://www.imogen.dev)).

## Features

- Till, water, plant and harvest several crop types; build fences to slow the slimes down
- Restore six buildings (well, farmhouse, chicken coop, barn, windmill, greenhouse) from the restoration board
- Chickens and cows with daily eggs and milk, fruit trees in the orchard
- Gayle, a helper who follows you, waters crops by day and chases slimes at night
- Farm Goals (recommended next steps), an inventory with Backpack / Storage / Goals tabs
- Endless days, sleeping through the night, automatic saving
- Procedurally generated chiptune sound effects and music (`tools/gen_audio.py`)

## Running from source

The game art is **not in this repository**. It uses the premium
[Cute Fantasy RPG](https://kenmi-art.itch.io/cute-fantasy-rpg) asset pack by Kenmi, whose license
allows using it in games but not redistributing the files.

1. Buy/download the pack and copy its folders (`Animals/`, `Buildings/`, `Crops/`, `Player/`, `Tiles/`, ...)
   into `assets/cute_fantasy/`, keeping the original file names. `docs/ASSETS.md` lists every sheet the game uses.
   The app icon (`assets/icon.png`, a slime and a carrot from the pack) is not included either; without it
   Godot just shows its default icon.
2. Open the project in **Godot 4.7.2** (Project Manager > Import > `project.godot`) and press **F5**.

Tests (headless):

```bash
GODOT=<path to the Godot 4.7.2 console executable>
"$GODOT" --headless --path . --script res://tests/run_tests.gd   # unit tests
"$GODOT" --headless --path . res://tests/aim_test.tscn          # input/scene tests
```

## Project layout

- `scripts/` all game code (GDScript, one `class_name` per system), `scenes/` the two scenes (title, main)
- `tests/` unit and scene tests, plus a bot that plays the whole game (`tests/playthrough.tscn`)
- `docs/GDD.md` game design, `docs/ASSETS.md` sprite-sheet map, `CLAUDE.md` developer guide
- `deploy/` hosting the web build on a VPS (nginx or Caddy) and the deploy script
- `tools/gen_audio.py` generates every sound in `assets/audio/`

## License

Code, sounds and docs: [MIT](LICENSE). The Cute Fantasy art is © Kenmi and is not covered by this
license; get it from the link above.
