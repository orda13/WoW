# Builds leveling/recipes-forever.json: every profession recipe item in Forever and where it comes from.
import json, glob, re, os, sys, collections
S = './work/'
sys.path.insert(0, S)
from luaparse import parse_data_string, parse_return_table
R = S + 'qdb/repo/'
items = parse_data_string(open(R + 'data/Forever/foreverItemDB.lua').read(), 'QuestieDB.itemData')
npcs = parse_data_string(open(R + 'data/Forever/foreverNpcDB.lua').read(), 'QuestieDB.npcData')
objs = parse_data_string(open(R + 'data/Forever/foreverObjectDB.lua').read(), 'QuestieDB.objectData')
quests = parse_data_string(open(R + 'data/Forever/foreverQuestDB.lua').read(), 'QuestieDB.questData')
di = parse_return_table(open(R + 'src/corrections/Forever/generated/foreverBaseItem.lua').read(), 'Load()')
dn = parse_return_table(open(R + 'src/corrections/Forever/generated/foreverBaseNpc.lua').read(), 'Load(')
# zone names
ztxt = open(R + 'src/corrections/enum/zones.lua').read()
ZN = {}; ZID = {}
for name, zid in re.findall(r'^\s*([A-Z0-9_]+)\s*=\s*(\d+),', ztxt, re.M):
    ZID[name] = int(zid)
    if int(zid) not in ZN: ZN[int(zid)] = name
FIX = {'UNGORO_CRATER': "Un'Goro Crater", 'ZUL_GURUB': "Zul'Gurub", 'ZUL_FARRAK': "Zul'Farrak", 'ONYXIAS_LAIR': "Onyxia's Lair",
       'AHN_QIRAJ': "Ahn'Qiraj", 'THE_TEMPLE_OF_ATAL_HAKKAR': "The Temple of Atal'Hakkar", 'ZUL_AMAN': "Zul'Aman", 'UN_GORO_CRATER': "Un'Goro Crater", 'RUINS_OF_AHN_QIRAJ': "Ruins of Ahn'Qiraj", 'BLACKROCK_DEPTHS_SHADOWFORGE_CITY': 'Blackrock Depths', 'BLACKROCK_DEPTHS': 'Blackrock Depths'}
def zname(z):
    n = ZN.get(z)
    if not n: return None
    return FIX.get(n) or n.replace('_', ' ').title().replace(' Of ', ' of ').replace(' The ', ' the ')
IK = {'name': 0, 'npcDrops': 1, 'objectDrops': 2, 'itemDrops': 3, 'questRewards': 5, 'vendors': 13}
NK = {'name': 0, 'minLevel': 3, 'maxLevel': 4, 'rank': 5, 'spawns': 6, 'zoneID': 8, 'friendlyToFaction': 12, 'subName': 13}
def apply(base, deltas, keys, prefix):
    for eid, d in deltas.items():
        row = list(base.get(eid) or [None] * 15)
        while len(row) < 15: row.append(None)
        for k, v in d.items():
            if not (isinstance(k, tuple) and k[0] == 'id'): continue
            f = k[1].split('.', 1)[1]
            add = f.endswith('_add'); f = f[:-4] if add else f
            if f not in keys: continue
            if isinstance(v, tuple) and v[0] == 'id' and v[1].startswith('zoneIDs.'): v = ZID.get(v[1].split('.')[1], 0)
            i = keys[f]
            if add and isinstance(v, list): row[i] = list(dict.fromkeys((row[i] or []) + v))
            else: row[i] = v
        base[eid] = row
apply(items, di, IK, 'itemKeys'); apply(npcs, dn, NK, 'npcKeys')
def npc_info(nid):
    n = npcs.get(nid)
    if not n: return None
    z = n[8] if len(n) > 8 else None
    if not z and isinstance(n[6], dict) and n[6]: z = next(iter(n[6]))
    rank = {1: 'Elite', 2: 'Rare elite', 3: 'Boss', 4: 'Rare'}.get(n[5] or 0)
    lv = (n[3], n[4]) if n[3] else None
    o = {'n': n[0], 'id': nid}
    if lv: o['lv'] = lv[0] if lv[0] == lv[1] else [lv[0], lv[1]]
    zn = zname(z) if isinstance(z, int) else None
    if zn: o['z'] = zn
    sp = n[6] if isinstance(n[6], dict) else {}
    pts = sp.get(z) if isinstance(z, int) else None
    if isinstance(pts, list) and pts and isinstance(pts[0], list) and len(pts[0]) >= 2 and isinstance(pts[0][0], (int, float)) and pts[0][0] >= 0:
        o['xy'] = [round(pts[0][0], 1), round(pts[0][1], 1)]
    if rank: o['r'] = rank
    if len(n) > 13 and n[13]: o['t'] = n[13]
    if len(n) > 12 and n[12]: o['f'] = n[12]
    return o
