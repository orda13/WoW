# Builds app/public/gathering-forever.json: every herb and mining node's spawn points per zone (map coordinates,
# 0-100), the gathering skill each needs, and zone names, for the page's gathering map and routes.
#   python3 -I build_gathering.py <QuestieDB checkout> <out json>
# Node spawns: QuestieDB's Forever object data (data/Forever/foreverObjectDB.lua), read with luaparse (never run).
# Which objects are nodes: app/public/materials-forever.json (its "nodes" lists). Skill needed: the original game's
# values (the client tables don't carry node locks); nodes not listed keep sk = null ("skill unknown").
import sys, os, re, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from luaparse import parse_data_string, P

QDB, OUT = sys.argv[1], sys.argv[2]
PUB = os.path.join(HERE, '..', '..', 'app', 'public')

SKILL = {
    # Herbalism
    'Peacebloom': 1, 'Silverleaf': 1, 'Earthroot': 15, 'Mageroyal': 50, 'Briarthorn': 70, 'Stranglekelp': 85,
    'Bruiseweed': 100, 'Wild Steelbloom': 115, 'Grave Moss': 120, 'Kingsblood': 125, 'Liferoot': 150, 'Fadeleaf': 160,
    'Goldthorn': 170, "Khadgar's Whisker": 185, 'Wintersbite': 195, 'Firebloom': 205, 'Purple Lotus': 210,
    "Arthas' Tears": 220, 'Sungrass': 230, 'Blindweed': 235, 'Ghost Mushroom': 245, 'Gromsblood': 250,
    'Golden Sansam': 260, 'Dreamfoil': 270, 'Mountain Silversage': 280, 'Plaguebloom': 285, 'Icecap': 290, 'Black Lotus': 300,
    # Mining
    'Copper Vein': 1, 'Tin Vein': 65, 'Incendicite Mineral Vein': 65, 'Silver Vein': 75, 'Ooze Covered Silver Vein': 75,
    'Lesser Bloodstone Deposit': 75, 'Iron Deposit': 125, 'Indurium Mineral Vein': 150, 'Gold Vein': 155,
    'Ooze Covered Gold Vein': 155, 'Mithril Deposit': 175, 'Ooze Covered Mithril Deposit': 175, 'Truesilver Deposit': 230,
    'Ooze Covered Truesilver Deposit': 230, 'Dark Iron Deposit': 230, 'Small Thorium Vein': 245,
    'Ooze Covered Thorium Vein': 245, 'Rich Thorium Vein': 275, 'Ooze Covered Rich Thorium Vein': 275,
}

# which objects are gathering nodes
mats = json.load(open(os.path.join(PUB, 'materials-forever.json')))['materials']
kinds = {}
for m in mats.values():
    for n, oid, zones, kind in m.get('nodes') or []:
        if kind in ('Herbalism', 'Mining'): kinds[oid] = (n, kind)

MINING = {k for k in SKILL if re.search(r'Vein|Deposit', k)}

# spawns
objects = parse_data_string(open(os.path.join(QDB, 'data', 'Forever', 'foreverObjectDB.lua'), encoding='utf-8').read(), 'QuestieDB.objectData')
# also any object named like a known node (some aren't in the materials file's node lists)
for oid, o in objects.items():
    nm = (o[0] if isinstance(o, list) else (o or {}).get(1)) if o else None
    if nm in SKILL and oid not in kinds: kinds[oid] = (nm, 'Mining' if nm in MINING else 'Herbalism')
nodes, used_zones = [], set()
for oid, (name, kind) in sorted(kinds.items()):
    o = objects.get(oid)
    if not o: continue
    row = o if isinstance(o, list) else [o.get(i) for i in range(1, 6)]
    spawns = row[3] if len(row) > 3 else None
    if not isinstance(spawns, dict): continue
    sp = {}
    for z, pts in spawns.items():
        pts = [[round(p[0], 1), round(p[1], 1)] for p in (pts or []) if isinstance(p, list) and len(p) == 2 and 0 <= p[0] <= 100 and 0 <= p[1] <= 100]
        if pts: sp[str(z)] = pts; used_zones.add(int(z))
    if sp: nodes.append({'id': oid, 'n': name, 'kind': kind, 'sk': SKILL.get(name), 'spawns': sp})

# zone names: QuestieDB's constants, matched to the names our quest data uses where possible
consts = {}
for line in open(os.path.join(QDB, 'src', 'corrections', 'enum', 'zones.lua'), encoding='utf-8'):
    m = re.match(r'\s*([A-Z0-9_]+)\s*=\s*(\d+),', line)
    if m: consts.setdefault(int(m.group(2)), m.group(1))
norm = lambda s: re.sub(r'[^a-z0-9]', '', s.lower())
known = {}
for z in json.load(open(os.path.join(PUB, 'quests-forever.json')))['zones']: known[norm(z['z'])] = z['z']
zones = {}
for zid in sorted(used_zones):
    c = consts.get(zid)
    if not c: continue
    zones[str(zid)] = known.get(norm(c)) or c.replace('_', ' ').title()

json.dump({'source': "QuestieDB's Forever object data (herb and mining node spawns); skill needed from the original game",
           'fetched': '2026-11-08', 'zones': zones, 'nodes': nodes}, open(OUT, 'w'), separators=(',', ':'), ensure_ascii=False)
print(len(nodes), 'nodes,', sum(len(p) for n in nodes for p in n['spawns'].values()), 'spawns,', len(zones), 'zones,',
      sum(1 for n in nodes if n['sk'] is None), 'without a skill:', [n['n'] for n in nodes if n['sk'] is None][:12], os.path.getsize(OUT), 'bytes')
