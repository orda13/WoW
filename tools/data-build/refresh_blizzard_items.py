# Re-reads every item the page shows from Blizzard's Forever item data, so hotfixes (binding, stats, damage, bag size,
# effects) reach the ledger without rebuilding everything:
#   app/public/items-forever.json        quest rewards and other items
#   app/public/dungeons-forever.json     dungeon loot ("items")
#   app/public/recipebook-forever.json   what each recipe makes ("mi", by the crafted item id "ci")
#   BLIZZARD_TOKEN=... python3 -I refresh_blizzard_items.py [--dry-run]
# Same item shapes as build_quest_data.py and build_book.py. Items Blizzard no longer returns are left as they are.
# Prints every change, so a hotfix list can be checked against it.
import sys, os, json, time, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor
HERE = os.path.dirname(os.path.abspath(__file__))
PUB = os.path.join(HERE, '..', '..', 'app', 'public')
TOKEN = os.environ.get('BLIZZARD_TOKEN')
DRY = '--dry-run' in sys.argv
if not TOKEN: sys.exit('set BLIZZARD_TOKEN (a client-credentials token from oauth.battle.net)')
QL = {'POOR': 0, 'COMMON': 1, 'UNCOMMON': 2, 'RARE': 3, 'EPIC': 4, 'LEGENDARY': 5, 'ARTIFACT': 6, 'HEIRLOOM': 7}

def fetch(i):
    url = f'https://us.api.blizzard.com/data/wow/item/{i}?locale=en_US'
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + TOKEN, 'Battlenet-Namespace': 'static-forever-us', 'User-Agent': 'leveling-ledger-build'})
            return json.loads(urllib.request.urlopen(req, timeout=30).read())
        except urllib.error.HTTPError as e:
            if e.code == 404: return None
            if e.code == 429 or e.code >= 500: time.sleep(1 + attempt); continue
            raise
        except Exception:
            time.sleep(1 + attempt)
    return None

def weapon(p):
    w = p.get('weapon')
    if w and w.get('damage'):
        return [w['damage'].get('min_value', 0), w['damage'].get('max_value', 0), round((w.get('attack_speed') or {}).get('value', 0) / 1000, 2), round((w.get('dps') or {}).get('value', 0), 1)]

def item_shape(d):
    """items-forever.json / dungeons-forever.json shape (build_quest_data.py)"""
    p = d.get('preview_item', {})
    o = {'n': d['name'], 'q': QL.get(d.get('quality', {}).get('type'), 1), 'il': d.get('level', 0), 'cl': d['item_class']['name'], 'sc': d['item_subclass']['name']}
    if d.get('required_level'): o['rl'] = d['required_level']
    if d.get('is_equippable'): o['sl'] = d['inventory_type']['name']
    if p.get('armor'): o['ar'] = p['armor'].get('value')
    st = [[s['type']['name'], s['value']] for s in p.get('stats', []) if 'type' in s]
    extra = [s['display']['display_string'] for s in p.get('stats', []) if 'type' not in s and s.get('display')]
    if st: o['st'] = st
    w = weapon(p)
    if w: o['w'] = w
    fx = [s.get('description') for s in p.get('spells', []) if s.get('description')] + extra
    if fx: o['fx'] = fx
    if p.get('binding'): o['b'] = p['binding']['name']
    return o

def mi_shape(d):
    """recipebook-forever.json "mi" shape (build_book.py's mi_from, on the item's preview)"""
    mk = d.get('preview_item', {})
    mi = {'cl': (mk.get('item_class') or {}).get('name'), 'sc': (mk.get('item_subclass') or {}).get('name'), 'q': QL.get((mk.get('quality') or {}).get('type'), 1)}
    inv = mk.get('inventory_type') or {}
    if inv.get('type') and inv['type'] != 'NON_EQUIP': mi['sl'] = inv['name']
    if (mk.get('armor') or {}).get('value'): mi['ar'] = mk['armor']['value']
    w = weapon(mk)
    if w: mi['w'] = w
    st = [[x['type']['name'], x['value']] for x in mk.get('stats', []) if 'type' in x]
    if st: mi['st'] = st
    fx = [x.get('description') for x in mk.get('spells', []) if x.get('description')]
    fx += [x['display']['display_string'] for x in mk.get('stats', []) if 'type' not in x and x.get('display')]
    if fx: mi['fx'] = fx
    if ((mk.get('requirements') or {}).get('level') or {}).get('value'): mi['rl'] = mk['requirements']['level']['value']
    if (mk.get('level') or {}).get('value'): mi['il'] = mk['level']['value']
    if (mk.get('binding') or {}).get('name'): mi['b'] = mk['binding']['name']
    if (mk.get('container_slots') or {}).get('value'): mi['bag'] = mk['container_slots']['value']
    return {k: v for k, v in mi.items() if v is not None}

def diff(old, new, keep=()):
    out = []
    for k in sorted(set(old) | set(new)):
        if k in keep: continue
        if old.get(k) != new.get(k): out.append(f'{k}: {old.get(k)!r} -> {new.get(k)!r}')
    return out

load = lambda f: json.load(open(os.path.join(PUB, f), encoding='utf-8'))
items, dung, book = load('items-forever.json'), load('dungeons-forever.json'), load('recipebook-forever.json')
want = set(int(i) for i in items['items']) | set(int(i) for i in dung.get('items', {})) | {r['ci'] for r in book['recipes'] if r.get('ci')}
print(len(want), 'items to read from Blizzard...', flush=True)
with ThreadPoolExecutor(8) as ex: got = dict(zip(sorted(want), ex.map(fetch, sorted(want))))
missing = sum(1 for v in got.values() if v is None)

changes = []
for i, o in items['items'].items():
    d = got.get(int(i))
    if not d: continue
    n = item_shape(d)
    ch = diff(o, n)
    if ch: changes.append(('item', o['n'], ch)); items['items'][i] = n
for i, o in dung.get('items', {}).items():
    d = got.get(int(i))
    if not d: continue
    n = item_shape(d)
    for k in ('src',):
        if k in o: n[k] = o[k]
    # Blizzard's quest items have no inventory class here; keep what the dungeon builder wrote for those
    ch = diff(o, n, keep=('src',))
    if ch: changes.append(('dungeon loot', o['n'], ch)); dung['items'][i] = n
for r in book['recipes']:
    d = got.get(r.get('ci'))
    if not d or 'mi' not in r: continue
    n = mi_shape(d)
    ch = diff(r['mi'], n)
    if ch: changes.append(('recipe makes', r['n'], ch)); r['mi'] = n

for kind, name, ch in changes: print(f'{kind}: {name}: ' + '; '.join(ch))
print(f'{len(changes)} changed, {missing} not returned by Blizzard (left as they were)')
if not DRY and changes:
    day = time.strftime('%Y-%m-%d')
    items['fetched'] = day
    for f, d in (('items-forever.json', items), ('dungeons-forever.json', dung), ('recipebook-forever.json', book)):
        json.dump(d, open(os.path.join(PUB, f), 'w', encoding='utf-8'), separators=(',', ':'), ensure_ascii=False)
    print('written')
