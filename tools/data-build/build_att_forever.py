# Builds two files from AllTheThings' WoW Forever database (db/Camelot; MIT license, (c) 2026 AllTheThings WoW Addon):
#   app/public/dungeons-att-forever.json  the newest Forever dungeons: level, bosses in order, quest zone (no loot published yet)
#   app/public/quests-att-forever.json    Forever quests our quest data doesn't have, with quest givers and where they stand
#   BLIZZARD_TOKEN=... python3 -I build_att_forever.py <AllTheThings folder> <ForeverDungeonRoutes checkout>
# Facts only: IDs, levels, coordinates, which boss is in which dungeon, quest givers and chains. The database is read as text
# (it's Lua that calls the add-on's own functions; nothing is run). Names the game fills in at runtime come from elsewhere:
# boss names from Forever Dungeon Routes' encounter list, quest titles, zones, XP and faction from Blizzard's Forever quest
# data (a quest Blizzard doesn't have is left out), quest-giver names from Wowhead's Forever tooltips.
import sys, os, re, json, time, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from luaparse import P
ATT, FDR = sys.argv[1], sys.argv[2]
PUB = os.path.join(HERE, '..', '..', 'app', 'public')
TOKEN = os.environ.get('BLIZZARD_TOKEN')
CAT = os.path.join(ATT, 'db', 'Camelot', 'Categories')

# the game's zone maps (uiMapID) -> zone name, as on Classic
UIMAP = dict(zip(range(1411, 1459), ["Durotar", "Mulgore", "The Barrens", "Kalimdor", "Eastern Kingdoms", "Alterac Mountains", "Arathi Highlands",
  "Badlands", "Blasted Lands", "Tirisfal Glades", "Silverpine Forest", "Western Plaguelands", "Eastern Plaguelands", "Hillsbrad Foothills",
  "The Hinterlands", "Dun Morogh", "Searing Gorge", "Burning Steppes", "Elwynn Forest", "Deadwind Pass", "Duskwood", "Loch Modan",
  "Redridge Mountains", "Stranglethorn Vale", "Swamp of Sorrows", "Westfall", "Wetlands", "Teldrassil", "Darkshore", "Ashenvale",
  "Thousand Needles", "Stonetalon Mountains", "Desolace", "Feralas", "Dustwallow Marsh", "Tanaris", "Azshara", "Felwood", "Un'Goro Crater",
  "Moonglade", "Silithus", "Winterspring", "Stormwind City", "Orgrimmar", "Ironforge", "Thunder Bluff", "Darnassus", "Undercity"]))

def read(f): return open(os.path.join(CAT, f), encoding='utf-8-sig').read()
def table_at(s, i):
    """the text of the {...} table that starts at s[i] == '{'"""
    d, q = 0, None
    for j in range(i, len(s)):
        c = s[j]
        if q:
            if c == '\\': continue
            if c == q: q = None
        elif c in '"\'': q = c
        elif c == '{': d += 1
        elif c == '}':
            d -= 1
            if d == 0: return s[i:j + 1]
    return s[i:]
def fields(t):
    """top-level key=value pairs of a table text (values as raw text)"""
    out, d, k, start, q = {}, 0, None, None, None
    i = 1
    while i < len(t) - 1:
        c = t[i]
        if q:
            if c == q: q = None
        elif c in '"\'': q = c
        elif c in '{(': d += 1
        elif c in '})': d -= 1
        elif d == 0:
            m = re.match(r'([A-Za-z_]\w*)=', t[i:])
            if m and (i == 1 or t[i - 1] in ',{'):
                if k: out[k] = t[start:i - 1]
                k, start = m.group(1), i + m.end(); i += m.end(); continue
        i += 1
    if k: out[k] = t[start:len(t) - 1]
    return out
nums = lambda v: [float(x) for x in re.findall(r'-?\d+(?:\.\d+)?', v or '')]
def map_ids(v): return [int(x) for x in re.findall(r'\[(\d+)\]=\{', v or '')]
def coords(v):
    """coords={[mapID]={{x,y},...}} -> [(zone, x, y)]"""
    out = []
    for m in re.finditer(r'\[(\d+)\]=\{((?:\{[^{}]*\},?)*)\}', v or ''):
        for xy in re.findall(r'\{(-?[\d.]+),(-?[\d.]+)\}', m.group(2)):
            out.append((UIMAP.get(int(m.group(1)), ''), float(xy[0]), float(xy[1])))
    return out

def get(url, headers=None):
    try: return json.loads(urllib.request.urlopen(urllib.request.Request(url, headers=headers or {'User-Agent': 'leveling-ledger-build'}), timeout=30).read())
    except Exception: return None
