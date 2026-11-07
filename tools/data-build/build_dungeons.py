# Builds leveling/dungeons-forever.json from the boss lists, QuestieDB Forever creatures/drops, Blizzard items and quest data.
import json, glob, os, re, sys, collections
S = './work/'
sys.path.insert(0, S)
src = open(S + 'build_dungeons_a.py').read().split('# --- inspect bosses')[0]
exec(src)  # inst, inst_npcs, loot, npcs, items, zname ...
from dungeon_list import DUNGEONS, FOREVER_AREAS
QUAL = {'POOR': 0, 'COMMON': 1, 'UNCOMMON': 2, 'RARE': 3, 'EPIC': 4, 'LEGENDARY': 5}
def compact(d):
    p = d.get('preview_item', {})
    o = {'n': d['name'], 'q': QUAL.get(d['quality']['type'], 1), 'il': d.get('level', 0), 'cl': d['item_class']['name'], 'sc': d['item_subclass']['name']}
    if d.get('is_equippable'): o['sl'] = d['inventory_type']['name']
    if (p.get('armor') or {}).get('value'): o['ar'] = p['armor']['value']
    w = p.get('weapon')
    if w and w.get('damage'): o['w'] = [w['damage'].get('min_value', 0), w['damage'].get('max_value', 0), round((w.get('attack_speed') or {}).get('value', 0) / 1000, 2), round((w.get('dps') or {}).get('value', 0), 1)]
    st = [[s['type']['name'], s['value']] for s in p.get('stats', []) if 'type' in s]
    if st: o['st'] = st
    fx = [s.get('description') for s in p.get('spells', []) if s.get('description')] + [s['display']['display_string'] for s in p.get('stats', []) if 'type' not in s and s.get('display')]
    if fx: o['fx'] = fx
    rl = ((p.get('requirements') or {}).get('level') or {}).get('value') or d.get('required_level')
    if rl: o['rl'] = rl
    if p.get('binding'): o['b'] = p['binding']['name']
    return o
blizz = {}
for f in glob.glob(S + 'jd/items/*.json'):
    try: d = json.load(open(f))
    except Exception: continue
    if 'id' in d and 'quality' in d: blizz[d['id']] = d
norm = lambda s: re.sub(r'[^a-z0-9]', '', s.lower())
by_name = collections.defaultdict(list)
for nid, n in npcs.items():
    if n and n[0]: by_name[norm(n[0])].append(nid)
qz = {z['z']: z for z in json.load(open(S + 'leveling/quests-forever.json'))['zones']}
out_items = {}; out = []
def npc_entry(nid, name, rare):
    n = npcs.get(nid)
    e = {'n': name}
    if nid: e['id'] = nid
    if n:
        if n[3]: e['lv'] = n[3] if n[3] == n[4] else [n[3], n[4]]
        r = {1: 'Elite', 2: 'Rare elite', 3: 'Boss', 4: 'Rare'}.get(n[5] or 0)
        if r: e['r'] = r
    if rare: e['rare'] = 1
    return e
for dg in DUNGEONS:
    g = dg['key']; members = inst_npcs.get(g, set()); gl = loot.get(g, {})
    bosses = []; boss_ids = set()
    for b in dg['bosses']:
        rare = b.endswith('*'); name = b.rstrip('*')
        cands = by_name.get(norm(name), [])
        inside = [c for c in cands if c in members]
        nid = (inside or cands or [None])[0]
        e = npc_entry(nid, name, rare)
        drops = sorted({i for c in (inside or ([nid] if nid else [])) for i in gl.get(c, []) if i in blizz}, key=lambda i: (-QUAL.get(blizz[i]['quality']['type'], 1), blizz[i]['name']))
        if drops: e['loot'] = drops
        for i in drops: out_items[i] = compact(blizz[i])
        bosses.append(e); boss_ids.update(inside or ([nid] if nid else []))
    other = collections.defaultdict(list)
    for nid, its in gl.items():
        if nid in boss_ids: continue
        for i in its:
            if i in blizz and QUAL.get(blizz[i]['quality']['type'], 1) >= 2: other[i].append(npcs[nid][0])
    for i in other: out_items[i] = compact(blizz[i])
    all_ids = {i for v in gl.values() for i in v}
    gone = sum(1 for i in all_ids if i not in blizz)
    quest_zones = [z for z in dg['quests'] if z in qz]
    e = {k: dg[k] for k in ('key', 'n', 'kind', 'size', 'loc')}
    e['lv'] = list(dg['lv']); e['bosses'] = bosses; e['qz'] = quest_zones; e['gone'] = gone
    if dg.get('fac'): e['fac'] = dg['fac']
    if other: e['other'] = [[i, sorted(set(v))[:4]] for i, v in sorted(other.items(), key=lambda kv: (-QUAL.get(blizz[kv[0]]['quality']['type'], 1), blizz[kv[0]]['name']))][:40]
    out.append(e)
forever = []
for name, key in FOREVER_AREAS:
    e = {'n': name}
    if name in qz: e['qz'] = [name]; e['lv'] = qz[name]['lv']
    if key and key in inst_npcs:
        cr = [npc_entry(n, npcs[n][0], False) for n in inst_npcs[key] if (npcs[n][5] or 0) >= 1]
        cr.sort(key=lambda x: (-(x['lv'][1] if isinstance(x.get('lv'), list) else x.get('lv', 0) or 0), x['n']))
        if cr: e['creatures'] = cr[:15]
    if e.get('qz') or e.get('creatures'): forever.append(e)
json.dump({'source': 'Boss lists: original game. Creature levels and ranks, drops: QuestieDB Forever data. Items: Blizzard Game Data API (static-forever-us). Quests: Blizzard.',
           'fetched': '2026-11-06', 'dungeons': out, 'forever': forever, 'items': {str(k): v for k, v in out_items.items()}},
          open(S + 'leveling/dungeons-forever.json', 'w'), separators=(',', ':'), ensure_ascii=False)
print(os.path.getsize(S + 'leveling/dungeons-forever.json'), 'bytes; items', len(out_items))
for d in out:
    found = sum(1 for b in d['bosses'] if b.get('id')); lootn = sum(len(b.get('loot', [])) for b in d['bosses'])
    print(f"{d['n']:28} bosses {found}/{len(d['bosses'])} matched  boss loot {lootn:3}  other {len(d.get('other', [])):3}  gone {d['gone']:3}  quests {d['qz']}")
print('missing bosses:', [(d['n'], b['n']) for d in out for b in d['bosses'] if not b.get('id')])
print('forever areas:', [(f['n'], len(f.get('creatures', [])), f.get('qz')) for f in forever])
