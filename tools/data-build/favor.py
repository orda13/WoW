import json, sys, re, collections
S = './work/'
sys.path.insert(0, S)
exec(open(S + 'build_recipes.py').read().split('# Blizzard recipe items')[0])
cands = []
for nid, n in npcs.items():
    t = (n[13] if len(n) > 13 else None) or ''
    nm = n[0] or ''
    if re.search(r'commerce authority|supply and logistics|favor|logistics|commerce', t + ' ' + nm, re.I): cands.append((nid, nm, t, zname(n[8]) if len(n) > 8 and isinstance(n[8], int) else None, n[12] if len(n) > 12 else None))
print('NPC candidates:'); [print(' ', c) for c in cands]
ids = {c[0] for c in cands}
sold = collections.defaultdict(list)
for iid, row in items.items():
    v = (row[13] if row and len(row) > 13 else None) or []
    for x in v:
        if x in ids: sold[x].append((iid, row[0]))
for nid, its in sold.items(): print(nid, npcs[nid][0], len(its), [n for _, n in its][:60])
print('--- Forever-added NPCs with titles in Redridge / Barrens / Durotar')
for nid in sorted(dn):
    n = npcs.get(nid)
    if not n: continue
    z = zname(n[8]) if len(n) > 8 and isinstance(n[8], int) else None
    t = (n[13] if len(n) > 13 else None)
    if z in ('Redridge Mountains', 'The Barrens', 'Durotar') and t:
        v = sum(1 for row in items.values() if row and len(row) > 13 and row[13] and nid in row[13])
        print(nid, n[0], '<' + t + '>', z, n[12] if len(n) > 12 else None, 'sells', v)
print('--- Items sold at the Merchant\'s Favor hubs')
HUB = {256729: 248196, 256730: 248197, 256731: 248198, 256732: 248199, 256733: 248200, 256734: 248201, 256735: 248202, 256389: 256384, 256736: 256400}
qual = {}
import glob as _g, os as _o
for d in ('rd/items', 'pr/reag', 'pr/crafted', 'qd/items', 'cd/mi', 'cd/pi', 'jd/items'):
    for f in _g.glob(S + d + '/*.json'):
        try: x = json.load(open(f))
        except Exception: continue
        if 'id' in x and 'item_class' in x: qual[x['id']] = (x['item_class']['name'], x['item_subclass']['name'], x.get('purchase_price', 0))
summary = {}
for a, h in HUB.items():
    sa = {iid for iid, row in items.items() if row and len(row) > 13 and row[13] and a in row[13]}
    sh = {iid for iid, row in items.items() if row and len(row) > 13 and row[13] and h in row[13]}
    cls = collections.Counter((qual.get(i, ('?', '?'))[0]) for i in sa)
    print(npcs[a][0], '/', npcs[h][0], '| same stock:', sa == sh, '| only A:', len(sa - sh), 'only H:', len(sh - sa), '|', dict(cls))
    others = [items[i][0] for i in sa if qual.get(i, ('?',))[0] != 'Recipe']
    if others: print('    non-recipe:', others[:12])
    summary[a] = sorted(sa | sh)
json.dump({str(k): v for k, v in summary.items()}, open(S + 'sk/favor_stock.json', 'w'))
print('--- non-recipe ids')
book_items = set()
for r in json.load(open(S + 'leveling/recipebook-forever.json'))['recipes']:
    for l in r.get('learn', []): book_items.add(l['i'])
for a, ids_ in summary.items():
    for i in ids_:
        if i not in book_items and not items[i][0].startswith(('Recipe', 'Pattern', 'Plans', 'Formula', 'Schematic')): print(i, items[i][0], 'cls', items[i][11] if len(items[i]) > 11 else None)
