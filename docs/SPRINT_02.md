# Sprint 2 — "Restore the Farm"

Turns Slime Harvest from a 7-night survival game into a cozy farm-restoration game with
saves. Decided with the owner on 2026-11-18.

## Sprint goal

Imogen arrives at a run-down family farm. By farming, raising animals and protecting crops
from slimes at night, Imogen (with the helper Gayle) earns enough to restore every building.
Restoring all of them is the "farm saved" ending; the game keeps going after it. Progress
is saved automatically.

## Decisions (already made)

| Topic | Decision |
|---|---|
| Survival | Removed. Slimes and skeletons never hurt the player. They only damage crops (and fences). No hearts, no death, no game-over. |
| Goal | Restore the farm: a list of buildings, each repaired with gold. All restored = ending banner + credits, then free play. |
| Days | Endless days. Night waves keep scaling with the day number. |
| Main character | Imogen (the current player character, renamed). |
| Gayle | A helper who follows Imogen: waters dry crops near them by day, chases slimes that are eating crops at night. |
| Save | **No database.** One local save file (`user://save.json`, JSON with a `version` field). Auto-save every morning, when sleeping, and on quit. Title screen gets Continue / New Game. A database (MySQL, Firebase...) is for many users sharing data online; this is a single-player offline game, so a file is the standard, simpler choice. |
| Scope | Buildings to restore, animals, enter the farmhouse, bigger map with areas. |

## Owner answers (2026-11-18)

1. **Imogen and Gayle are spouses** (husband and wife). Both use the layered farmer sprite with
   clearly different hair and clothes. Their short dialogue lines can reflect that they are a
   couple. Don't guess genders or pronouns in text beyond what the owner said; use names.
2. **Azy runs the market stall**: a shopkeeper NPC standing at the stall, using one of the
   premade sheets in `NPCs (Premade)/`, with a "Azy" name tag. Talking to Azy (E) opens the shop.
3. **Sleeping through the night: approved.** Sleeping skips the night; each crop that is not
   inside a fence has a 30% chance to be eaten.
4. **Skeletons: removed.** Delete skeleton + projectile scripts, their wave entries, tests and docs.

## Phases and tickets

Sizes: **S** < 1 h of agent work, **M** a few hours, **L** a day. Every ticket's
definition of done is at the bottom.

### Phase 1 — Foundations (sequential, orchestrator does these; everything else builds on them)

| ID | Ticket | Size | Notes |
|---|---|---|---|
| F1 | **Remove survival** | M | Delete player HP/hurt/death, hearts HUD, "hearts"/"heal" shop items, end screen "defeated". Slimes stop chasing the player (crops only). Remove skeletons and projectiles entirely (answer 4). Update tests, GDD, tutorial, How to Play. |
| F2 | **Endless days + restoration goal** | M | Remove `NIGHTS_TO_WIN`. `Waves` extends past night 7 by formula. New `Restoration` data: list of projects `{id, name, cost, unlocks}`; `Game.restored` set; `Game.restore(id)`; signal `farm_restored` when all done → ending banner + credits screen, then continue. |
| F3 | **Save system** | L | `SaveGame` autoload: `save()`, `load()`, `has_save()`, `delete()`. Each system exposes `to_save() -> Dictionary` / `from_save(data)`: Game (day, time, gold, seeds, bag, upgrades, restored), Farm (tilled/wet cells, crops with type/stage/ticks), Fences (cells + HP), player position/facing/tool, camera zoom. Versioned JSON; unknown/old versions fail safely to "no save". Auto-save at dawn and on quit. Title: Continue (only if a save exists) / New Game (confirm overwrite). Round-trip tests. |
| F4 | **New map layout framework** | L | Map grows to ~80x50 tiles, described as data in a new `world_layout.gd`: named areas (fields, building plots, pond, orchard, path to the stall, animal pens) + where trees/rocks go. Water + pond edges (map `Tiles/Water` autotile), dirt paths. Main builds the world from this layout. Phase 2 agents only fill in their own areas. |

### Phase 2 — Features (parallel agents in worktrees, after Phase 1 is merged)

