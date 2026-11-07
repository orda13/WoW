# Builds leveling/materials-forever.json: where to get every crafting reagent in Forever.
import json, glob, os, re, sys, collections
S = './work/'
sys.path.insert(0, S)
exec(open(S + 'build_recipes.py').read().split('# Blizzard recipe items')[0])  # reuse: items, npcs, objs, quests, deltas applied, zname, npc_info
QUAL = {'POOR': 0, 'COMMON': 1, 'UNCOMMON': 2, 'RARE': 3, 'EPIC': 4, 'LEGENDARY': 5}
CHEST = re.compile(r'chest|strongbox|crate|box\b|lockbox|footlocker|cache|treasure|coffer|barrel|sack|trunk|booty|supplies|gift|bundle|package', re.I)
# Skinning isn't in QuestieDB; level guidance from the original game
SKIN = {'Ruined Leather Scraps': '1–20', 'Light Leather': '1–20', 'Light Hide': '1–20', 'Medium Leather': '15–30', 'Medium Hide': '15–30',
        'Heavy Leather': '25–40', 'Heavy Hide': '25–40', 'Thick Leather': '35–50', 'Thick Hide': '35–50', 'Rugged Leather': '45–60', 'Rugged Hide': '45–60',
        'Devilsaur Leather': "Devilsaurs in Un'Goro Crater", 'Black Dragonscale': 'black dragonkin (Burning Steppes, Blackrock)',
        'Red Dragonscale': 'red dragonkin', 'Green Dragonscale': 'green dragonkin', 'Blue Dragonscale': 'blue dragonkin (Azshara, Winterspring)',
        'Worn Dragonscale': 'dragonkin', 'Scorpid Scale': 'scorpids', 'Turtle Scale': 'turtles', 'Thick Wolfhide': 'wolves', 'Warbear Leather': 'bears (Timbermaw)',
        'Chimera Leather': 'chimaeras', 'Frostsaber Leather': 'frostsabers (Winterspring)', 'Core Leather': 'Molten Core creatures', 'Primal Bat Leather': "bats (Zul'Gurub)", 'Primal Tiger Leather': "tigers (Zul'Gurub)"}
book = json.load(open(S + 'leveling/recipebook-forever.json'))['recipes']
crafted_by = collections.defaultdict(list)
for r in book:
    if r.get('ci') and not r.get('sod'): crafted_by[r['ci']].append([r['p'], r['n']])
used_by = collections.defaultdict(list)
reag_ids = {}
for f in glob.glob(S + 'pr/recipes/*.json'):
    d = json.load(open(f))
    for x in d.get('reagents', []):
        rg = x.get('reagent') or {}
        if rg.get('id'): reag_ids[rg['id']] = rg['name']
for r in book:
    if r.get('sod'): continue
    rec = json.load(open(S + f"pr/recipes/{r['id']}.json"))
    for x in rec.get('reagents', []):
        rg = x.get('reagent') or {}
        if rg.get('id'): used_by[rg['id']].append(r['id'])
def obj_zones(oid):
    o = objs.get(oid)
    if not o: return []
    zs = list((o[3] or {}).keys()) if isinstance(o[3], dict) else []
    if not zs and len(o) > 4 and isinstance(o[4], int): zs = [o[4]]
    return [zname(z) for z in zs if isinstance(z, int) and zname(z)]
