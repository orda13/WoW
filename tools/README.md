# Tools

## `addon-simulate.py`

Runs the add-on (`addon/LevelingLedger/LevelingLedger.lua`) against a fake WoW API, using the `lupa` Lua runtime, and writes a sample SavedVariables file. Use it to check add-on changes without starting the game.

```bash
pip install lupa
python tools/addon-simulate.py
```

## `data-build/`

These scripts produced the game data in `app/public/*.json`. They were written while exploring sources for Forever, so treat them as a record of how the data was made, not a polished pipeline. Run them from inside a `work` folder, which holds their downloads and outputs:

```bash
cd tools/data-build
mkdir -p work
```

Sources they read (download into `work/` first):
- **QuestieDB** (github.com/Questie/QuestieDB): quests, NPCs, objects and items for Forever, including the `foreverBase*` corrections. The scripts parse the Lua data with `luaparse.py` and run none of it.
- **wago.tools DB2 CSVs** for the Forever build (product `wowf`): spells, skill lines, item sets, currencies, mounts, pets and toys.
- **Wowhead tooltips** (`nether.wowhead.com/tooltip/...?dataEnv=16`): ability and item details, fetched only for IDs already known, about one request per second.
- **The Blizzard Game Data API**: static Forever data.

Rebuild order for recipes:

```
build_recipes → build_book → add_skillups → wh_merge → build_mats
```

Other builders: `build_quest_data.py`, `build_questinfo.py`, `build_dungeons*.py`, `build_abilities.py`, `wh_spells.py`, `build_sets.py`, `build_gear.py` and `build_collect.py`.
