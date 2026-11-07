# Builds leveling/recipebook-forever.json: every Forever crafting recipe, what it makes, reagents, and how it's learned.
import json, glob, os, re, collections
S = './work/'
QUAL = {'POOR': 0, 'COMMON': 1, 'UNCOMMON': 2, 'RARE': 3, 'EPIC': 4, 'LEGENDARY': 5}
def mi_from(mk):
    mi = {'cl': (mk.get('item_class') or {}).get('name'), 'sc': (mk.get('item_subclass') or {}).get('name'),
          'q': QUAL.get((mk.get('quality') or {}).get('type'), 1)}
    inv = mk.get('inventory_type') or {}
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
    if (mk.get('container_slots') or {}).get('value'): mi['bag'] = mk['container_slots']['value']
    return {k: v for k, v in mi.items() if v is not None}
# crafted-item details: from recipe-item previews, then from fetched items
crafted = {}
for f in glob.glob(S + 'rd/items/*.json'):
    x = json.load(open(f)); mk = ((x.get('preview_item') or {}).get('recipe') or {}).get('item') or {}
    if (mk.get('item') or {}).get('id'): crafted[mk['item']['id']] = mi_from(mk)
for f in glob.glob(S + 'pr/crafted/*.json'):
    x = json.load(open(f))
    if 'id' in x and x['id'] not in crafted: crafted[x['id']] = mi_from(x.get('preview_item') or x)
# recipe items (how a recipe is learned), keyed by crafted item id and by name
ri = json.load(open(S + 'leveling/recipes-forever.json'))['recipes']
craft_of_item = {}
for f in glob.glob(S + 'rd/items/*.json'):
    x = json.load(open(f)); mk = ((x.get('preview_item') or {}).get('recipe') or {}).get('item') or {}
    if 'id' in x and (mk.get('item') or {}).get('id'): craft_of_item[x['id']] = mk['item']['id']
by_craft = collections.defaultdict(list); by_name = collections.defaultdict(list)
strip_prefix = lambda n: re.sub(r'^(Pattern|Plans|Recipe|Formula|Schematic|Manual|Design|Technique): ', '', n).lower()
for e in ri:
    slim = {k: v for k, v in e.items() if k in ('i', 'n', 'q', 'price', 'sk', 'fac', 'v', 'd', 'wd', 'o', 'in', 'qs', 'src')}
    if e['i'] in craft_of_item: by_craft[craft_of_item[e['i']]].append(slim)
    by_name[(e['p'], strip_prefix(e['n']))].append(slim)
book = []; used = set()
for f in sorted(glob.glob(S + 'pr/tiers/*.json')):
    tier = json.load(open(f)); prof = tier['name']
    for cat in tier.get('categories', []):
        for r in cat.get('recipes', []):
            d = json.load(open(S + f"pr/recipes/{r['id']}.json"))
            e = {'id': d['id'], 'n': d['name'], 'p': prof, 'c': cat['name']}
            if cat['name'].upper() == 'SEASON OF DISCOVERY': e['sod'] = 1
            ci = d.get('crafted_item') or d.get('alliance_crafted_item')
            if ci:
                e['ci'] = ci['id']
                if ci['id'] in crafted: e['mi'] = crafted[ci['id']]
            if d.get('description'): e['fx'] = [d['description']]
            q = (d.get('crafted_quantity') or {})
            qty = q.get('value') or q.get('minimum')
            if qty and qty > 1: e['qty'] = int(qty) if float(qty).is_integer() else qty
            rg = [[x['reagent']['name'], x.get('quantity', 1)] for x in d.get('reagents', []) if x.get('reagent')]
            if rg: e['rg'] = rg
            learn = (by_craft.get(ci['id']) if ci else None) or ([] if e.get('sod') else by_name.get((prof, d['name'].lower()))) or []
            if learn:
                e['learn'] = learn; used.update(x['i'] for x in learn)
                sks = [x['sk'] for x in learn if x.get('sk')]
                if sks: e['sk'] = min(sks)
            book.append(e)
# recipe items that teach nothing in the books (kept only so nothing silently disappears)
orphans = [{k: v for k, v in e.items() if k in ('i', 'n', 'p', 'q', 'sk', 'mk')} for e in ri if e['i'] not in used]
out = {'source': 'Blizzard Game Data API (static-forever-us professions, recipes and items); recipe-item sources from QuestieDB Forever data.',
       'fetched': '2026-11-06', 'recipes': book, 'orphans': orphans}
json.dump(out, open(S + 'leveling/recipebook-forever.json', 'w'), separators=(',', ':'), ensure_ascii=False)
c = collections.Counter('item' if e.get('learn') else 'trainer/other' for e in book)
print(len(book), 'recipes', dict(c), 'orphan recipe items', len(orphans), os.path.getsize(S + 'leveling/recipebook-forever.json'), 'bytes')
for n in ('Minor Mana Potion', 'Moonsteel Broadsword', 'Enchant Chest - Greater Stamina', 'Heavy Woolen Cloak'):
    x = next((b for b in book if b['n'] == n), None); print(n, '->', json.dumps(x)[:500])
