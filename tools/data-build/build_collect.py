import json, glob, re, os, sys
sys.path.insert(0, '.')
from collect_sources import MOUNT_SRC, PET_SRC, PVP_TITLES, RETIRED
qd = json.load(open('leveling/quests-forever.json'))
rewarded = {}
for z in qd['zones']:
    for q in z['q']:
        for i in q.get('ic', []) + q.get('ig', []): rewarded.setdefault(i, []).append([q['t'], z['z'], q['i']])
def items_from(globpat):
    out = {}
    for f in glob.glob(globpat):
        d = json.load(open(f)); out[d['id']] = d
    return out
mitems = items_from('cd/mi/*.json'); pitems = items_from('cd/pi/*.json')
def iteminfo(d):
    p = d.get('preview_item', {}); r = p.get('requirements') or {}
    o = {'item': d['name'], 'iid': d['id'], 'price': d.get('purchase_price', 0)}
    if (r.get('level') or {}).get('value'): o['lvl'] = r['level']['value']
    if r.get('ability'): o['skill'] = r['ability']['spell']['name']
    if r.get('faction'): o['fac'] = r['faction']['value']['name']
    if r.get('playable_races'): o['races'] = [x['name'] for x in r['playable_races']['links']]
    if rewarded.get(d['id']): o['quests'] = rewarded[d['id']]
    return o
norm = lambda s: re.sub(r'^(reins of the |reins of |horn of the |horn of |whistle of the |whistle of |summon )', '', s.lower()).replace(' bridle', '').replace(' mount', '').replace(' mod a', '').strip()
by_item = {}
for d in mitems.values(): by_item.setdefault(norm(d['name']), []).append(d)
mounts = []; used = set()
for f in sorted(glob.glob('cd/mount/*.json')):
    m = json.load(open(f))
    if m['name'].startswith('[PH]') or m['name'] == 'Translocation': continue
    if any(x['n'] == m['name'] for x in mounts): continue
    e = {'n': m['name'], 'mid': m['id']}
    if m.get('should_exclude_if_uncollected'): e['na'] = 1
    req = m.get('requirements') or {}
    if req.get('faction'): e['fac'] = req['faction']['name']
    if req.get('classes'): e['cls'] = [c['name'] for c in req['classes']]
    if req.get('races'): e['races'] = [c['name'] for c in req['races']]
    qn = re.match(r'Summon (\w+) Qiraji Battle Tank', m['name'])
    cands = by_item.get(norm(m['name']), []) or (by_item.get(norm(f'{qn.group(1)} Qiraji Resonating Crystal'), []) if qn else [])
    if cands:
        d = cands[0]; used.add(d['id']); e.update({k: v for k, v in iteminfo(d).items() if k not in e})
    src = MOUNT_SRC.get(m['name']) or (MOUNT_SRC.get(e.get('item')) if e.get('item') else None)
    if m.get('source') and not src: src = (m['source']['name'], m['source']['name'])
    if src: e['sk'], e['src'] = src
    elif e.get('quests'): e['sk'] = 'Quest'
    elif m['name'] in RETIRED: e['sk'], e['src'] = 'Retired', 'Removed early in the original game'
    mounts.append(e)
# mount items that never matched a mount record: list them too (most are real, obtainable items)
for d in mitems.values():
    if d['id'] in used: continue
    e = {'n': re.sub(r'^(Reins of the |Horn of the |Whistle of the )', '', d['name']).replace(' Bridle', '')}
    e.update(iteminfo(d))
    src = MOUNT_SRC.get(d['name'])
    if src: e['sk'], e['src'] = src
    elif e.get('quests'): e['sk'] = 'Quest'
    # skip if a mount with the same display name already exists
    if any(x['n'].lower() == e['n'].lower() for x in mounts): continue
    mounts.append(e)
# pets
pet_items = {d['name']: d for d in pitems.values() if d['item_class']['name'] == 'Miscellaneous' and d['item_subclass']['name'] in ('Companion Pets', 'Pet')}
def pet_item_for(name):
    n = name.lower()
    for iname, d in pet_items.items():
        il = iname.lower(); inner = re.search(r'^(\w+)[^(]*\(([^)]+)\)', il)
        if il == n or il.replace(' box', '').replace(' carrier', '').replace(' egg', '') == n: return d
        if '(' not in il and re.search(r'\b' + re.escape(n) + r'\b', il): return d
        if inner:
            kind, var = inner.group(1), inner.group(2)  # e.g. "cat", "bombay" from "Cat Carrier (Bombay)"
            if n == var or (var in n and (kind in n or kind in ('parrot',))): return d
    return None
pets = []; used_p = set()
for f in sorted(glob.glob('cd/pet/*.json')):
    p = json.load(open(f)); e = {'n': p['name'], 'type': p['battle_pet_type']['name'], 'npc': (p.get('creature') or {}).get('id')}
    if p.get('should_exclude_if_uncollected'): e['na'] = 1
    if p.get('is_alliance_only'): e['fac'] = 'Alliance'
    if p.get('is_horde_only'): e['fac'] = 'Horde'
    if p.get('description'): e['desc'] = p['description']
    d = pet_item_for(p['name'])
    if d: used_p.add(d['id']); e.update({k: v for k, v in iteminfo(d).items() if k not in e})
    src = PET_SRC.get(e.get('item', '')) or PET_SRC.get(p['name'])
    if src: e['sk'], e['src'] = src
    elif p.get('source'): e['sk'] = e['src'] = p['source']['name']
    elif e.get('quests'): e['sk'] = 'Quest'
    pets.append(e)
toys = []
for f in sorted(glob.glob('cd/toy/*.json')):
    t = json.load(open(f)); d = pitems.get(t['item']['id'])
    e = {'n': t['item']['name'], 'iid': t['item']['id']}
    if t.get('should_exclude_if_uncollected'): e['na'] = 1
    if d: e.update({k: v for k, v in iteminfo(d).items() if k not in ('item',)})
    if t.get('source_description'): e['src'] = t['source_description']
    if e.get('quests'): e['sk'] = 'Quest'
    toys.append(e)
titles = []
for t in json.load(open('cd/title_index.json'))['titles']:
    e = {'n': t['name'], 'tid': t['id']}
    if t['name'] in PVP_TITLES: e['sk'], e['src'] = 'PvP', 'PvP honor rank title'
    elif t['name'].startswith('the ') and t['name'][4:] in ('Blacksmith', 'Leatherworker', 'Enchanter', 'Tailor', 'Alchemist', 'Engineer', 'Herbalist', 'Miner', 'Skinner', 'Cook', 'Angler', 'Fisherman', 'Physician'):
        e['sk'] = 'Profession'
    titles.append(e)
for lst in (mounts, pets, toys, titles): lst.sort(key=lambda e: e['n'].lower())
out = {'source': 'Blizzard Game Data API, static-forever-us mounts, pets, toys, titles and their items', 'fetched': '2026-11-06',
       'mounts': mounts, 'pets': pets, 'toys': toys, 'titles': titles}
json.dump(out, open('leveling/collectables-forever.json', 'w'), separators=(',', ':'), ensure_ascii=False)
import collections
for k in ('mounts', 'pets', 'toys', 'titles'):
    L = out[k]; print(k, len(L), 'unavailable', sum(1 for e in L if e.get('na')), 'sources', dict(collections.Counter(e.get('sk', '?') for e in L)))
print('pet items not matched:', [n for n, d in pet_items.items() if d['id'] not in used_p])
print(os.path.getsize('leveling/collectables-forever.json'), 'bytes')