_npc = {}
def npc_name(i):
    if i not in _npc:
        d = get(f'https://nether.wowhead.com/forever/tooltip/npc/{i}'); time.sleep(0.15)
        _npc[i] = (d or {}).get('name') or ''
    return _npc[i]
def blizz_quest(i):
    if not TOKEN: return None
    d = get(f'https://us.api.blizzard.com/data/wow/quest/{i}?namespace=static-forever-us&locale=en_US', {'Authorization': 'Bearer ' + TOKEN}); time.sleep(0.08)
    return d if d and d.get('title') else None

# ---------- the newest dungeons ----------
enc_src = open(os.path.join(FDR, 'ForeverDungeonRoutes', 'Data', 'Encounters.lua'), encoding='utf-8').read()
p = P(enc_src); p.i = enc_src.index('DR.Encounters = {') + len('DR.Encounters = '); fdr_enc = p.val()
enc_name = {}
for lst in (fdr_enc.values() if isinstance(fdr_enc, dict) else []):
    for e in (lst or []):
        for x in (e.get('ids') or []): enc_name[x] = e.get('name')
dsrc = open(os.path.join(FDR, 'ForeverDungeonRoutes', 'Data', 'Dungeons.lua'), encoding='utf-8').read()
p = P(dsrc); p.i = dsrc.index('DR.Dungeons = {') + len('DR.Dungeons = '); fdr_d = {d['instanceID']: d for d in p.val()}

known = {re.sub(r'[^a-z0-9]', '', re.sub(r'^the ', '', d['n'].lower())) for f in ('dungeons-forever.json', 'dungeons-curated-forever.json')
         for d in json.load(open(os.path.join(PUB, f)))['dungeons']}
inst_src = read('Instances.lua')
dungeons, inst_quests = [], {}
for m in re.finditer(r'\binst\((\d+),\{', inst_src):
    iid = int(m.group(1)); t = table_at(inst_src, m.end() - 1); top = fields(t)
    if 'awp=16001' not in t[:200]: continue
    fd = fdr_d.get(iid); name = fd and fd.get('name')
    if not name: continue
    key = re.sub(r'[^a-z0-9]', '', re.sub(r'^the ', '', name.lower()))
    inst_quests[iid] = name
    if key in known: continue                     # a dungeon the page already has bosses for
    bosses = []
    for e in re.finditer(r'\be\((\d+),\{', t):
        f = fields(table_at(t, e.end() - 1)); eid = int(e.group(1))
        npc = int(nums(f.get('npcID'))[0]) if f.get('npcID') else (int(nums(f.get('crs'))[0]) if f.get('crs') else None)
        n = enc_name.get(eid) or (npc and npc_name(npc)) or f'Boss {eid}'
        bosses.append({'n': n, 'loot': [], **({'npcid': npc} if npc else {})})
    lv = fd.get('levels') or ([int(nums(top.get('lvl'))[0])] * 2 if top.get('lvl') else [0, 0])
    dungeons.append({'key': re.sub(r'[^A-Z0-9]+', '_', name.upper()).strip('_'), 'n': name, 'kind': 'Dungeon', 'size': 5, 'loc': '',
                     'lv': list(lv)[:2], 'bosses': bosses, 'other': [], 'qz': [name],
                     'curated': "AllTheThings' Forever database"})
    print(f"dungeon {name}: level {lv}, {len(bosses)} bosses: {', '.join(b['n'] for b in bosses)}")

# ---------- quests our data doesn't have ----------
CLASS = {1: 'Warrior', 2: 'Paladin', 3: 'Hunter', 4: 'Rogue', 5: 'Priest', 7: 'Shaman', 8: 'Mage', 9: 'Warlock', 11: 'Druid'}
PROF = {164: 'Blacksmithing', 165: 'Leatherworking', 171: 'Alchemy', 182: 'Herbalism', 186: 'Mining', 197: 'Tailoring', 202: 'Engineering',
        333: 'Enchanting', 356: 'Fishing', 393: 'Skinning', 129: 'First Aid', 185: 'Cooking'}
RACE = {1: 'Human', 2: 'Orc', 3: 'Dwarf', 4: 'Night Elf', 5: 'Undead', 6: 'Tauren', 7: 'Gnome', 8: 'Troll'}
def class_context(src):
    """quest id -> class id of the class section (cl(...)) it sits in"""
    out, stack = {}, []
    for m in re.finditer(r'([A-Za-z_]+)\((-?\d+)|[()]', src):
        if m.group(1):
            stack.append((m.group(1), int(m.group(2))))
            if m.group(1) == 'q':
                cls = [i for f, i in stack[:-1] if f == 'cl']
                if cls: out.setdefault(int(m.group(2)), cls[-1])
                maps = [i for f, i in stack[:-1] if f == 'm' and i in UIMAP]
                if maps: zone_of.setdefault(int(m.group(2)), UIMAP[maps[-1]])
        elif m.group(0) == '(': stack.append(('(', 0))
        elif stack: stack.pop()
    return out
