# Builds app/public/dungeon-routes-forever.json from the Forever Dungeon Routes add-on
# (https://github.com/Checkov23/ForeverDungeonRoutes, MIT license, (c) 2026 Checkov23): its standard routes,
# boss stops and notes, placed on the Wowhead floor images the ledger page already shows.
#   python3 -I build_fdr_routes.py <ForeverDungeonRoutes checkout> [<out json>]
# Reads the add-on's Lua data with luaparse (nothing is run). Its routes are drawn on the game's dungeon maps
# (the same art Wowhead shows), as 0..1 positions on each floor; floors are the game's uiMapIDs, matched here to
# Wowhead's floor numbers. The four new dungeons use map pictures by Santiago Reyes that only the add-on may use,
# so their routes are left out.
import sys, os, re, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from luaparse import P
SRC = sys.argv[1]
PUB = os.path.join(HERE, '..', '..', 'app', 'public')
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(PUB, 'dungeon-routes-forever.json')
DATA = os.path.join(SRC, 'ForeverDungeonRoutes', 'Data')

def tables(path, pattern):
    s = open(path, encoding='utf-8').read()
    out = {}
    for m in re.finditer(pattern, s):
        p = P(s); p.i = m.end() - 1; out[m.group(1)] = p.val()
    return out

routes = tables(os.path.join(DATA, 'DefaultRoutes.lua'), r'DR\.DefaultRoutes\["([a-z_]+)"\]\s*=\s*\{')
dsrc = open(os.path.join(DATA, 'Dungeons.lua'), encoding='utf-8').read()
p = P(dsrc); p.i = dsrc.index('DR.Dungeons = {') + len('DR.Dungeons = '); fdr = p.val()

# their dungeon -> ours (wings of one dungeon share our entry)
OURS = {'ragefire': 'RAGEFIRE_CHASM', 'deadmines': 'THE_DEADMINES', 'wailingcaverns': 'WAILING_CAVERNS', 'shadowfang': 'SHADOWFANG_KEEP',
        'blackfathom': 'BLACKFATHOM_DEEPS', 'stockade': 'THE_STOCKADE', 'razorfenkraul': 'RAZORFEN_KRAUL', 'gnomeregan': 'GNOMEREGAN',
        'sm_graveyard': 'SCARLET_MONASTERY', 'sm_library': 'SCARLET_MONASTERY', 'sm_armory': 'SCARLET_MONASTERY', 'sm_cathedral': 'SCARLET_MONASTERY',
        'razorfendowns': 'RAZORFEN_DOWNS', 'uldaman': 'ULDAMAN', 'zulfarrak': 'ZUL_FARRAK', 'maraudon': 'MARAUDON', 'sunkentemple': 'SUNKEN_TEMPLE',
        'blackrockdepths': 'BLACKROCK_DEPTHS', 'diremaul_east': 'DIRE_MAUL', 'diremaul_west': 'DIRE_MAUL', 'diremaul_north': 'DIRE_MAUL',
        'lowerblackrock': 'BLACKROCK_SPIRE', 'upperblackrock': 'BLACKROCK_SPIRE', 'scholomance': 'SCHOLOMANCE', 'stratholme': 'STRATHOLME',
        'moltencore': 'MOLTEN_CORE', 'onyxia': 'ONYXIAS_LAIR', 'blackwinglair': 'BLACKWING_LAIR', 'zulgurub': 'ZUL_GURUB',
        'ruinsofahnqiraj': 'RUINS_OF_AHN_QIRAJ', 'templeofahnqiraj': 'AHN_QIRAJ', 'naxxramas': 'NAXXRAMAS'}
WING = {'sm_graveyard': 'Graveyard', 'sm_library': 'Library', 'sm_armory': 'Armory', 'sm_cathedral': 'Cathedral',
        'diremaul_east': 'East', 'diremaul_west': 'West', 'diremaul_north': 'North', 'lowerblackrock': 'Lower', 'upperblackrock': 'Upper'}
maps = json.load(open(os.path.join(PUB, 'dungeon-maps-forever.json')))['dungeons']

# the game's floors (uiMapIDs) of each of our dungeons, in order, against Wowhead's floor numbers in order;
# Wowhead's floor 0 is the old one-floor map when it has more floors than the game
floor_of = {}
for key in sorted(set(OURS.values())):
    ui = sorted({f for d in fdr if OURS.get(d['key']) == key for f in d['floors'] if f < 1000000})
    wh = list(maps.get(key, {}).get('floors') or [])
    if len(wh) > len(ui) and wh and wh[0] == 0: wh = wh[1:]
    if len(wh) < len(ui): print(f'{key}: game floors {ui} vs Wowhead floors {wh}: skipped'); continue
    for u, w in zip(ui, wh): floor_of[u] = (key, w)

# floors whose Wowhead image is cropped differently from the game's map, so the route doesn't fit it (checked by drawing
# every route on every floor): Dire Maul West, Scholomance's two middle floors, Lower Blackrock Spire's first floor
SKIP = {236, 237, 238, 307, 308, 250}
for u in SKIP: floor_of.pop(u, None)

pct = lambda v: round(v * 100, 2)
out = {}
for fk, rs in routes.items():
    key = OURS.get(fk)
    if not key: continue                      # the new dungeons: map pictures we can't use
    for r in (rs if isinstance(rs, list) else [rs]):
        name = ' · '.join(x for x in (WING.get(fk), r.get('name')) if x) or 'Standard route'
        floors = {}
        def fl(u):
            k = floor_of.get(u)
            return floors.setdefault(str(k[1]), {'paths': [], 'stops': [], 'notes': []}) if k and k[0] == key else None
        for path in r.get('paths') or []:
            f = fl(path['floor'])
            if f is None: continue
            pts = path['pts']
            e = {'kind': path.get('kind', 'main'), 'pts': [[pct(pts[i]), pct(pts[i + 1])] for i in range(0, len(pts) - 1, 2)]}
            if path.get('title'): e['title'] = path['title']
            f['paths'].append(e)
        for st in r.get('stops') or []:
            f = fl(st['floor'])
            if f is None: continue
            e = {'kind': st.get('kind', 'boss'), 'n': st.get('name'), 'x': pct(st['x']), 'y': pct(st['y'])}
            if st.get('note'): e['note'] = st['note']
            f['stops'].append(e)
        for nt in r.get('notes') or []:
            f = fl(nt['floor'])
            if f is not None and nt.get('text'): f['notes'].append({'x': pct(nt['x']), 'y': pct(nt['y']), 'text': nt['text']})
        floors = {k: v for k, v in floors.items() if v['paths'] or v['stops']}
        if floors: out.setdefault(key, {'routes': []})['routes'].append({'name': name, 'floors': floors})
for k, v in sorted(out.items()):
    print(f"{k:22}", ' | '.join(f"{r['name']}: floors {sorted(r['floors'])}, {sum(len(f['stops']) for f in r['floors'].values())} stops" for r in v['routes']))
json.dump({'source': "Forever Dungeon Routes by Checkov23 (MIT license): standard routes, boss stops and notes. "
           "Its routes were traced from aetherflask.com's dungeon walkthrough maps (mirrored at eintr.net).",
           'dungeons': out}, open(OUT, 'w'), separators=(',', ':'), ensure_ascii=False)
print(os.path.getsize(OUT), 'bytes')
