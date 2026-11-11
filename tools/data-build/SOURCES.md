# Where the WoW Forever data comes from, and how to refresh it

WoW Forever is new, and every source below keeps filling in as people play. To re-check them all at once:

```bash
bash tools/data-build/refresh_sources.sh [<unpacked AtlasLoot Continued folder>]
```

It fetches each source into a scratch folder, rebuilds the files below, and lists what changed in `app/public/`. Review the diff, then commit.

| Source | What we take | Built file | How it's refreshed |
|---|---|---|---|
| [QuestieDB](https://github.com/Questie/QuestieDB) (`data/Forever`) | creatures, levels and ranks inside dungeons (and the original quest, NPC and object data) | `dungeon-maps-forever.json` (others from the older builders) | cloned by the script |
| Blizzard Game Data API (`static-forever-us`) | quest titles, zones, XP and faction; items; every class's talent trees | used by `build_att_forever.py`, `build_talents.py` (`talents-<class>.json`) and the older builders | token from `oauth.battle.net` |
| Wowhead's image server | spell icons (names from its Forever tooltips) and the classic talent tree backgrounds, shown straight from there | `build_talents.py` records icon names and background ids only | nothing to refresh |
| [Forever Dungeon Routes](https://github.com/Checkov23/ForeverDungeonRoutes) (MIT) | standard routes, boss stops, map notes; boss names by encounter | `dungeon-routes-forever.json` | cloned by the script |
| [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings) (MIT; `db/Camelot`) | the newest dungeons' bosses and quests; quests the main data lacks (class, profession, new Forever quests) | `dungeons-att-forever.json`, `quests-att-forever.json` | cloned by the script (only `db/Camelot`) |
| Your Library Books list (`tools/data-build/library-books.tsv`) with AllTheThings | book locations, notes and videos (yours); each book's quest and item, the librarians and the 10, 20 and 25-book rewards (AllTheThings) | `collections-forever.json`, `addon/LevelingLedger/CollectionsData.lua` (`build_library_books.py`) | edit the list; the script reruns the join |
| Your quest-chain guides (`tools/data-build/quest-chains.json`), quest ids from AllTheThings | each faction's steps, spots and what to do (Cozy Sleeping Bag) | `collections-forever.json` `chains`, `CollectionsData.lua` (`build_library_books.py`) | edit the file; the script rebuilds |
| The bag guide you shared (`tools/data-build/bags.tsv`), item ids from QuestieDB and AllTheThings | every bag by kind, slots and source; starter-zone bag quests | `bags-forever.json` (`build_bags.py`) | edit the list; the script reruns the lookups |
| WoW Forever secrets (`tools/data-build/secrets.json`): news and guide sites (Icy Veins, Warcraft Tavern, Method, Mobalytics, the WoW Secret Finding Discord's findings), ids and spots from AllTheThings | each secret, how to get it, its spots, and how the game shows it's done | `collections-forever.json` `secrets`, `CollectionsData.lua` (`build_library_books.py`) | edit the file as new secrets are found; the script rebuilds |
| [MSPaintWoW](https://www.mspaintwow.com/wow-forever/dungeons) | pull order, difficulty, drop chances, best-in-slot marks, quest rewards | `dungeon-guides-forever.json` | read from its site (robots.txt allows it) |
| [AtlasLoot Continued](https://www.curseforge.com/wow/addons/atlasloot-continued) (GPL-2.0) | boss loot no other source lists | `dungeons-atlasloot-forever.json` | not on GitHub: download the zip and pass its folder |
| Wowhead's Forever dungeon journal | bosses and drops | `dungeons-curated-forever.json` | paste a dungeon's page into a session; `curate_wowhead.py` (Wowhead's pages can't be fetched automatically) |
| Ask Mr. Robot | your own gear setups | (from the add-on, per character) | nothing to refresh |

Facts only from every source (IDs, levels, coordinates, names, which boss drops what); no code, guide text or map pictures. Credits are in the README.
