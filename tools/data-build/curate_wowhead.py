# Adds a dungeon's bosses and loot, copied from its Wowhead WoW Forever page (Drops tab) by the owner, to
# app/public/dungeons-curated-forever.json. Run once per pasted page:
#   python3 -I curate_wowhead.py <pasted page .txt> [<curated json>]
# The paste's first line is the dungeon's name. It reads the Bosses list (order, rare spawns) and the Drops table:
#   [Item](https://www.wowhead.com/forever/item=ID/slug)Requires Level N
#   <Slot><Type>[Boss](.../dungeon-journal/<dungeon>/<boss>), [Boss](...)
# An item one boss drops goes on that boss; one several bosses share goes in the dungeon's other drops, with who drops it.
# A dungeon pasted again replaces its earlier entry.
import sys, os, re, json
HERE = os.path.dirname(os.path.abspath(__file__))
PUB = os.path.join(HERE, '..', '..', 'app', 'public')
src = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(PUB, 'dungeons-curated-forever.json')

SLOTS = ['Held In Off-hand', 'Main Hand', 'Off Hand', 'One-Hand', 'Two-Hand', 'Shoulder', 'Trinket', 'Ranged', 'Thrown', 'Shield',
         'Finger', 'Tabard', 'Waist', 'Wrist', 'Hands', 'Chest', 'Shirt', 'Relic', 'Head', 'Neck', 'Back', 'Legs', 'Feet']
WEAPON = re.compile(r'Axe|Mace|Sword|Dagger|Staff|Polearm|Bow|Gun|Crossbow|Wand|Thrown|Fist|Fishing Pole')
LINK = re.compile(r'\[([^\]]+)\]\((https?://[^)]+)\)')

lines = [l.rstrip() for l in open(src, encoding='utf-8').read().splitlines()]
name = lines[0].strip()
lv = None
m = re.search(r'Level\s+(\d+)\s*[–-]\s*(\d+)', '\n'.join(lines[:6]))
if m: lv = [int(m.group(1)), int(m.group(2))]
clean = lambda b: re.sub(r'\s*\((Rare|Warlock Quest)\)$', '', b).replace('\u2019', "'").strip()

# bosses in order, from the Bosses list
bosses, rare, i = [], set(), 0
while i < len(lines) and lines[i].strip() != 'Bosses': i += 1
for l in lines[i + 1:]:
    s = l.strip()
    if s in ('Guides', 'Quests', 'Drops'): break
    mm = LINK.search(s)
    if mm and 'dungeon-journal' in mm.group(2):
        b = mm.group(1)
        if b.endswith('(Rare)'): rare.add(clean(b))
        bosses.append((clean(b), mm.group(2)))

# the Drops table: an item line, then a slot/type/source line
items, loot, other = {}, {b: [] for b, _ in bosses}, []
i = next((k for k, l in enumerate(lines) if l.strip() == 'Drops'), len(lines))
k = i + 1
while k < len(lines):
    l = lines[k].strip()
    mm = re.match(r'\[([^\]]+)\]\(https?://www\.wowhead\.com/forever/item=(\d+)[^)]*\)\s*(?:Requires Level (\d+))?', l)
    if not mm: k += 1; continue
    iname, iid, rl = mm.group(1), int(mm.group(2)), mm.group(3)
    nxt = lines[k + 1].strip() if k + 1 < len(lines) else ''
    first = nxt.find('[')
    kind, srcs = (nxt[:first], nxt[first:]) if first >= 0 else (nxt, '')
    slot = next((sl for sl in SLOTS if kind.startswith(sl) and len(kind) > len(sl)), None)
    typ = kind[len(slot):] if slot else kind
    e = {'n': iname, 'src': 'wowhead'}
    if slot:
        e['sl'] = slot; e['sc'] = typ.replace(' Armor', '') if typ.endswith(' Armor') else typ
        e['cl'] = 'Weapon' if WEAPON.search(typ) else 'Armor'
    else:
        e['cl'] = 'Recipe' if re.search(r'Pattern|Plans|Formula|Recipe|Schematic|Manual', typ) else typ or 'Miscellaneous'
        e['sc'] = typ or 'Miscellaneous'
    if rl: e['rl'] = int(rl)
    items[str(iid)] = e
    who = [clean(b) for b, url in LINK.findall(srcs) if 'dungeon-journal' in url]
    for b in who:
        if b not in loot: loot[b] = []; bosses.append((b, ''))
    if len(who) == 1: loot[who[0]].append(iid)
    elif who: other.append([iid, who])
    k += 2

