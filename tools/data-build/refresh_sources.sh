#!/usr/bin/env bash
# Re-checks the outside sources for WoW Forever data and rebuilds the files built from them, then lists what changed.
#   bash tools/data-build/refresh_sources.sh [<AtlasLoot Continued folder>]
# Sources (see tools/data-build/SOURCES.md): QuestieDB, Forever Dungeon Routes and AllTheThings from GitHub,
# MSPaintWoW's site, Blizzard's Forever API (the token comes from oauth.battle.net; the environment supplies the client).
# AtlasLoot Continued isn't on GitHub: pass its unpacked folder to include it. Wowhead's dungeon journal is pasted by hand.
# Downloaded sources go in a scratch folder and are only read (python -I, luaparse); nothing from them is run.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
B="$ROOT/tools/data-build"
W="${LL_SCRATCH:-$(mktemp -d)}"
AL="${1:-}"
echo "Working in $W"

fetch() { # url dir [sparse path]
  rm -rf "$2"
  if [ -n "${3:-}" ]; then
    git clone -q --depth 1 --filter=blob:none --sparse "$1" "$2" && git -C "$2" sparse-checkout set "$3"
  else git clone -q --depth 1 "$1" "$2"; fi
  echo "  $(basename "$2"): $(git -C "$2" log -1 --format='%h %cd' --date=short)"
}
echo "Fetching sources:"
fetch https://github.com/Questie/QuestieDB "$W/questiedb"
fetch https://github.com/Checkov23/ForeverDungeonRoutes "$W/fdr"
fetch https://github.com/ATTWoWAddon/AllTheThings "$W/att" db/Camelot

# Blizzard token (never printed)
TOKEN="$(curl -sS -X POST https://oauth.battle.net/token -d grant_type=client_credentials | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))' || true)"
[ -n "$TOKEN" ] || echo "  (no Blizzard token: quests Blizzard confirms are skipped)"
export BLIZZARD_TOKEN="$TOKEN"

echo "Rebuilding:"
cd "$ROOT"
python3 -I "$B/build_dungeon_maps.py" "$W/questiedb" app/public/dungeon-maps-forever.json | tail -1
python3 -I "$B/build_mspaint_guides.py" | tail -1
python3 -I "$B/build_fdr_routes.py" "$W/fdr" | tail -1
python3 -I "$B/build_att_forever.py" "$W/att" "$W/fdr" | tail -2
python3 -I "$B/build_library_books.py" "$W/att" | tail -1
if [ -n "$TOKEN" ]; then python3 -I "$B/build_talents.py" | tail -1; else echo "  talents skipped (no Blizzard token)"; fi
if [ -n "$AL" ]; then python3 -I "$B/build_atlasloot_gaps.py" "$AL" | tail -1; else echo "  AtlasLoot skipped (no folder given)"; fi

echo; echo "What changed:"
git -C "$ROOT" status --short -- app/public || true
git -C "$ROOT" diff --stat -- app/public || true