# Blizzard recipe items
QUAL = {'POOR': 0, 'COMMON': 1, 'UNCOMMON': 2, 'RARE': 3, 'EPIC': 4, 'LEGENDARY': 5}
bq = json.load(open(S + 'leveling/quests-forever.json'))
bquest = {q['i']: (q['t'], z['z']) for z in bq['zones'] for q in z['q']}
out = []; stats = collections.Counter()
for f in glob.glob(S + 'rd/items/*.json'):
    d = json.load(open(f))
    if 'id' not in d: continue
    p = d.get('preview_item', {}); req = p.get('requirements') or {}
    prof = d['item_subclass']['name']
    e = {'i': d['id'], 'n': d['name'], 'p': prof, 'q': QUAL.get(d['quality']['type'], 1), 'price': d.get('purchase_price', 0)}
    sk = (req.get('skill') or {})
    if sk.get('level'): e['sk'] = sk['level']
    if (req.get('faction') or {}).get('value'): e['fac'] = req['faction']['value']['name']
    rc = p.get('recipe') or {}
    mk = (rc.get('item') or {})
    if mk.get('name'): e['mk'] = mk['name']; e['mq'] = QUAL.get((mk.get('quality') or {}).get('type'), 1)
    if mk:
        mi = {'cl': (mk.get('item_class') or {}).get('name'), 'sc': (mk.get('item_subclass') or {}).get('name')}
        inv = (mk.get('inventory_type') or {})
        if inv.get('type') and inv['type'] != 'NON_EQUIP': mi['sl'] = inv['name']
        if (mk.get('armor') or {}).get('value'): mi['ar'] = mk['armor']['value']
        w = mk.get('weapon')
        if w and w.get('damage'):
            mi['w'] = [w['damage'].get('min_value', 0), w['damage'].get('max_value', 0), round((w.get('attack_speed') or {}).get('value', 0) / 1000, 2), round((w.get('dps') or {}).get('value', 0), 1)]
        st = [[x['type']['name'], x['value']] for x in mk.get('stats', []) if 'type' in x]
        if st: mi['st'] = st
        fx = [x.get('description') for x in mk.get('spells', []) if x.get('description')]
        fx += [x['display']['display_string'] for x in mk.get('stats', []) if 'type' not in x and x.get('display')]
        if fx: mi['fx'] = fx
        if ((mk.get('requirements') or {}).get('level') or {}).get('value'): mi['rl'] = mk['requirements']['level']['value']
        if (mk.get('level') or {}).get('value'): mi['il'] = mk['level']['value']
        if (mk.get('binding') or {}).get('name'): mi['b'] = mk['binding']['name']
        if mk.get('is_stackable') or (mk.get('item_class') or {}).get('name') in ('Consumable', 'Trade Goods'): pass
        e['mi'] = {k: v for k, v in mi.items() if v is not None}
    elif p.get('spells'):
        fx = [re.sub(r'^Use: Teaches you how to ', '', x.get('description', '')).rstrip('.') for x in p['spells'] if x.get('description')]
        fx = [f[0].upper() + f[1:] for f in fx if f]
        if fx: e['fx'] = fx
    rg = [[x['reagent']['name'], x.get('quantity', 1)] for x in rc.get('reagents', []) if x.get('reagent')]
    if rg: e['rg'] = rg
    row = items.get(d['id'])
    src = []
    if row:
        vend = [npc_info(v) for v in (row[13] if len(row) > 13 and row[13] else [])]
        vend = [v for v in vend if v]
        if vend: e['v'] = vend[:12]; src.append('Vendor')
        drops = [npc_info(n) for n in (row[1] or [])]; drops = [x for x in drops if x]
        if drops:
            src.append('Drop')
            if len(drops) > 15:
                lvs = [x['lv'] if isinstance(x.get('lv'), int) else x.get('lv', [0, 0])[0] for x in drops if x.get('lv')]
                lvs2 = [x['lv'] if isinstance(x.get('lv'), int) else x.get('lv', [0, 0])[1] for x in drops if x.get('lv')]
                zc = collections.Counter(x.get('z') for x in drops if x.get('z'))
                e['wd'] = {'count': len(drops), 'lv': [min(lvs), max(lvs2)] if lvs else None, 'zones': [z for z, _ in zc.most_common(8)]}
            else: e['d'] = drops
        if row[2]:
            on = {}
            for o in row[2]:
                if o in objs and objs[o] and objs[o][0] and objs[o][0] not in on: on[objs[o][0]] = o
            if on: e['o'] = [[n, i] for n, i in list(on.items())[:8]]; src.append('Container')
        if row[3]:
            inn = [[items[x][0], x] for x in row[3] if x in items]
            if inn: e['in'] = inn[:8]; src.append('Container')
        qr = row[5] or []
        qs = []
        for qid in qr:
            if qid in bquest: qs.append([bquest[qid][0], bquest[qid][1], qid])
            elif qid in quests and quests[qid]: qs.append([quests[qid][0], None, qid])
        if qs: e['qs'] = qs; src.append('Quest')
    e['src'] = list(dict.fromkeys(src))
    stats[tuple(e['src']) if e['src'] else ('none',)] += 1
    out.append(e)
out.sort(key=lambda e: (e['p'], e.get('sk', 0), e['n']))
json.dump({'source': 'Recipe items: Blizzard Game Data API (static-forever-us). Vendors, drops, quests and containers: QuestieDB Forever data (Classic Era data plus Forever changes).',
           'fetched': '2026-11-06', 'recipes': out}, open(S + 'leveling/recipes-forever.json', 'w'), separators=(',', ':'), ensure_ascii=False)
print(len(out), 'recipes', os.path.getsize(S + 'leveling/recipes-forever.json'), 'bytes')
for k, v in stats.most_common(): print(v, k)
