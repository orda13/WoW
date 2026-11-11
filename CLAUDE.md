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
  - `export.js`: `/api/export?char=&what=` downloads, for the Ledger tab's Export panel: CSV (sessions, levels, quests, characters, items; cells that look like formulas get a leading apostrophe) or JSON (the character's documents plus the shared ones)
- Characters (`lib/characters.js`):
  - The main character's documents use plain paths (`state/character`).
  - Each alt's documents sit under a prefix derived from its Blizzard name (`c1a2b3c4.state/character`), in the same store.
  - `local-shim.js` adds the prefix for the character picked on the page (`?char=` or localStorage).
  - Server code that touches character data goes through `charStore(store, id)`.
  - Characters the add-on records are tracked automatically (`newAlts` in `lib/settings.js`, as `name-<main's realm>`, up to 10). Ones removed in Settings go to `config.altsRemoved` and aren't added again.
  - The Ledger tab's Your characters table removes a character with its ×: it goes in `shared/hiddenchars` (keyed `<account>/<key>`), drops out of the page, `Shared.lua` and auto-tracking, and leaves Settings' list (re-added on "bring back").
- Relays (`app/relay.js`; installers `scripts/install-relay.ps1` and `scripts/install-relay.sh`):
  - Other PCs and the Steam Deck send their SavedVariables to the hub's `/api/relay/upload` with a Cloudflare service token.
  - The hub stores each file under `data/relay/<device>/<account>/` and imports it like its own.
  - The import keeps per-device state (`sourceKey`): loot is summed per device, and skills, reputation and vendors keep the newest.
  - A service token may only upload, ping, or fetch `/api/relay/summary`.
  - The in-game summary: the hub and each relay write `Shared.lua` into the add-on folder from that JSON, using `lib/summary.js`.
    - WoW runs that file, so it's generated only through `toLua`: numbers, and strings with every special or non-ASCII byte escaped.
    - Updates and installers never overwrite `Shared.lua`.
  - Relays update themselves to the hub's files (`/api/relay/version` and `/api/relay/bundle`, from `lib/relaybundle.js`).
    - The files are `relay.js`, `lib/*.js` and the add-on from the hub's own `addon/` copy.
    - Add-on files are installed only while no `Wow*.exe` is running.
    - `relay-boot.js` starts the relay, and nothing ever updates it. It rolls back an update that fails to start three times.
