# Where the WoW Forever data comes from, and how to refresh it

WoW Forever is new, and every source below keeps filling in as people play. To re-check them all at once:

```bash
bash tools/data-build/refresh_sources.sh [<unpacked AtlasLoot Continued folder>]
```

It fetches each source into a scratch folder, rebuilds the files below, and lists what changed in `app/public/`. Review the diff, then commit.

| Source | What we take | Built file | How it's refreshed |
|---|---|---|---|
| [QuestieDB](https://github.com/Questie/QuestieDB) (`data/Forever`, `support/Forever/Zones`; GPL-3.0) | creatures, levels and ranks inside dungeons (and the original quest, NPC and object data); dungeon and raid entrance positions | `dungeon-maps-forever.json`, the add-on's `EntranceData.lua` (`build_entrances.py`) (others from the older builders) | cloned by the script |
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

## Hotfixes
`refresh_blizzard_items.py` re-reads every item the page shows (quest rewards, dungeon loot, what recipes make) from Blizzard's Forever item data and prints each change, so a hotfix post can be checked against it. Blizzard's item data usually has a hotfix within days; its recipe reagents, talent and spell text can lag. Changes from a post that Blizzard hasn't published yet are patched into the JSON by hand (the next rebuild then takes Blizzard's version):
- 2026-11-12 (hotfixes of Nov 5-11): bag recipes' bolts (Green/Red Woolen Bag 5, Green Silk Pack 5, Black Silk Pack 6, Red Mageweave Bag 5) and the bag guide's slot counts (`bags.tsv`); Coarse Grinding Stone grey at 90 (green estimated at 70); Tanning Rack skill 125, skill-ups 15 lower; "Recipe: Elixir of Holy Power"; "Find Bingles" under Loch Modan; talent text for Mental Dexterity, Maelstrom Weapon, Stormstrike, Soul Siphon, Wrack and Nature's Swiftness; Arcane Shot and Summon Hawk at 11% of base Mana.
