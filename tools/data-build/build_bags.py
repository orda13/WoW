# Builds app/public/bags-forever.json: every bag from tools/data-build/bags.tsv (the bag guide the owner shared), with its
# item id and the ids of the quests that reward it, so the page can show which bags each character has.
#   python3 -I build_bags.py <QuestieDB checkout> <AllTheThings folder>
# Item ids by name: QuestieDB's Forever, then Classic item data (read as text). Bags new in Forever that it lacks (the
# starter-zone bags) are found as the reward of their quest in AllTheThings' Forever data, named by Wowhead's Forever tooltips.
# Quest ids by title: the page's quest data (quests-forever.json and quests-att-forever.json).
import sys, os, re, json, time, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
PUB = os.path.join(HERE, '..', '..', 'app', 'public')
QDB, ATT = sys.argv[1], sys.argv[2]
norm = lambda t: re.sub(r'[^a-z0-9]', '', (t or '').lower())

names = {}
for f in ('Forever/foreverItemDB.lua', 'Classic/classicItemDB.lua'):
    for m in re.finditer(r"^\[(\d+)\] = \{'((?:[^'\\]|\\.)*)'", open(os.path.join(QDB, 'data', f), encoding='utf-8').read(), re.M):
        names.setdefault(norm(m.group(2).replace("\\'", "'")), int(m.group(1)))

quests = {}
for f in ('quests-forever.json', 'quests-att-forever.json'):
    p = os.path.join(PUB, f)
    if os.path.exists(p):
        for z in json.load(open(p))['zones']:
            for q in z['q']: quests.setdefault(norm(q['t']), []).append(q['i'])

att = ''.join(open(os.path.join(ATT, 'db', 'Camelot', 'Categories', f), encoding='utf-8-sig').read() for f in ('Zones.lua', 'ExpansionFeatures.lua'))
def rewards(qid):
    m = re.search(r'\bq\(%d,\{' % qid, att)
    if not m: return []
    d, i = 0, m.end() - 1
    for j in range(i, min(len(att), i + 4000)):
        if att[j] == '{': d += 1
        elif att[j] == '}':
            d -= 1
            if d == 0: break
    return [int(x) for x in re.findall(r'\bi\((\d+)', att[i:j])]
def tip(i):
    try:
        d = json.loads(urllib.request.urlopen(urllib.request.Request(f'https://nether.wowhead.com/forever/tooltip/item/{i}',
            headers={'User-Agent': 'leveling-ledger-build'}), timeout=20).read()); time.sleep(0.12); return d.get('name')
    except Exception: return None

# found once by name among AllTheThings' new Forever items (Wowhead's Forever tooltips), Nov 10 2026
KNOWN = {"Apprentice's Herb Pouch": 277113, "Apprentice's Skinning Satchel": 277114, "Apprentice's Mining Pack": 277115,
         'Cozy Sleeping Bag': 211527, 'Canvas Latchbag': 277977}
# where AllTheThings disagrees with the guide
NOTES = {"Grace of An'she and Mu'sha": "AllTheThings lists this quest's reward as a Scorched Leather Pouch (item 277200)"}
bags, missing = [], []
for line in open(os.path.join(HERE, 'bags.tsv'), encoding='utf-8'):
    if line.startswith('#') or line.startswith('kind\t') or not line.strip(): continue
    cols = line.rstrip('\n').split('\t') + ['']
    kind, name, slots, source, quest = cols[:5]
    b = {'kind': kind, 'n': name, 'slots': int(slots) if slots.isdigit() else None, 'src': source}
    qids = quests.get(norm(quest), []) if quest else []
    if quest: b['quest'] = quest
    if qids: b['qids'] = sorted(set(qids))
    iid = KNOWN.get(name) or names.get(norm(name))
    if quest in NOTES: b['note'] = NOTES[quest]
    if not iid:
        for q in qids:
            for r in rewards(q):
                if norm(tip(r)) == norm(name): iid = r; break
            if iid: break
    if iid: b['id'] = iid
    else: missing.append(name)
    bags.append(b)
json.dump({'source': "The bag guide the owner shared (bags.tsv); item ids from QuestieDB's Forever and Classic data, new Forever bags "
           "from AllTheThings' quest rewards checked with Wowhead's Forever tooltips.", 'fetched': time.strftime('%Y-%m-%d'),
           'kinds': [['standard', 'Standard bags'], ['starter', 'Starter-zone bag quests'], ['reagent', 'Reagent bag slot'],
                     ['enchanting', 'Enchanting bags'], ['herb', 'Herb bags'], ['soul', 'Soul bags (Warlock)'],
                     ['ammo', 'Ammo pouches'], ['quiver', 'Quivers'], ['special', 'Other']],
           'bags': bags}, open(os.path.join(PUB, 'bags-forever.json'), 'w'), indent=1, ensure_ascii=False)
print(len(bags), 'bags;', sum('id' in b for b in bags), 'with an item id;', sum('qids' in b for b in bags), 'of', sum('quest' in b for b in bags), 'quests found')
print('no item id:', missing)
print('quests not found:', sorted({b['quest'] for b in bags if 'quest' in b and 'qids' not in b}))