out = {}
for iid, name in reag_ids.items():
    if iid not in used_by: continue
    e = {'n': name}
    try: d = json.load(open(S + f'pr/reag/{iid}.json'))
    except Exception: d = {}
    if 'id' in d:
        e['q'] = QUAL.get(d['quality']['type'], 1); e['t'] = d['item_subclass']['name']; e['c'] = d['item_class']['name']
        if d.get('purchase_price'): e['price'] = d['purchase_price']
    row = items.get(iid)
    how = []
    if row:
        v = [npc_info(x) for x in (row[13] if len(row) > 13 and row[13] else [])]; v = [x for x in v if x]
        if v: e['v'] = v[:10]; e['vn'] = len(v); how.append('Vendor')
        drops = [npc_info(x) for x in (row[1] or [])]; drops = [x for x in drops if x]
        if drops:
            how.append('Drop')
            if e.get('t') in ('Herb', 'Metal & Stone') and (row[2] or []): e['rare'] = 1
            if len(drops) > 12:
                lo = [x['lv'] if isinstance(x.get('lv'), int) else x['lv'][0] for x in drops if x.get('lv')]
                hi = [x['lv'] if isinstance(x.get('lv'), int) else x['lv'][1] for x in drops if x.get('lv')]
                zc = collections.Counter(x.get('z') for x in drops if x.get('z'))
                e['wd'] = {'count': len(drops), 'lv': [min(lo), max(hi)] if lo else None, 'zones': [z for z, _ in zc.most_common(8)]}
            else: e['d'] = drops
        nodes = collections.OrderedDict(); chests = []
        for oid in (row[2] or []):
            o = objs.get(oid)
            if not o or not o[0]: continue
            if CHEST.search(o[0]): chests.append([o[0], oid]); continue
            g = nodes.setdefault(o[0], {'id': oid, 'zones': collections.Counter()})
            g['zones'].update(obj_zones(oid))
        if nodes:
            def kind(n):
                l = n.lower()
                if re.search(r'school|pool|floating|wreckage|oily blackmouth|patch of elemental water', l): return 'Fishing'
                if re.search(r'vein|deposit|ooze covered|small thorium|rich thorium', l): return 'Mining'
                if e.get('t') == 'Herb': return 'Herbalism'
                return 'Gathering'
            e['nodes'] = [[n, g['id'], [z for z, _ in g['zones'].most_common(6)], kind(n)] for n, g in nodes.items()][:6]
            for x in e['nodes']: how.append(x[3])
        if chests:
            seen = {}; [seen.setdefault(n, i) for n, i in chests]
            e['chests'] = [[n, i] for n, i in list(seen.items())[:6]]; how.append('Container')
        inn = [[items[x][0], x] for x in (row[3] or []) if x in items]
        if inn: e['in'] = inn[:6]; how.append('Container')
    if name in SKIN or (e.get('t') == 'Leather' and re.search(r'leather|hide|scale', name, re.I) and iid not in crafted_by):
        e['skin'] = SKIN.get(name, ''); how.append('Skinning')
    if e.get('t') == 'Enchanting' and re.search(r'dust|essence|shard|crystal', name, re.I): e['de'] = 1; how.append('Disenchanting')
    if iid in crafted_by: e['cb'] = crafted_by[iid][:6]; how.append('Crafted')
    e['how'] = list(dict.fromkeys(how))
    e['u'] = used_by[iid]
    out[iid] = e
json.dump({'source': 'Reagents and recipes: Blizzard Game Data API (static-forever-us). Vendors, drops, gathering nodes and containers: QuestieDB Forever data. Skinning levels: original game.',
           'fetched': '2026-11-06', 'materials': out}, open(S + 'leveling/materials-forever.json', 'w'), separators=(',', ':'), ensure_ascii=False)
c = collections.Counter(h for e in out.values() for h in e['how'])
print(len(out), 'materials', os.path.getsize(S + 'leveling/materials-forever.json'), 'bytes', dict(c), 'no source:', sum(1 for e in out.values() if not e['how']))
for n in ('Peacebloom', 'Copper Ore', 'Linen Cloth', 'Light Leather', 'Strange Dust', 'Copper Bar', 'Deviate Fish', 'Bolt of Woolen Cloth'):
    x = next((v for v in out.values() if v['n'] == n), None)
    print(n, '->', x and {k: (v if k not in ('u', 'v', 'd') else (len(v) if isinstance(v, list) else v)) for k, v in x.items()})
