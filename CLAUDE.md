# Working in this repository

## Git
- Commit and push straight to `main`. Don't create branches or pull requests unless the owner asks.
- This repository is **public**. Never commit `config.json`, Blizzard or Cloudflare credentials, ledger data (`data/`, `store.json`, `seed.json`), SavedVariables files, logs, or anyone's email address. `.gitignore` covers these; keep it that way. Check staged files before each commit.

## Layout
- `app/`: Node.js server with no npm dependencies; Node 18 or newer. `server.js` plus `lib/`:
  - `store.js`: JSON document store
  - `watcher.js`: SavedVariables watcher
  - `addon-import.js`: add-on import
  - `blizzard.js`: Blizzard sync
  - `access.js`: Cloudflare Access JWT check
- Characters (`lib/characters.js`):
  - The main character's documents use plain paths (`state/character`).
  - Each alt's documents sit under a prefix derived from its Blizzard name (`c1a2b3c4.state/character`), in the same store.
  - `local-shim.js` adds the prefix for the character picked on the page (`?char=` or localStorage).
  - Server code that touches character data goes through `charStore(store, id)`.
- Relays (`app/relay.js`; installers `scripts/install-relay.ps1` and `scripts/install-relay.sh`):
  - Other PCs and the Steam Deck send their SavedVariables to the hub's `/api/relay/upload` with a Cloudflare service token.
  - The hub stores each file under `data/relay/<device>/<account>/` and imports it like its own.
  - The import keeps per-device state (`sourceKey`): loot is summed per device, and skills, reputation and vendors keep the newest.
  - A service token may only upload or ping.
- `app/public/`: the ledger page (`leveling-ledger.html`) and its game data. `local-shim.js` gives the page the storage interface it was written against (`window.claude.use("db")`), backed by `/api/*` and live updates through Server-Sent Events.
- `app/scripts/`: Windows install and uninstall scripts, using NSSM and the Local Service account. They can't run in Linux sessions, so review PowerShell changes by hand and keep the files ASCII-only.
- `addon/LevelingLedger/`: the WoW Forever add-on (Interface 16001, SavedVariables `LevelingLedgerDB`).
- `tools/`: the add-on simulator (`addon-simulate.py`, needs `lupa`) and the data-build scripts.

## Updates
- `app/lib/updater.js` installs the latest commit on `main` from GitHub when the owner presses Update.
  - It may only replace the files matched by `APP_FILES` and `ADDON_FILES`, never `scripts/` or `tools/`.
  - The server must keep parsing after each commit, because a broken `main` is what users get.
  - New top-level app files need adding to `APP_FILES` and to the installer's permission list.

## Testing changes
- Run the server against a throwaway config:

  ```bash
  LL_CONFIG=/path/to/test-config.json node app/server.js
  ```

  Point `dataDir` and `wowFolder` at scratch folders. For the Blizzard sync, set `blizzard.apiBase` and `blizzard.oauthUrl` to a local mock.
- Check the page in Playwright with no page errors.
- For access changes, check that forged, expired, wrong-audience and wrong-email tokens get 403.

## Product notes
- Roadmap: the "Leveling Ledger Roadmap" doc (Now, Next, Later).
- Character: Talwyn Orda, US, Normal ruleset, Night Elf Druid (`blizzard.character` = `talwyn-orda`, namespace `profile-forever-us`).
