# Builds the Library Books collection ("Friend of the Library") for the page and the add-on:
#   app/public/collections-forever.json        the page's Collections section
#   addon/LevelingLedger/CollectionsData.lua    the same books for /ledger books and the Questie map pins
#   python3 -I build_library_books.py <AllTheThings folder>
# From tools/data-build/library-books.tsv (the owner's list: route order, zone, coordinates, notes, videos) joined with
# AllTheThings' Forever database (MIT; db/Camelot ExpansionFeatures, the "Library Books" section): each book's hidden quest
# (completed when you hand the book in, per character), the book item, faction-only books, the librarians and the 10-book
# reward. Item names from Wowhead's Forever tooltips. A book AllTheThings doesn't list is kept without a quest (ticked by hand).
import sys, os, re, json, time, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
ATT = sys.argv[1]
s = open(os.path.join(ATT, 'db', 'Camelot', 'Categories', 'ExpansionFeatures.lua'), encoding='utf-8-sig').read()
i = s.find('h(-799'); d = 0
for j in range(s.index('(', i), len(s)):
    if s[j] == '(': d += 1
    elif s[j] == ')':
        d -= 1
        if d == 0: break
blk = s[i:j + 1]

def tip(kind, i):
    try:
        d = json.loads(urllib.request.urlopen(urllib.request.Request(f'https://nether.wowhead.com/forever/tooltip/{kind}/{i}',
            headers={'User-Agent': 'leveling-ledger-build'}), timeout=20).read())
        time.sleep(0.12); return d.get('name')
    except Exception: return None

# the book quests listed under the 10-book reward quest, and each one's book item, zone and faction
reward = re.search(r'q\((\d+),\{sourceQuests=\{([\d,]+)\},sqreq=(\d+)', blk)
att = {}
for q in reward.group(2).split(','):
    m = re.search(r'q\(%s,\{(.*?)g=\{' % q, blk, re.S)
    f = m.group(1) if m else ''
    item = re.search(r'qss=\{(\d+)', f); r = re.search(r'\br=(\d)', f)
    if item: att[int(q)] = {'item': int(item.group(1)), 'fac': {1: 'H', 2: 'A'}.get(r and int(r.group(1))), 'name': tip('item', int(item.group(1)))}
# every reward tier (10, 20 and 25 books): its quest, level and the items to choose from (i(item) or s(source, item))
TITLES = {10: 'Friend of the Library', 20: 'Greater Friend of the Library'}
tiers = []
for m in re.finditer(r'q\((\d+),\{(?:lvl=(\d+),)?sourceQuests=\{[\d,]+\},sqreq=(\d+),g=\{', blk):
    j = blk.index('}})', m.end())
    g = blk[m.end():j]
    items = [int(x) for x in re.findall(r'\bi\((\d+)', g)] + [int(x) for x in re.findall(r'\bs\(\d+,(\d+)', g)]
    tiers.append({'at': int(m.group(3)), 'title': TITLES.get(int(m.group(3)), ''), 'quest': int(m.group(1)),
                  **({'lvl': int(m.group(2))} if m.group(2) else {}), 'rewards': [[i, tip('item', i) or f'Item {i}'] for i in items[:4]]})
tiers.sort(key=lambda t: t['at'])
# the librarians (Alliance: aqd, Horde: hqd)
def giver(tag):
    m = re.search(tag + r'=\s*\{coords=\{\s*\[(\d+)\]=\{\{([\d.]+),([\d.]+)\}\}\},qgs=\{(\d+)\}', blk)
    return {'npc': int(m.group(4)), 'n': tip('npc', int(m.group(4))) or '', 'map': int(m.group(1)), 'x': float(m.group(2)), 'y': float(m.group(3))} if m else None

norm = lambda t: re.sub(r'[^a-z0-9]', '', (t or '').lower())
byname = {norm(v['name']): (q, v) for q, v in att.items() if v['name']}
books = []
for line in open(os.path.join(HERE, 'library-books.tsv'), encoding='utf-8'):
    if line.startswith('#') or line.startswith('n\t') or not line.strip(): continue
    n, name, zone, mp, x, y, note, video = line.rstrip('\n').split('\t')
    b = {'n': int(n), 'name': name, 'zone': zone, 'map': int(mp), 'x': float(x), 'y': float(y), 'note': note, 'video': video}
    hit = byname.get(norm(name))
    if hit:
        q, v = hit; b['quest'] = q; b['item'] = v['item']
        if v['fac']: b['fac'] = v['fac']
    books.append(b)
out = {'source': "The owner's list of Library Book locations, joined with AllTheThings' WoW Forever database (MIT) for each book's quest and item.",
       'fetched': time.strftime('%Y-%m-%d'),
       'collections': [{
           'id': 'library-books', 'name': 'Library Books',
           'about': 'Books found around the world, handed in to the librarian. Per character: every character can collect them all.',
           'video': 'https://www.youtube.com/watch?v=reF3hqSufkA',
           'turnin': {'A': giver('aqd'), 'H': giver('hqd')},
           'milestones': tiers,
           'items': books}]}
# quest chains (tools/data-build/quest-chains.json): steps per faction, a Horde step {"same": n} reuses Alliance step n
chains = json.load(open(os.path.join(HERE, 'quest-chains.json'), encoding='utf-8'))['chains']
for c in chains:
    a_steps = c['steps']['A']
    for fac, steps in c['steps'].items():
        c['steps'][fac] = [dict(a_steps[st['same']]) if 'same' in st else st for st in steps]
