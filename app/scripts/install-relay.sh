#!/usr/bin/env bash
# Installs (or updates) the Leveling Ledger relay on a Steam Deck or another Linux PC.
# It sends this device's add-on file to your hub, and keeps trying while the hub can't be reached.
# Run in Desktop Mode, in Konsole, from the downloaded project's app folder:
#   bash scripts/install-relay.sh
# Nothing outside your home folder is changed, and no administrator password is needed.
set -euo pipefail

DEST="$HOME/.local/share/leveling-ledger-relay"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_VERSION="v20.18.1"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT="leveling-ledger-relay.service"

mkdir -p "$DEST/app/lib" "$DEST/data"

# --- Node.js: use the one installed if it's 18 or newer, otherwise download it into $DEST/node ---
NODE=""
if command -v node >/dev/null 2>&1 && [ "$(node -p 'process.versions.node.split(".")[0]')" -ge 18 ]; then
  NODE="$(command -v node)"
elif [ -x "$DEST/node/bin/node" ]; then
  NODE="$DEST/node/bin/node"
else
  case "$(uname -m)" in x86_64) ARCH=x64 ;; aarch64) ARCH=arm64 ;; *) echo "Unsupported processor: $(uname -m)"; exit 1 ;; esac
  NAME="node-$NODE_VERSION-linux-$ARCH.tar.xz"
  echo "Downloading Node.js $NODE_VERSION into $DEST/node ..."
  TMP="$(mktemp -d)"
  curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/$NAME" -o "$TMP/$NAME"
  curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt" -o "$TMP/SHASUMS256.txt"
  (cd "$TMP" && grep " $NAME\$" SHASUMS256.txt | sha256sum -c -) || { echo "The Node.js download didn't match its published checksum; stopping."; exit 1; }
  rm -rf "$DEST/node" && mkdir -p "$DEST/node"
  tar -xJf "$TMP/$NAME" -C "$DEST/node" --strip-components=1
  rm -rf "$TMP"
  NODE="$DEST/node/bin/node"
fi
echo "Node.js: $NODE ($("$NODE" -v))"

# --- the relay (it reuses a few files from the app's lib folder) ---
cp "$SRC/relay.js" "$SRC/relay-boot.js" "$DEST/app/"
cp "$SRC"/lib/*.js "$DEST/app/lib/"

# --- settings ---
CFG="$DEST/relay.json"
if [ ! -f "$CFG" ]; then
  echo
  echo "Your hub's Cloudflare address, and the service token you made for this device (README: Other PCs and the Steam Deck)."
  read -rp "  Hub address (like https://ledger.example.com): " HUB
  read -rp "  Service token Client ID: " CID
  read -rsp "  Service token Client Secret: " SEC; echo
  DEFAULT_NAME="$(hostname)"; [ "$DEFAULT_NAME" = "steamdeck" ] && DEFAULT_NAME="Steam Deck"
  read -rp "  Name for this device [$DEFAULT_NAME]: " DEV; DEV="${DEV:-$DEFAULT_NAME}"
  read -rp "  World of Warcraft folder (leave blank to find it automatically): " WOW
  umask 077
  "$NODE" -e 'const [f, hub, id, sec, dev, wow] = process.argv.slice(1); const c = { hubUrl: hub.trim(), clientId: id.trim(), clientSecret: sec.trim(), device: dev }; if (wow) c.wowFolder = wow; require("fs").writeFileSync(f, JSON.stringify(c, null, 2) + "\n", { mode: 0o600 });' \
    "$CFG" "$HUB" "$CID" "$SEC" "$DEV" "${WOW:-}"
else
  echo "Keeping your existing relay settings in $CFG"
fi
chmod 600 "$CFG"

echo
echo "Checking the add-on files and the connection to your hub..."
LL_RELAY_CONFIG="$CFG" LL_RELAY_STATE="$DEST/data/relay-state.json" "$NODE" "$DEST/app/relay.js" --test || true

# --- run in the background with your user session (starts with the Deck, also in Game Mode) ---
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  mkdir -p "$UNIT_DIR"
  cat > "$UNIT_DIR/$UNIT" <<EOF
[Unit]
Description=Leveling Ledger relay
After=network-online.target

[Service]
ExecStart=$NODE $DEST/app/relay-boot.js
Environment=LL_RELAY_CONFIG=$CFG
Environment=LL_RELAY_STATE=$DEST/data/relay-state.json
Restart=always
RestartSec=30

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable "$UNIT" >/dev/null
  systemctl --user restart "$UNIT"
  echo
  echo "The relay is running and starts with your device. It sends this device's add-on data whenever you log out or /reload."
  echo "Check it with:   systemctl --user status $UNIT     and   journalctl --user -u $UNIT"
else
  echo
  echo "This system has no user services; start the relay yourself with:"
  echo "  LL_RELAY_CONFIG=\"$CFG\" LL_RELAY_STATE=\"$DEST/data/relay-state.json\" \"$NODE\" \"$DEST/app/relay-boot.js\""
fi
