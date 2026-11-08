# Builds app/public/dungeon-maps-forever.json: for each dungeon and raid in dungeons-forever.json, its map floors
# (Wowhead's map images, checked to exist) and the creatures inside it with level and rank, for the page's tank notes.
#   python3 -I build_dungeon_maps.py <QuestieDB checkout> <out json>
# QuestieDB has no positions inside instances (spawns there are {-1,-1}), so routes are drawn by you on the page.
import sys, os, re, json, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from luaparse import parse_data_string

QDB, OUT = sys.argv[1], sys.argv[2]
PUB = os.path.join(HERE, '..', '..', 'app', 'public')
dungeons = json.load(open(os.path.join(PUB, 'dungeons-forever.json')))['dungeons']

ids = {}
for line in open(os.path.join(QDB, 'src', 'corrections', 'enum', 'zones.lua'), encoding='utf-8'):
    m = re.match(r'\s*([A-Z0-9_]+)\s*=\s*(\d+),', line)
    if m: ids.setdefault(m.group(1), int(m.group(2)))
ALIAS = {'AHN_QIRAJ': 'AHN_QIRAJ_THE_FALLEN_KINGDOM', 'SUNKEN_TEMPLE': 'THE_TEMPLE_OF_ATAL_HAKKAR'}

def exists(url):
    try:
        req = urllib.request.Request(url, method='HEAD', headers={'User-Agent': 'leveling-ledger-build'})
        return urllib.request.urlopen(req, timeout=15).status == 200
    except Exception:
        return False

npcs = parse_data_string(open(os.path.join(QDB, 'data', 'Forever', 'foreverNpcDB.lua'), encoding='utf-8').read(), 'QuestieDB.npcData')
RANK = {0: 'normal', 1: 'elite', 2: 'rare elite', 3: 'boss', 4: 'rare'}
out = {}
for d in dungeons:
    key = d['key']
    zid = ids.get(ALIAS[key]) if key in ALIAS and ALIAS[key] in ids else ids.get(key)
    if not zid: print('no zone id for', key); continue
    group = {v for k, v in ids.items() if k == key or k.startswith(key + '_') or k == ALIAS.get(key)} | {zid}
    # map floors: Wowhead's maps by zone and floor
    floors = [f for f in range(0, 9) if exists(f'https://wow.zamimg.com/images/wow/maps/enus/original/{zid}-{f}.jpg')]
    classic = exists(f'https://wow.zamimg.com/images/wow/classic/maps/enus/original/{zid}.jpg')
    mobs = {}
    for nid, n in npcs.items():
        row = n if isinstance(n, list) else [n.get(i) for i in range(1, 16)]
        row = row + [None] * (15 - len(row))
        name, lo, hi, rank, spawns, zone, friendly = row[0], row[3] or 0, row[4] or 0, row[5] or 0, row[6], row[8], row[12]
        if not name or friendly or lo <= 0: continue
        zs = set(spawns.keys()) if isinstance(spawns, dict) else set()
        if zone: zs.add(zone)
        if not (zs & group): continue
        k = name
        m = mobs.get(k) or {'n': name, 'lv': [lo, hi], 'r': RANK.get(rank, 'normal'), 'ids': []}
        m['lv'] = [min(m['lv'][0], lo), max(m['lv'][1], hi)]; m['ids'].append(nid)
        mobs[k] = m
    out[key] = {'zid': zid, 'floors': floors, 'classic': classic, 'mobs': sorted(mobs.values(), key=lambda m: (m['lv'][0], m['n']))}
    print(f"{key:24} zone {zid:5}  floors {floors}  classic {classic}  creatures {len(mobs)}")

json.dump({'source': "Maps: Wowhead's images (checked to exist). Creatures, levels and ranks: QuestieDB's Forever data.",
           'fetched': '2026-11-08', 'dungeons': out}, open(OUT, 'w'), separators=(',', ':'), ensure_ascii=False)
print(os.path.getsize(OUT), 'bytes')