| ID | Ticket | Size | Notes |
|---|---|---|---|
| B1 | **Buildings + restoration** | L | Farmhouse, barn, chicken coop, windmill (animated sails), well, greenhouse/shed. Unrestored plot = sign + rubble + faint outline of the building; restored = full building with collision and a door. Restore from a "Restoration board" next to the farmhouse (panel listing projects, costs, what each unlocks). Map building sheets in `docs/ASSETS.md`. |
| B2 | **Farmhouse interior + sleep** | M | Walk through the door into an interior scene (walls/floors/furniture from `Buildings/Houses_Interiors` + `House_Decor`), back out the same door. Bed: sleep → fade, skip to next morning, auto-save (night rule from Q3). Interior only open once the farmhouse is restored? (Proposal: the farmhouse is restored at the start; it's your home.) |
| B6 | **Azy, the shopkeeper** | S | NPC at the stall (premade sheet, idle animation, name tag); E on Azy opens the shop. Map the premade NPC sheet layout in `docs/ASSETS.md`. |
| B3 | **Animals** | M | Chickens (need coop) and cows (need barn), bought in the shop. Wander inside their pen, show a product bubble once a day (egg / milk), click to collect, sell in the shop. Slimes ignore animals. Saved. |
| B4 | **Gayle, the helper** | L | Imogen's spouse (answer 1). Layered sprite with a different look. Follows Imogen at a distance, never blocks them. Day: every few seconds waters one dry crop near Imogen. Night: walks to the nearest slime/skeleton eating a crop and hits it (weaker than Imogen). Talk with E: short lines, and a toggle Follow / Stay here. Saved (position + mode). |
| B5 | **Orchard + fruit trees** | S | Fruit trees from `Crops/*_Tree.png` in the orchard area: planted once (sapling from shop), grow over days, give fruit every few days. Saved. |

### Phase 3 — Integration and polish (orchestrator + 1-2 agents)

| ID | Ticket | Size | Notes |
|---|---|---|---|
| P1 | **Economy & restoration balance** | M | Restoration costs vs income from crops/animals/fruit so the farm is saved in roughly 15-20 in-game days for a normal player. Update the bot playthrough to a "restore everything" goal and report days needed. |
| P2 | **Save coverage** | S | Every Phase-2 system saves and loads; one test that plays a few days, saves, reloads and compares. |
| P3 | **Tutorial, How to Play, Credits** | S | New first-day tips (restoration board, Gayle, sleeping). Credits: Gayle. |
| P4 | **Final QA + build** | S | All tests, playthrough, visual check of every area, Windows export. |

## Order and parallel work

```
Phase 1 (sequential):  F1 -> F2 -> F3 -> F4          merge, build, play-test
Phase 2 (parallel):    B1 | B2 | B3 | B4 | B5 | B6   each in its own worktree
                       merge order: B1, B2, B6, B3, B5, B4 (Gayle last: touches the most systems)
Phase 3:               P1 -> P2 -> P3 -> P4
```

Why Phase 1 is sequential: F1-F4 change rules, the save contract and the map that every
feature depends on. Doing them first keeps Phase 2 agents from all editing `main.gd` and
`game.gd` at once.

## Definition of done (every ticket)

- Static-typed GDScript following `CLAUDE.md`; new systems in new files where possible.
- `tests/run_tests.gd`, `tests/aim_test.tscn` and the playthrough pass; new logic has tests.
- If the system has state, it saves and loads (from F3 on).
- `docs/GDD.md`, `docs/ASSETS.md` (new sheets), `CLAUDE.md` Layout and How to Play updated.
- Checked visually from recorded frames; no captures or temp files in the repo.
- Windows `.exe` exports and starts.

## Risks

| Risk | Mitigation |
|---|---|
| Bigger map makes `main.gd` a conflict hotspot | F4 moves layout into data first; Phase 2 only adds to its own area. |
| Save format changes as features land | Versioned JSON, each system owns its own `to_save/from_save`, P2 round-trip test. |
| Gayle's AI gets stuck on buildings/fences | Simple steering + teleport back next to Imogen if stuck or too far. |
| Balance unknown | Bot playthrough reports days-to-restore; owner play-tests after Phase 1 and Phase 2. |
| No "ruined building" art in the pack | Plot = sign + rubble + faint outline; restored = full building. |