zone_have = {q['i']: z['z'] for z in json.load(open(os.path.join(PUB, 'quests-forever.json')))['zones'] for q in z['q']}
have = set(zone_have)
found = {}
ctx, zone_of, votes0 = {}, {}, {}
for f, src in (('Zones.lua', read('Zones.lua')), ('Instances.lua', inst_src)):
    ctx.update(class_context(src))
    for m in re.finditer(r'\bq\((\d+),\{', src):
        qid = int(m.group(1))
        if qid in found: continue
        top = fields(table_at(src, m.end() - 1))
        if qid in have:
            # a quest we already place: what its map id is called, for new Forever zones
            mids = map_ids(top.get('coords'))
            if mids and zone_have[qid]: votes0.setdefault(mids[0], {}).setdefault(zone_have[qid], 0); votes0[mids[0]][zone_have[qid]] += 1
            continue
        if 'u' in top: continue                                       # marked unobtainable
        found[qid] = top
print(len(found), 'quests in AllTheThings that our quest data lacks; asking Blizzard which exist in Forever...')
zones, pending, votes = {}, [], votes0
for qid, top in sorted(found.items()):
    b = blizz_quest(qid)
    if not b: continue
    area = (b.get('area') or {}).get('name') or ''
    fac = ((b.get('requirements') or {}).get('faction') or {}).get('type')
    q = {'i': qid, 't': b['title'], 'x': ((b.get('rewards') or {}).get('experience')) or 0, 'src': 'att'}
    if fac: q['f'] = 'A' if fac == 'ALLIANCE' else 'H'
    elif top.get('r') in ('1', '2'): q['f'] = 'H' if top['r'] == '1' else 'A'
    cls = [CLASS[int(c)] for c in nums(top.get('c')) if int(c) in CLASS] or ([CLASS[ctx[qid]]] if ctx.get(qid) in CLASS else [])
    if cls: q['c'] = cls
    races = [RACE[int(r)] for r in nums(top.get('races')) if int(r) in RACE]
    if races and len(races) < 8: q['r'] = races
    lvl = nums(top.get('lvl'))
    if lvl: q['rl'] = int(lvl[0])
    givers = [int(x) for x in nums(top.get('qgs'))[:3]]
    pts = coords(top.get('coords'))
    if givers:
        q['qs'] = [["npc", g, npc_name(g), (pts[0][0] if pts else ''), *(list(pts[0][1:]) if pts else [])] for g in givers[:1]]
    elif pts: q['qs'] = [["npc", 0, '', pts[0][0], pts[0][1], pts[0][2]]]
    pre = [int(x) for x in nums(top.get('sourceQuests'))]
    if pre: q['p'] = pre                                              # prerequisite quests, as in the main quest data
    sk = nums(top.get('requireSkill'))
    if sk and int(sk[0]) in PROF: q['prof'] = PROF[int(sk[0])]
    if b.get('description'): q['ob'] = re.sub(r'\s+', ' ', b['description']).strip()[:300]
    # a new Forever zone has its own map id: learn its name from the quests on it that Blizzard does name
    mids = map_ids(top.get('coords'))
    if area and mids: votes.setdefault(mids[0], {}).setdefault(area, 0); votes[mids[0]][area] += 1
    z = area or (pts[0][0] if pts else '') or zone_of.get(qid)
    if z: zones.setdefault(z, []).append(q)
    else: pending.append((q, mids))
for q, mids in pending:
    v = votes.get(mids[0]) if mids else None
    z = max(v, key=v.get) if v else 'Unknown'
    if q.get('qs') and not q['qs'][0][3] and z != 'Unknown': q['qs'][0][3] = z
    zones.setdefault(z, []).append(q)
out_q = {'source': "Quests from AllTheThings' WoW Forever database that the main quest data lacks: titles, zones, XP and faction from "
         "Blizzard's Forever quest data, quest givers from Wowhead's Forever tooltips.", 'fetched': time.strftime('%Y-%m-%d'),
         'zones': [{'z': z, 'lv': None, 'q': qs} for z, qs in sorted(zones.items()) if z != 'Unknown']}
json.dump(out_q, open(os.path.join(PUB, 'quests-att-forever.json'), 'w'), separators=(',', ':'), ensure_ascii=False)
print(sum(len(z['q']) for z in out_q['zones']), 'quests added, in', len(out_q['zones']), 'zones')
json.dump({'source': "AllTheThings' WoW Forever database (MIT): the newest dungeons' bosses and quests. Boss names: Forever Dungeon Routes.",
           'dungeons': dungeons, 'items': {}}, open(os.path.join(PUB, 'dungeons-att-forever.json'), 'w'), indent=1, ensure_ascii=False)
