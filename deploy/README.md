# Hosting Slime Harvest on your VPS

Live at **https://slimeharvest.imogen.dev** (a VPS running nginx + certbot).
The web build is plain static files, so nginx just serves a folder. No game server runs yet
(that comes with online features later).

```
/srv/slime-harvest/
├── web/        index.html, index.js, index.wasm, index.pck ...   -> https://slimeharvest.imogen.dev/
└── download/   SlimeHarvest.exe                                   -> https://slimeharvest.imogen.dev/download/SlimeHarvest.exe
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

It exports both builds, uploads them over SSH and swaps them in at once. Players get the new
version on their next page load (the `no-cache` header makes browsers re-check the files).
Keep the SSH key outside this repo.

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
