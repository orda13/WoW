# Builds app/public/talents-<class>.json for every class from Blizzard's WoW Forever talent trees (Game Data API,
# static-forever-us): each spec tree's talents with row, column, ranks, rank text, prerequisite, spell and icon.
#   BLIZZARD_TOKEN=... python3 -I build_talents.py
# Talent ids are Blizzard's node ids, so saved picks and leveling plans keep working across rebuilds.
# icon: the spell's icon name, from Wowhead's Forever tooltips.
# bg: the classic talent tab id, for the tree's background art on Wowhead's image server
# (wow.zamimg.com/images/wow/talents/backgrounds/classic/<bg>.jpg; shown from there, never copied here).
import os, re, json, time, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
PUB = os.path.join(HERE, '..', '..', 'app', 'public')
TOKEN = os.environ['BLIZZARD_TOKEN']
API = 'https://us.api.blizzard.com/data/wow/'
BG = {('Warrior', 'Arms'): 161, ('Warrior', 'Fury'): 164, ('Warrior', 'Protection'): 163,
      ('Paladin', 'Holy'): 382, ('Paladin', 'Protection'): 383, ('Paladin', 'Retribution'): 381,
      ('Hunter', 'Beast Mastery'): 361, ('Hunter', 'Marksmanship'): 363, ('Hunter', 'Survival'): 362,
      ('Rogue', 'Assassination'): 182, ('Rogue', 'Combat'): 181, ('Rogue', 'Subtlety'): 183,
      ('Priest', 'Discipline'): 201, ('Priest', 'Holy'): 202, ('Priest', 'Shadow'): 203, ('Priest', 'Shadow Magic'): 203,
      ('Shaman', 'Elemental'): 261, ('Shaman', 'Elemental Combat'): 261, ('Shaman', 'Enhancement'): 263, ('Shaman', 'Restoration'): 262,
      ('Mage', 'Arcane'): 81, ('Mage', 'Fire'): 41, ('Mage', 'Frost'): 61,
      ('Warlock', 'Affliction'): 302, ('Warlock', 'Demonology'): 303, ('Warlock', 'Destruction'): 301,
      ('Druid', 'Balance'): 283, ('Druid', 'Feral Combat'): 281, ('Druid', 'Restoration'): 282}

def get(path):
    url = path if path.startswith('http') else API + path
    url = re.sub(r'namespace=[^&]+', 'namespace=static-forever-us', url)
    if 'namespace=' not in url: url += ('&' if '?' in url else '?') + 'namespace=static-forever-us'
    url += '&locale=en_US'
    for attempt in range(3):
        try:
            return json.loads(urllib.request.urlopen(urllib.request.Request(url, headers={'Authorization': 'Bearer ' + TOKEN}), timeout=30).read())
        except Exception:
            time.sleep(1 + attempt)
    return None
icons = {}
def icon(spell):
    """the spell's icon name, from Wowhead's Forever tooltip (Blizzard's media gives only a numbered image)"""
    if spell not in icons:
        try:
            d = json.loads(urllib.request.urlopen(urllib.request.Request(f'https://nether.wowhead.com/forever/tooltip/spell/{spell}',
                headers={'User-Agent': 'leveling-ledger-build'}), timeout=20).read())
            icons[spell] = d.get('icon') or ''
        except Exception: icons[spell] = ''
        time.sleep(0.12)
    return icons[spell]

index = get('talent-tree/index')
for ct in index['class_talent_trees']:
    cls = ct['name']; tree = get(ct['key']['href'])
    out = {'class': cls, 'source': f"Blizzard Game Data API, static-forever-us talent-tree {tree['id']}", 'fetched': time.strftime('%Y-%m-%d'), 'trees': []}
    for st in tree['spec_talent_trees']:
        s = get(st['key']['href']); spec = s['name']
        nodes = s['spec_talent_nodes']; row = {n['id']: n['display_row'] for n in nodes}
        mincol = min(n['display_col'] for n in nodes)
        ns = []
        for n in sorted(nodes, key=lambda n: (n['display_row'], n['display_col'])):
            ranks = sorted(n.get('ranks') or [], key=lambda r: r.get('rank', 0))
            tips = [r.get('tooltip') or {} for r in ranks]
            name = ((tips[0].get('talent') or {}).get('name')) if tips else ''
            sp = [((t.get('spell_tooltip') or {}).get('spell') or {}).get('id') for t in tips]
            desc = [((t.get('spell_tooltip') or {}).get('description') or '').strip() for t in tips]
            # the prerequisite is the linked talent in a row above
            req = next((x for x in (n.get('locked_by') or []) if row.get(x, 99) < n['display_row']), None)
            ns.append({'id': n['id'], 'name': name, 'row': n['display_row'], 'col': n['display_col'] - mincol, 'max': len(ranks),
                       'desc': desc, 'req': req, 'sp': sp, 'icon': icon(sp[0]) if sp and sp[0] else ''})
        out['trees'].append({'spec': spec, 'specId': s['playable_specialization']['id'], 'bg': BG.get((cls, spec)), 'nodes': ns})
        print(f"{cls:8} {spec:14} {len(ns):2} talents  background {BG.get((cls, spec))}")
    json.dump(out, open(os.path.join(PUB, f'talents-{cls.lower()}.json'), 'w'), separators=(',', ':'), ensure_ascii=False)
