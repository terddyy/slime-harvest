# Sprint 3: "Finish the Farm, Play Together"

Takes Slime Harvest from a finished single-player loop to a complete game: its own art and a
loading screen, settings, more content, a story with intro and ending, and **online co-op**
(friends join your farm with a room code). Decided with the owner on 2026-11-20. Time is not
a constraint; quality and a game that keeps working are.

## Decisions (already made)

| Topic | Decision |
|---|---|
| Art | Generated with the `gpt-image` skill (Codex renders through the owner's ChatGPT plan): `& "$HOME\.claude\skills\gpt-image\generate.ps1" -PromptFile <txt> -OutPath <png>` (30-120 s, use a 300000 ms timeout). Save to `assets/generated/<name>.png` with `<name>.prompt.txt` next to it (CLAUDE.md "Generated art"). Only for what the pack lacks: logo, title art, app icon, loading art, story illustrations, portraits. **Read every image you generate** and redo it once if it misses the brief; at most 2 renders per asset. Generated art is ours, so it is tracked in git (unlike `assets/cute_fantasy/`). |
| Icon | A new generated icon replaces the pack-derived `assets/icon.png`: save as `assets/generated/icon.png`, point `config/icon` and the export presets at it, so the public repo gets a real icon. |
| Co-op model | **Host-authoritative.** The host plays their normal game (their own save). Friends join by a 6-character room code and play as extra farmers on the host's farm. Only the host simulates crops, slimes, animals, Gayle and the clock, and only the host saves. Solo play stays exactly as it is today. |
| Co-op transport | **WebSocket through a relay on the VPS.** `server/relay.gd`: a headless Godot script (no new dependencies) that listens on a local port (default 9080), handles rooms (create/join, max 4 players, codes from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`), gives the host peer id 1 and joiners 2, 3..., and forwards packets between players in the same room. Clients use `RelayPeer` (`extends MultiplayerPeerExtension`) so game code uses normal Godot `@rpc` with the host as the server (peer 1). Works in the browser and the desktop exe. Production URL: `wss://slimeharvest.imogen.dev/relay` (nginx proxies to the relay). Tickets only write the deploy files; **touching the VPS is done later by the orchestrator, with the owner's approval.** |
| Co-op sync | Joining: the host sends a full snapshot that reuses the `SaveGame` data (each system's `to_save()`); the joiner loads it with `from_save()` without writing a save file. After that: joiners send **intents** (move input, "use tool at cell", "buy X", "restore Y"); the host checks and applies them, then broadcasts results (cell changes, crop stages, gold, slimes, animals, buildings, clock). Player positions at about 15 Hz with interpolation. |
| Co-op rules | Gold, seeds, bag and storage are **shared** by the whole farm. Each player has their own tool and seed choice. In online play, panels (shop, board, inventory, Esc menu) **don't pause** the world. Sleeping skips the night only when **every** player is in bed ("Waiting for 1 more..."). If the host leaves, joiners get "The host left" and return to the title. Joiners never write `user://save.json`. |
| Story | Intro (new game only, skippable): a few illustrated panels with short text explaining why Imogen and Gayle came to the run-down family farm. Ending (after the last restoration): illustrated panels, then scrolling credits, then "Keep playing". Use names, no guessed pronouns (Imogen and Gayle are spouses; see SPRINT_02 owner answers). |
| Settings | `user://settings.cfg` (ConfigFile): master/music/sfx volume, fullscreen (hidden on web), key rebinding for the actions in `Game.KEY_BINDINGS`. Reachable from the title and the pause menu. Rebinding also fixes cases where a browser extension steals a key. |

## Phases and tickets

Every ticket follows the Definition of done at the bottom and writes a handover note
`docs/sprint03/<ID>.md` (what changed, files, how it was tested, known limits). Read the
handover notes of earlier tickets before starting.

### Phase A: Look and feel

| ID | Ticket | Notes |
|---|---|---|
| A1 | **Logo, title art, icon** | Generate: a "Slime Harvest" logo (transparent background, pixel-art feel matching the Cute Fantasy palette, readable at 480x270), a title-screen illustration or a decoration that fits behind the existing farm backdrop, and the app icon (slime + crop, 1:1). Downscale big renders to their display size (a Python/Pillow or a Godot tool script with Lanczos; check what's available) so they don't look jagged under nearest filtering. Use the logo on the title screen in place of the text title (keep the tagline "Restore the farm. Protect the harvest."). Replace the icon as in Decisions. Update `docs/ASSETS.md` with a "Generated art" section. |
| A2 | **Loading screens** | (1) Web: a custom HTML shell (`html/custom_html_shell`) with the logo, a styled progress bar using Godot's progress callback, a short tip line, matching colors; it must still work with thread support off. (2) Desktop: boot splash with the logo (`application/boot_splash/*`). (3) In game: going from the title to the farm (New Game / Continue) shows a loading screen with a progress bar using `ResourceLoader.load_threaded_request`, plus a random tip. Test the web build locally with `python -m http.server`. |
| A3 | **Settings menu** | As in Decisions. Audio buses Master/Music/SFX (create them in code or a bus layout, and make `Audio` play on the right bus). Rebinding: click an action, press a key, Esc cancels, duplicates are swapped or refused with a message, "Reset to defaults". Settings load at startup, before the input map is used. Tests for the save/load of settings and the rebinding rules (pure logic class). How to Play shows the current keys. |

### Phase B: Complete the game

| ID | Ticket | Notes |
|---|---|---|
| B2 | **More crops** | Add about 6 crops from `Crops/Crops.png` (map the rows you use in `docs/ASSETS.md`), each with its own grow time, seed price and sell price, so there are early/mid/late choices. Some unlock only after a building is restored (e.g. greenhouse crops), shown in the shop. Rebalance with the playthrough bot (target still about 15-20 days to save the farm; run it twice). Update GDD and Farm Goals if relevant. |
| B3 | **Late-game content** | Things to buy after the farm is restored, so free play has goals: sprinklers (water a 3x3 area every morning; placeable item, saved, slimes ignore them) and one new animal if the pack has its art (check `Animals/`; otherwise skip it and say so in the handover). Add 2-3 new Farm Goals for them. Tests for the new pure logic. |
| B4 | **Story: intro and ending** | As in Decisions. Generate 3-4 intro panels and 3-4 ending panels with `gpt-image` in one consistent style (same prompt preamble for all; describe Imogen's and Gayle's look from the farmer sprites so they match the game). A reusable `StoryPanels` CanvasLayer: image, text box, click/E/Space for next, Esc skips. Intro plays on New Game before the tutorial; the ending replaces the current "farm saved" pause with panels and then scrolling credits (`Credits` holds the names), then Keep playing / Quit to Title. Saved flag so the intro never repeats. |
| B1 | **Polish and bugs** | Run every test, the smoke runs and the playthrough (both modes) and fix every error/warning. Screenshot every panel (title, how to play, settings, shop, board, inventory, Gayle talk, pause, story, ending) at 480x270 and fix clipped or overflowing text and misaligned UI. Read the tutorial and Farm Goals texts and make them clear and consistent with the new content. List anything you didn't fix in the handover. |

### Phase C: Online co-op (after Phases A and B are merged)

| ID | Ticket | Notes |
|---|---|---|
| C1 | **Net foundation** | `server/relay.gd` (+ how to run it locally: `"$GODOT" --headless --script res://server/relay.gd -- --port=9080`), `scripts/relay_peer.gd` (MultiplayerPeerExtension over `WebSocketPeer`), `scripts/net.gd` autoload `Net`: `host() -> code`, `join(code, name)`, `leave()`, `is_online()`, `is_host()`, players list, signals (`room_created`, `joined`, `player_joined`, `player_left`, `failed(reason)`, `host_left`). Relay URL from a constant with a local override (`--relay=ws://127.0.0.1:9080`). An automated test that starts a relay and two clients (host + joiner) and checks an RPC round trip and a disconnect. The `server/` folder is excluded from exports. |
| C2 | **Lobby + remote players** | Title: "Play Together": Host (shows the room code and who joined; Start) and Join (code + name). Joiner gets the snapshot and loads the farm without saving. Remote farmers: the layered farmer sprite with a different color per player, name tag, synced position/facing/animation with interpolation. Join/leave banners. Host leaving: message + back to title. |
| C3 | **World sync** | Every joiner action goes through the host as an intent: till/untill, water, plant seeds and saplings, harvest, build fences, hit slimes, collect eggs/milk, shop buy/sell, restore buildings, sprinklers. The host broadcasts results; slimes, animals, Gayle, the clock, gold and the inventory are replicated. Panels don't pause in online play; sleeping needs every player in bed. A test that drives host + joiner through till -> plant -> harvest and checks both worlds match. |
| C4 | **Co-op polish + deploy files** | Edge cases (joining mid-night, joining while the host is in the farmhouse, a full room, a wrong code, the relay is down → friendly message). `deploy/`: nginx `location /relay` WebSocket proxy snippet, a systemd unit for the relay, `deploy.sh` uploads the relay script; `deploy/README.md` steps. GDD "Online co-op" section, How to Play, CLAUDE.md layout. **Do not connect to the VPS.** |

### Phase D: Release (orchestrator, with the owner)

Deploy the web/desktop builds and the relay to the VPS after the owner approves that scope,
then push to the public repo.

## Definition of done (every ticket)

- Follows CLAUDE.md (static typing, `class_name`, constants at the top, simple readable code, one
  feature) and the global rules: stage files by explicit path (never `git add .`/`-A`), no QA
  screenshots or captures inside the repo (use the session scratchpad), no AI mentions or
  co-author lines in commits.
- Unit tests pass, `tests/aim_test.tscn` passes, the smoke runs (title and `scenes/main.tscn`) print
  no `SCRIPT ERROR`/`ERROR` lines. Run the playthrough when the ticket touches the economy, enemies
  or the day/night flow.
- The visible result is checked with a screenshot (`--write-movie` into the scratchpad) and Read.
- GDD, CLAUDE.md layout, ASSETS.md and How to Play are updated where they describe what changed.
- One commit (or a few) on `main`, conventional message `feat(scope): ...`, not pushed.
- Handover note `docs/sprint03/<ID>.md` committed with the work.