- `app/public/`: the ledger page (`leveling-ledger.html`) and its game data. `dungeons-curated-forever.json` holds dungeon bosses and loot pasted from Wowhead's Forever dungeon journal (`tools/data-build/curate_wowhead.py`). The page adds new dungeons whole and merges the rest into the built entry: loot goes to the same boss, matched by name, by each name of an "A & B" encounter, or by a spelling a letter or two off. Wings (Scarlet Monastery, Stratholme, Dire Maul, Blackrock Spire) are pasted one at a time into one entry, each boss tagged `wing`. `dungeon-guides-forever.json` (`tools/data-build/build_mspaint_guides.py`) holds MSPaintWoW's facts only: pull order, difficulty, drop chances, best-in-slot marks by spec, quest rewards. Its guide text and maps are its own work: link to them, don't copy them. `dungeon-routes-forever.json` (`tools/data-build/build_fdr_routes.py`, from the Forever Dungeon Routes add-on, MIT) holds standard routes drawn on the Wowhead floor images in 0-100 coordinates; floors whose Wowhead image is cropped differently are in the builder's `SKIP`. `dungeons-atlasloot-forever.json` (`tools/data-build/build_atlasloot_gaps.py`) holds only the boss loot from AtlasLoot Continued's Forever tables that no other source lists; AtlasLoot is GPL-2.0-only, so take facts from it, never code. `dungeons-att-forever.json` and `quests-att-forever.json` (`tools/data-build/build_att_forever.py`, from AllTheThings' `db/Camelot`, MIT) add the newest dungeons (bosses, no loot yet) and quests the main data lacks; quests carry `c` (class), `r` (race), `prof` (profession, filtered against the character's professions) and `p` (prerequisite quests). Every outside source and its refresh are in `tools/data-build/SOURCES.md`; `tools/data-build/refresh_sources.sh` re-checks them all. `talents-<class>.json` (`tools/data-build/build_talents.py`, Blizzard's talent trees for all nine classes; node ids are Blizzard's, so saved picks and plans survive rebuilds) and `talentplans-<class>.json` feed the Talents tab: your class's picks in `state/talents`, a build planned for another class in `state/talents-<class>`. `local-shim.js` gives the page the storage interface it was written against (`window.claude.use("db")`), backed by `/api/*` and live updates through Server-Sent Events.
- `app/scripts/`: Windows install and uninstall scripts, using NSSM and the Local Service account. They can't run in Linux sessions, so review PowerShell changes by hand and keep the files ASCII-only.
- `addon/LevelingLedger/`: the WoW Forever add-on (Interface 16001, SavedVariables `LevelingLedgerDB`).
  - Files: `LevelingLedger.lua` (core, panel, `/ledger`), `Shared.lua` (written by the app), `Alts.lua`, `Break.lua` (water breaks), `QuestLog.lua`, `QuestiePlan.lua`, `Auction.lua` (auction prices into `LevelingLedgerDB.ah`, merged by the hub into `shared/ahprices`), `RecipeVendors.lua` (recipes to buy, from `shared/recipeneeds` via `Shared.lua` `recipes`), `MrRobot.lua` (at logout copies Ask Mr. Robot Classic's imported gear setups, sell and keep lists from its saved table `AskMrRobotDb5` into `chars[...].amr`; read-only, its add-on has no license, so never copy its code; imported to `state/amr`), `CollectionsData.lua` (generated by `tools/data-build/build_library_books.py`) and `Collections.lua` (Library Books: Questie map pins for books still needed, through Questie's internals like `QuestiePlan.lua`; `/ledger books`; at logout `chars[...].books` = handed in and in bags, imported to `state/books`; the page also takes ticks in `state/bookticks`; quest chains from `tools/data-build/quest-chains.json`: a Questie pin on your current step, `/ledger chains`, chain quests completed or in the log saved as `chars[...].chainq`, imported to `state/chainq`; secrets from `tools/data-build/secrets.json`: `?` Questie pins on the spots of the ones not done for your class, faction and level, `/ledger secrets`, done ones (quest, item by id or name, whole set, toy, pet) saved as `chars[...].secrets`, imported to `state/secrets`; ticks on the page go in `shared/secretticks` by first name and reach the add-on through `Shared.lua` `secrets`), the core also records the bag items in the bag slots, reagent slot and bank bag slots (`bagItems`, `bankBagItems`, shared through `shared/inventories` for the Bags section; `bags-forever.json` from `tools/data-build/build_bags.py`), `Talents.lua` (names the next talent from the plan picked on the Talents tab, `shared/talentplans` via `Shared.lua` `talents`, at level up and login; `/ledger talents`), `Bindings.xml` (the Save key).
  - Register events through `listen()` (`ns.listen`): an event the client doesn't have is an error that stops the rest of the file from loading.
  - The WoW Forever client runs on the newest engine: add-ons may not register `COMBAT_LOG_EVENT_UNFILTERED` (the game blocks them). Kills come from the kill-XP chat message.
  - `QuestiePlan.lua` uses Questie's internals (`QuestieLoader:ImportModule` QuestieDB/QuestieMap/QuestieQuest, `Questie.db.char.hidden`), which aren't a stable API: keep every call feature-checked and in pcall. Planned quests come from `shared/questplan` through `Shared.lua` (`plans`). `QuestLog.lua` uses only Questie's public API.
  - At `PLAYER_LOGOUT` the game often answers with nothing (no rested XP or zone, 0 gold, level 0, empty bags, no completed quests, no item names). Save state while playing, from events; at logout only keep or add to it (`read()` in `LevelingLedger.lua`, `save(true)` in `Collections.lua`), never overwrite with an empty answer.
  - Avoid taint: never assign Blizzard globals or add to `StaticPopupDialogs`; build the add-on's own frames instead. Taint makes the game blame the add-on for blocked actions.
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
