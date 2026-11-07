# Builds leveling/itemsets-forever.json: gear sets, their pieces and bonuses (Forever game tables via wago.tools).
import sys, csv, json, os, collections
S = './work/'
sys.path.insert(0, S)
import wago
names = {}
with open(S + 'sk/itemsparse.csv', newline='', encoding='utf-8') as f:
    for r in csv.DictReader(f): names[int(r['ID'])] = r['Display_lang']
bon = collections.defaultdict(list)
for r in wago.rows('ItemSetSpell'):
    t = wago.text(int(r['SpellID']))
    if t: bon[int(r['ItemSetID'])].append([int(r['Threshold']), t])
sets, by_item = {}, {}
for r in wago.rows('ItemSet'):
    sid = int(r['ID'])
    pieces = [int(r[f'ItemID_{i}']) for i in range(17) if r.get(f'ItemID_{i}') and r[f'ItemID_{i}'] != '0']
    if not pieces or not r['Name_lang']: continue
    sets[sid] = {'n': r['Name_lang'], 'p': [[i, names.get(i, '')] for i in pieces], 'b': sorted(bon.get(sid, []))}
    for i in pieces: by_item[i] = sid
json.dump({'source': 'Forever game tables (ItemSet, ItemSetSpell, Spell) build 1.60.1.70790 via wago.tools', 'fetched': '2026-11-06',
           'sets': {str(k): v for k, v in sets.items()}, 'byItem': {str(k): v for k, v in by_item.items()}},
          open(S + 'leveling/itemsets-forever.json', 'w'), separators=(',', ':'), ensure_ascii=False)
print(len(sets), 'sets', len(by_item), 'pieces', os.path.getsize(S + 'leveling/itemsets-forever.json'), 'bytes')
# how many set pieces appear in our data?
ours = set()
for f in ('items-forever.json',):
    ours |= {int(k) for k in json.load(open(S + 'leveling/' + f))['items']}
ours |= {int(k) for k in json.load(open(S + 'leveling/dungeons-forever.json'))['items']}
ours |= {r['ci'] for r in json.load(open(S + 'leveling/recipebook-forever.json'))['recipes'] if r.get('ci')}
hit = ours & set(by_item)
print('set pieces in quest rewards / dungeon loot / crafting:', len(hit))
for i in list(hit)[:6]: s = sets[by_item[i]]; print(' ', names.get(i), '->', s['n'], len(s['p']), 'pieces', s['b'][:2])
