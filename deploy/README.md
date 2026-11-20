# Hosting Slime Harvest on your VPS

Live at **https://slimeharvest.imogen.dev** (a VPS running nginx + certbot).
The web build is plain static files, so nginx just serves a folder. The only program that runs
is the co-op room relay (see "Online co-op" below).

```
/srv/slime-harvest/
├── web/        index.html, index.js, index.wasm, index.pck ...   -> https://slimeharvest.imogen.dev/
├── download/   SlimeHarvest.exe                                   -> https://slimeharvest.imogen.dev/download/SlimeHarvest.exe
└── relay/      relay.gd (the co-op room relay)                    -> run by systemd, reached at wss://slimeharvest.imogen.dev/relay
```

## One-time setup (done 2026-11-19)

1. DNS: an `A` record for the subdomain (e.g. `slimeharvest`) pointing at the VPS IP.
2. `/srv/slime-harvest` created on the VPS.
3. nginx: `nginx.conf.example` installed as `/etc/nginx/sites-available/slimeharvest.imogen.dev`,
   symlinked into `sites-enabled`, `nginx -t && systemctl reload nginx` (reload keeps the other sites up).
4. HTTPS: `certbot --nginx -d slimeharvest.imogen.dev` once DNS points at the VPS; the existing
   certbot timer renews it.

`Caddyfile.example` is the same setup for a server that runs Caddy instead of nginx.

## Each release (from this PC, in Git Bash)

```bash
GODOT=<godot console exe> DEPLOY_HOST=<user>@<vps-ip> DEPLOY_SSH_KEY=<path to the VPS key> ./deploy/deploy.sh
```

It exports both builds, uploads them (and `server/relay.gd`) over SSH and swaps them in at once. Players get the new
version on their next page load (the `no-cache` header makes browsers re-check the files).
Keep the SSH key outside this repo.

## Online co-op: the relay (one-time setup)

Friends join a farm with a room code. The game talks to `wss://slimeharvest.imogen.dev/relay`;
nginx forwards that to `server/relay.gd`, a small script run by a headless Godot (it keeps no files
and no game data, it only passes packets between the players of one room, 4 at most).
Nothing here has been run on the VPS yet. Do these steps once, on the VPS, as root:

1. Put the Linux Godot 4.7.2 binary (`Godot_v4.7.2-stable_linux.x86_64`, the normal editor
   build works headless) at `/opt/godot/godot` and `chmod +x` it.
2. `mkdir -p /srv/slime-harvest/relay`, then run `./deploy/deploy.sh` from this PC once: it uploads
   `relay.gd` there.
3. Copy `deploy/slime-relay.service` to `/etc/systemd/system/`, then
   `systemctl daemon-reload && systemctl enable --now slime-relay`.
   Check it: `systemctl status slime-relay` and `journalctl -u slime-relay -n 20`
   (it prints "relay: listening on 127.0.0.1:9080").
4. nginx: add the `location = /relay { ... }` block from `nginx.conf.example` to the **HTTPS**
   server block of the site (certbot made it), then `nginx -t && systemctl reload nginx`.
   Without it the browser gets the web page instead of a WebSocket and the game says it
   can't reach the room server.
5. Try it: open the game in two browsers, "Play Together", host in one and join with the code in the other.

Later releases: `deploy.sh` uploads the new `relay.gd`; it only takes effect after
`systemctl restart slime-relay`, which ends every online game in progress, so do it at a quiet
time (`RESTART_RELAY=1 ./deploy/deploy.sh` does both). Players on an old web build keep
working with a new relay as long as the packet format stays the same.

Good to know: the relay allows 200 rooms and 600 connections at once and only listens on
127.0.0.1, so the only way in is through nginx. To test it without nginx on any PC:
`"$GODOT" --headless --script server/relay.gd -- --port=9080` and start the game with
`-- --relay=ws://127.0.0.1:9080`.

## Try the web build locally first

```bash
"$GODOT" --headless --path . --export-release "Web" export/web/index.html
python -m http.server 8060 --directory export/web
```
Open http://localhost:8060. (Opening `index.html` straight from disk does not work; it needs a server.)

## Good to know

- **Saves in the browser** live in the browser's storage (IndexedDB) for that site. Clearing site
  data deletes them, and they don't move between browsers or devices. The web build saves at dawn,
  when sleeping, and whenever the tab loses focus (a closing tab gives no warning).
- **Quit** is hidden on the web title screen; players close the tab.
- **Size:** the first load downloads roughly 40-80 MB (engine + game), then it's cached.
- **Art license:** check the Cute Fantasy pack's license allows publishing the game before making it public.
