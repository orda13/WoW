# Usage: python3 -I build_gear.py <equipment.json> <out.json> : Talwyn's equipped gear in the ledger's compact item shape.
import json, sys, time
d = json.load(open(sys.argv[1]))
QUAL = {'POOR': 0, 'COMMON': 1, 'UNCOMMON': 2, 'RARE': 3, 'EPIC': 4, 'LEGENDARY': 5}
out = []
for it in d.get('equipped_items', []):
    o = {'slot': it['slot']['type'], 'sn': it['slot']['name'], 'id': it['item']['id'], 'n': it.get('name'), 'q': QUAL.get((it.get('quality') or {}).get('type'), 1),
         'il': (it.get('level') or {}).get('value', 0), 'sl': (it.get('inventory_type') or {}).get('name'), 'sc': (it.get('item_subclass') or {}).get('name')}
    if (it.get('armor') or {}).get('value'): o['ar'] = it['armor']['value']
    w = it.get('weapon')
    if w and w.get('damage'): o['w'] = [w['damage'].get('min_value', 0), w['damage'].get('max_value', 0), round((w.get('attack_speed') or {}).get('value', 0) / 1000, 2), round((w.get('dps') or {}).get('value', 0), 1)]
    st = [[s['type']['name'], s['value']] for s in it.get('stats', []) if 'type' in s]
    if st: o['st'] = st
    fx = [s.get('description') for s in it.get('spells', []) if s.get('description')]
    if fx: o['fx'] = fx
    if (it.get('durability') or {}).get('value') is not None: o['du'] = [it['durability'].get('value'), it['durability'].get('max_value')]
    out.append(o)
json.dump({'items': out, 'syncedAt': int(time.time() * 1000)}, open(sys.argv[2], 'w'))
print(len(out), 'items:', [(o['sn'], o['n'], o['il']) for o in out])
