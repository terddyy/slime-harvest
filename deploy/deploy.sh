#!/usr/bin/env bash
# Builds the web + Windows exports and uploads them to the VPS over SSH.
# Usage (Git Bash):  GODOT=<godot console exe> DEPLOY_HOST=user@your-vps ./deploy/deploy.sh
# Optional: DEPLOY_DIR (default /srv/slime-harvest), DEPLOY_SSH_KEY (private key file).
# Needs only ssh + tar on both sides. The upload goes to a temp folder first and is swapped in,
# so players never load a half-copied game.
set -euo pipefail

: "${DEPLOY_HOST:?Set DEPLOY_HOST, e.g. DEPLOY_HOST=user@your-vps}"
DEPLOY_DIR="${DEPLOY_DIR:-/srv/slime-harvest}"
SSH=(ssh)
if [ -n "${DEPLOY_SSH_KEY:-}" ]; then SSH=(ssh -i "$DEPLOY_SSH_KEY"); fi
GODOT="${GODOT:?Set GODOT to the Godot 4.7.2 console executable}"

cd "$(dirname "$0")/.."
rm -rf export/web
mkdir -p export/web export/windows
touch export/.gdignore  # keeps Godot from importing the exported files back into the project
"$GODOT" --headless --path . --export-release "Web" export/web/index.html
"$GODOT" --headless --path . --export-release "Windows Desktop" export/windows/SlimeHarvest.exe

upload() {  # upload <local folder> <remote folder>
	tar -C "$1" -cz . | "${SSH[@]}" "$DEPLOY_HOST" "set -e
		rm -rf '$2.new' && mkdir -p '$2.new' && tar -xz --no-same-owner -C '$2.new'
		chmod -R u=rwX,go=rX '$2.new'
		rm -rf '$2.old'; if [ -d '$2' ]; then mv '$2' '$2.old'; fi
		mv '$2.new' '$2' && rm -rf '$2.old'"
}

upload export/web "$DEPLOY_DIR/web"
upload export/windows "$DEPLOY_DIR/download"
echo "Deployed to $DEPLOY_HOST:$DEPLOY_DIR"