out['chains'] = chains
# secrets (tools/data-build/secrets.json): rewards named by Wowhead's Forever tooltips
secrets = json.load(open(os.path.join(HERE, 'secrets.json'), encoding='utf-8'))['secrets']
for sc in secrets:
    if sc.get('reward'): sc['reward'] = [[i, tip('item', i) or f'Item {i}'] for i in sc['reward']]
    for k in ('items', 'allItems'):
        for i in (sc.get('have') or {}).get(k, []) + (sc.get('parts') or {}).get('items', []):
            sc.setdefault('names', {})[str(i)] = sc.setdefault('names', {}).get(str(i)) or tip('item', i) or f'Item {i}'
out['secrets'] = secrets
json.dump(out, open(os.path.join(ROOT, 'app', 'public', 'collections-forever.json'), 'w'), indent=1, ensure_ascii=False)

# the add-on's copy (ASCII only: every other character escaped, as WoW reads it as Lua)
def lstr(t): return '"' + ''.join(ch if (32 <= ord(ch) < 127 and ch not in '"\\') else ''.join('\\%03d' % x for x in ch.encode('utf-8')) for ch in t) + '"'
L = ['-- Generated by tools/data-build/build_library_books.py; edit the list there, not here.',
     '-- The Library Books ("Friend of the Library"): route order, quest (completed when handed in), book item, map and spot.',
     'local ADDON, ns = ...', 'ns.libraryBooks = {']
for b in books:
    parts = [f'n = {b["n"]}', f'name = {lstr(b["name"])}', f'zone = {lstr(b["zone"])}', f'map = {b["map"]}', f'x = {b["x"]}', f'y = {b["y"]}', f'note = {lstr(b["note"])}']
    if b.get('quest'): parts += [f'quest = {b["quest"]}', f'item = {b["item"]}']
    if b.get('fac'): parts.append(f'fac = "{b["fac"]}"')
    L.append('  { ' + ', '.join(parts) + ' },')
L.append('}')
t = out['collections'][0]['turnin']
L.append('ns.libraryTurnIn = { A = ' + (f'{{ n = {lstr(t["A"]["n"])}, zone = "Stormwind City" }}' if t['A'] else 'nil') + ', H = ' + (f'{{ n = {lstr(t["H"]["n"])}, zone = "Undercity" }}' if t['H'] else 'nil') + ' }')
L.append('ns.libraryTiers = {' + ', '.join(str(m['at']) for m in tiers) + '}')
L.append('ns.questChains = {')
for c in chains:
    L.append(f'  {{ id = {lstr(c["id"])}, name = {lstr(c["name"])}, level = {c.get("level", 1)}, steps = {{')
    for fac, steps in c['steps'].items():
        L.append(f'    {fac} = {{')
        for st in steps:
            parts = [f'zone = {lstr(st["zone"])}', f'map = {st["map"]}', f'x = {st["x"]}', f'y = {st["y"]}', f'title = {lstr(st["title"])}']
            if st.get('quest'): parts.append(f'quest = {st["quest"]}')
            if st.get('start'): parts.append('start = true')
            if st.get('optional'): parts.append('optional = true')
            L.append('      { ' + ', '.join(parts) + ' },')
        L.append('    },')
    L.append('  } },')
L.append('}')
# secrets: how the game shows each one is done, and the spots to pin on Questie's map
def ints(l): return '{' + ', '.join(str(int(x)) for x in l) + '}'
def strs(l): return '{' + ', '.join(lstr(x) for x in l) + '}'
L.append('ns.secrets = {')
for sc in secrets:
    h = sc.get('have') or {}
    hv = []
    for k in ('quests', 'items', 'allItems'):
        if h.get(k): hv.append(f'{k} = {ints(h[k])}')
    if h.get('names'): hv.append(f'names = {strs(h["names"])}')
    for k in ('toy', 'pet'):
        if h.get(k): hv.append(f'{k} = {int(h[k])}')
    parts = [f'id = {lstr(sc["id"])}', f'name = {lstr(sc["name"])}', f'status = {lstr(sc["status"])}', 'have = { ' + ', '.join(hv) + ' }']
    if sc.get('class'): parts.append(f'class = {lstr(sc["class"])}')
    if sc.get('fac'): parts.append(f'fac = {lstr(sc["fac"])}')
    if sc.get('level'): parts.append(f'level = {int(sc["level"])}')
    st = ', '.join('{ ' + f'zone = {lstr(x["zone"])}, map = {x["map"]}, x = {x["x"]}, y = {x["y"]}, title = {lstr(x["title"])}' + ' }' for x in sc.get('steps', []))
    parts.append('steps = { ' + st + ' }')
    L.append('  { ' + ', '.join(parts) + ' },')
L.append('}')
open(os.path.join(ROOT, 'addon', 'LevelingLedger', 'CollectionsData.lua'), 'w', encoding='ascii').write('\n'.join(L) + '\n')
print(len(secrets), 'secrets;', 'reward tiers', [(m['at'], m['quest'], [r[1] for r in m['rewards']]) for m in tiers])
print(len(books), 'books;', sum('quest' in b for b in books), 'with a quest;', 'rewards', out['collections'][0]['milestones'][0]['rewards'], '| librarians', t)