# a new dungeon's level range when the page has no "Level a-b" line: lowest required item level to highest quest level
if not lv:
    rls = [e['rl'] for e in items.values() if e.get('rl')]
    qls = [int(x) for x in re.findall(r'/quest=\d+[^)]*\)Level (\d+)', '\n'.join(lines))]
    if rls or qls: lv = [min(rls or qls), max(qls + rls)]
LOC = {'Ruins of Lordaeron': 'Tirisfal Glades', 'Excavation Site: Wetlands': 'Wetlands', 'City of Dalaran': 'Alterac Mountains',
       'The Hall of Thanes': 'Ironforge'}

# a wing of a dungeon the data lists as one ("Scarlet Monastery: Library"): its bosses join that dungeon's entry
whole, wing = name, None
WINGS = ('Scarlet Monastery', 'Stratholme', 'Dire Maul', 'Blackrock Spire')
for w in WINGS:
    if name.startswith(w + ':') or name.startswith(w + ' '): whole, wing = w, name[len(w):].lstrip(':').strip()
    elif name.endswith(' ' + w): whole, wing = w, name[:-len(w)].strip()   # "Lower Blackrock Spire"
key = re.sub(r'[^A-Z0-9]+', '_', whole.upper()).strip('_')
known = json.load(open(os.path.join(PUB, 'dungeons-forever.json')))['dungeons']
have = next((d for d in known if d['n'].lower() == whole.lower()), None)
if have: key = have['key']
entry = {'key': key, 'n': whole, 'kind': have['kind'] if have else 'Dungeon', 'size': have.get('size', 5) if have else 5,
         'loc': have['loc'] if have else LOC.get(name, ''), 'lv': have['lv'] if have else (lv or [0, 0]),
         'bosses': [{'n': b, 'loot': loot.get(b, []), **({'wh': url} if url else {}), **({'rare': 1} if b in rare else {}), **({'wing': wing} if wing else {})} for b, url in bosses],
         'other': other, 'qz': have['qz'] if have else [whole], 'curated': "Wowhead's dungeon journal, pasted 2026-11-08"}

data = json.load(open(out)) if os.path.exists(out) else {'source': '', 'dungeons': [], 'items': {}}
if wing:
    # keep the other wings already pasted; replace this wing's bosses and shared drops
    prev = next((d for d in data['dungeons'] if d['key'] == key), None)
    if prev:
        mine = {b['n'] for b in entry['bosses']}
        entry['bosses'] = [b for b in prev['bosses'] if b.get('wing') != wing] + entry['bosses']
        entry['other'] = [o for o in prev.get('other', []) if not set(o[1]) <= mine] + entry['other']
data['dungeons'] = [d for d in data['dungeons'] if d['key'] != key] + [entry]
data['items'].update(items)
json.dump(data, open(out, 'w'), indent=1, ensure_ascii=False)
print(f"{name}: {len(bosses)} bosses, {sum(len(v) for v in loot.values())} boss items, {len(other)} shared, {len(items)} items" + (" (new dungeon)" if not have else f" (merged into {key})"))
for b, _ in bosses: print(f"  {b}{' (rare)' if b in rare else ''}: {len(loot.get(b, []))}")
