# Merges Wowhead tooltip data (Forever, dataEnv=16) into the dungeon and recipe-book files.
import json, glob, sys, re, collections
S = './work/'
sys.path.insert(0, S)
from wh_parse import parse
wh = {}
for f in glob.glob(S + 'wh/items/*.json'):
    d = json.load(open(f))
    if 'error' in d: continue
    o = parse(d); wh[int(f.split('/')[-1][:-5])] = o
norm = lambda s: re.sub(r'[^a-z0-9]', '', (s or '').lower())
# --- dungeons
dp = S + 'leveling/dungeons-forever.json'; dg = json.load(open(dp))
added = collections.Counter(); unplaced = []
for iid, o in wh.items():
    if not o.get('by'): continue
    placed = False
    for d in dg['dungeons']:
        for b in d['bosses']:
            if norm(b['n']) == norm(o['by']):
                b.setdefault('loot', [])
                if iid not in b['loot']: b['loot'].insert(0, iid)
                b.setdefault('chance', {})[str(iid)] = o.get('chance')
                item = {k: v for k, v in o.items() if k not in ('by', 'chance')}
                if 'sl' in item and 'cl' not in item: item['cl'] = 'Weapon' if item.get('w') else 'Armor'
                dg['items'][str(iid)] = item
                added[d['n']] += 1; placed = True
    if not placed: unplaced.append((o['n'], o['by']))
dg['wowhead'] = 'Some loot and drop chances from Wowhead tooltips (Forever), looked up for items already known from QuestieDB.'
json.dump(dg, open(dp, 'w'), separators=(',', ':'), ensure_ascii=False)
print('dungeon loot added:', dict(added)); print('dropped by non-boss creatures:', unplaced)
# --- recipe book: crafted items Blizzard lacks
bp = S + 'leveling/recipebook-forever.json'; book = json.load(open(bp)); n = 0
for r in book['recipes']:
    if r.get('ci') and not r.get('mi') and r['ci'] in wh:
        o = wh[r['ci']]; r['mi'] = {k: v for k, v in o.items() if k in ('q', 'sl', 'sc', 'ar', 'w', 'st', 'fx', 'rl', 'il', 'b')}; r['mi']['src'] = 'wowhead'; n += 1
json.dump(book, open(bp, 'w'), separators=(',', ':'), ensure_ascii=False)
print('crafted items filled in from Wowhead:', n)
