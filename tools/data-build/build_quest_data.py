# Builds leveling/quests-forever.json and leveling/items-forever.json from the Blizzard dumps in qd/.
import json, glob, collections, statistics, sys, os
sys.path.insert(0, '.')
from infer import fac
from zones_known import RANGES, CITIES
Q = {}
for f in glob.glob('qd/q/*.json'):
    d = json.load(open(f)); Q[d['id']] = d
zname = lambda q: q['area'] if isinstance(q['area'], str) else q['area'].get('name', '?')
rep = lambda q: bool(q.get('is_repeatable') or q.get('is_daily') or q.get('is_weekly'))

def prereqs(q):
    out = []
    def walk(c):
        if isinstance(c, dict):
            t = c.get('target')
            if isinstance(t, dict) and 'id' in t: out.append(t['id'])
            for v in c.values(): walk(v)
        elif isinstance(c, list):
            for v in c: walk(v)
    walk((q.get('requirements') or {}).get('quests'))
    return out
F = {i: fac(q) for i, q in Q.items()}; P = {i: prereqs(q) for i, q in Q.items()}
for _ in range(6):
    for i, ps in P.items():
        for p in ps:
            if p in F:
                if F[i] is None and F[p]: F[i] = F[p]
                elif F[p] is None and F[i]: F[p] = F[i]

# Zone level ranges: known original zones, else estimated from the zone's high-end quest XP.
xp_by_zone = collections.defaultdict(list)
for q in Q.values():
    x = (q.get('rewards') or {}).get('experience', 0)
    if x and not rep(q): xp_by_zone[zname(q)].append(x)
p90 = {z: statistics.quantiles(v, n=10)[-1] if len(v) >= 5 else max(v) for z, v in xp_by_zone.items()}
cal = sorted((p90[z], (a + b) / 2) for z, (a, b) in list(RANGES.items())[:45] if z in p90)
xs = [c[0] for c in cal]; ys = sorted(c[1] for c in cal)  # monotone: pair sorted XP with sorted levels
def est(x):
    if x <= xs[0]: return ys[0]
    if x >= xs[-1]: return ys[-1]
    for k in range(1, len(xs)):
        if x <= xs[k]:
            t = (x - xs[k-1]) / ((xs[k] - xs[k-1]) or 1); return ys[k-1] + t * (ys[k] - ys[k-1])
zone_lv = {}
for z in set(map(zname, Q.values())):
    if z in CITIES: continue
    if z in RANGES: zone_lv[z] = [RANGES[z][0], RANGES[z][1], 0]
    elif z in p90:
        m = round(est(p90[z])); zone_lv[z] = [max(1, m - 5), min(60, m + 5), 1]

# Chains: Blizzard prerequisite links, plus same-name quests in one zone (ordered by quest id).
groups = collections.defaultdict(list)
for i, q in Q.items():
    if not rep(q): groups[(zname(q), q['title'])].append(i)
chain_of = {}; cid = 0
for (z, t), ids in groups.items():
    if len(ids) > 1:
        cid += 1
        for n, i in enumerate(sorted(ids), 1): chain_of[i] = (cid, n, 's')
# prerequisite links in the same zone join or start chains
for i, ps in P.items():
    for p in ps:
        if p in Q and zname(Q[p]) == zname(Q[i]) and i not in chain_of:
            if p not in chain_of: cid += 1; chain_of[p] = (cid, 1, 'b')
            c = chain_of[p]; chain_of[i] = (c[0], c[1] + 1, 'b')

def item_ids(o, acc):
    if isinstance(o, dict):
        if isinstance(o.get('item'), dict) and 'id' in o['item']: acc.append(o['item']['id'])
        for v in o.values(): item_ids(v, acc)
    elif isinstance(o, list):
        for v in o: item_ids(v, acc)
    return acc

zones = collections.defaultdict(list); used_items = set()
for i, q in Q.items():
    r = q.get('requirements') or {}; rw = q.get('rewards') or {}
    it = {'i': i, 't': q['title'], 'x': rw.get('experience', 0)}
    if F[i]: it['f'] = F[i]
    if r.get('classes'): it['c'] = [c['name'] for c in r['classes']]
    if r.get('races'): it['r'] = [c['name'] for c in r['races']]
    if rep(q): it['rp'] = 1
    if P[i]: it['p'] = P[i]
    if i in chain_of: it['ch'] = list(chain_of[i])
    items = rw.get('items') or {}
    if isinstance(items, dict):
        ch = item_ids(items.get('choice_of', []), []); gv = item_ids({k: v for k, v in items.items() if k != 'choice_of'}, [])
    else: ch, gv = [], item_ids(items, [])
    if ch: it['ic'] = ch
    if gv: it['ig'] = gv
    used_items |= set(ch) | set(gv)
    if (rw.get('money') or {}).get('value'): it['m'] = rw['money']['value']
    if rw.get('reputations'): it['rep'] = [[x['reward']['name'], x['value']] for x in rw['reputations']]
    sp = rw.get('spell') or rw.get('trade_skill_spell')
    if isinstance(sp, dict) and sp.get('name'): it['sp'] = sp['name']
    zones[zname(q)].append(it)
out = [{'z': z, 'lv': zone_lv.get(z), 'q': sorted(v, key=lambda x: x['i'])} for z, v in sorted(zones.items())]
json.dump({'source': 'Blizzard Game Data API, static-forever-us quest areas and quests', 'fetched': '2026-11-06', 'zones': out},
          open('leveling/quests-forever.json', 'w'), separators=(',', ':'), ensure_ascii=False)

QL = {'POOR': 0, 'COMMON': 1, 'UNCOMMON': 2, 'RARE': 3, 'EPIC': 4, 'LEGENDARY': 5, 'ARTIFACT': 6, 'HEIRLOOM': 7}
items = {}
for i in used_items:
    try: d = json.load(open(f'qd/items/{i}.json'))
    except Exception: continue
    p = d.get('preview_item', {})
    o = {'n': d['name'], 'q': QL.get(d.get('quality', {}).get('type'), 1), 'il': d.get('level', 0), 'cl': d['item_class']['name'], 'sc': d['item_subclass']['name']}
    if d.get('required_level'): o['rl'] = d['required_level']
    if d.get('is_equippable'): o['sl'] = d['inventory_type']['name']
    if p.get('armor'): o['ar'] = p['armor'].get('value')
    st = [[s['type']['name'], s['value']] for s in p.get('stats', []) if 'type' in s]
    extra = [s['display']['display_string'] for s in p.get('stats', []) if 'type' not in s and s.get('display')]
    if st: o['st'] = st
    w = p.get('weapon')
    if w and w.get('damage'):
        o['w'] = [w['damage'].get('min_value', 0), w['damage'].get('max_value', 0),
                  round((w.get('attack_speed') or {}).get('value', 0) / 1000, 2), round((w.get('dps') or {}).get('value', 0), 1)]
    fx = [s.get('description') for s in p.get('spells', []) if s.get('description')] + extra
    if fx: o['fx'] = fx
    if p.get('binding'): o['b'] = p['binding']['name']
    items[i] = o
json.dump({'source': 'Blizzard Game Data API, static-forever-us items', 'fetched': '2026-11-06', 'items': items},
          open('leveling/items-forever.json', 'w'), separators=(',', ':'), ensure_ascii=False)
print('quests', os.path.getsize('leveling/quests-forever.json'), 'items', os.path.getsize('leveling/items-forever.json'), len(items), 'chains', cid)
print('estimated zones:', sorted((z, v[:2]) for z, v in zone_lv.items() if v[2])[:40])
