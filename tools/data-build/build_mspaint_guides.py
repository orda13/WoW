# Builds app/public/dungeon-guides-forever.json from MSPaintWoW's WoW Forever dungeon guides (www.mspaintwow.com;
# its robots.txt allows crawling). One request per dungeon page, a few seconds apart.
#   python3 -I build_mspaint_guides.py [<out json>]
# It keeps facts only: pull order, boss difficulty, dungeon quests and their rewards, each item's drop chance and the specs
# the site marks it best-in-slot (or top 3) for. The site's own guide text and hand-drawn maps stay there: the page links to them.
import sys, os, re, json, time, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
PUB = os.path.join(HERE, '..', '..', 'app', 'public')
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(PUB, 'dungeon-guides-forever.json')
SITE = 'https://www.mspaintwow.com'
UA = {'User-Agent': 'leveling-ledger-build'}

def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30).read().decode('utf-8')

def flight(page):
    # Next.js streams the page's data as self.__next_f.push([1,"..."]) chunks; joined, they're "id:value" lines
    txt = ''.join(json.loads('"' + c + '"') for c in re.findall(r'self\.__next_f\.push\(\[1,"(.*?)"\]\)', page, re.S))
    refs = {}
    for line in txt.split('\n'):
        m = re.match(r'([0-9a-f]+):([\[{].*)$', line)
        if m:
            try: refs[m.group(1)] = json.loads(m.group(2))
            except ValueError: pass
    return txt, refs

def obj_at(txt, marker):
    i = txt.find(marker)
    return json.JSONDecoder().raw_decode(txt[i:])[0] if i >= 0 else None

def deref(v, refs):
    return refs.get(v[1:], v) if isinstance(v, str) and v.startswith('$') else v

bn = lambda t: re.sub(r'[^a-z0-9]', '', re.sub(r'^the\s+', '', (t or '').lower()))
known = json.load(open(os.path.join(PUB, 'dungeons-forever.json')))['dungeons']
known += json.load(open(os.path.join(PUB, 'dungeons-curated-forever.json')))['dungeons']
keys = {bn(d['n']): d['key'] for d in known}
keys[bn('Stormwind Stockade')] = 'THE_STOCKADE'

sm = get(SITE + '/sitemap.xml')
pages = sorted(set(re.findall(r'<loc>(https://www\.mspaintwow\.com/wow-forever/([a-z0-9-]+))</loc>', sm)))
out = {}
for url, slug in pages:
    if slug in ('dungeons', 'gear-ladder'): continue
    time.sleep(3)
    txt, refs = flight(get(url))
    d = obj_at(txt, '{"map":{"image"')
    loot = obj_at(txt, '{"rows":[')
    if not d or not loot: print('no guide data on', url); continue
    key = keys.get(bn(d['name']))
    if not key: print('no dungeon matches', d['name']); continue
    items = {}
    for iid, it in (loot.get('items') or {}).items():
        tip = ' '.join(t.get('text', '') for t in it.get('tooltip') or [])
        ch = re.search(r'Drop Chance:\s*([\d.]+)%', tip)
        e = {'n': it.get('name'), 'q': it.get('quality'), 'sl': it.get('slot'), 'rl': it.get('reqLevel')}
        if ch: e['chance'] = float(ch.group(1))
        for tier in ('bis', 'top3'):
            specs = sorted({f"{c['cls']}:{c['spec']}" for c in it.get('classes') or [] if c.get('tier') == tier})
            if specs: e[tier] = specs
        items[iid] = {k: v for k, v in e.items() if v is not None}
    bosses = [{'n': b['name'], 'order': b['order'], 'diff': b.get('difficulty'), 'url': f"{url}/{b['slug']}",
               'loot': deref(next((r['items'] for r in loot['rows'] if r.get('key') == b['slug']), []), refs)}
              for b in sorted(d['bosses'], key=lambda b: b['order'])]
    quests = [{'n': q['quest'], 'lv': q.get('level'), **({'fac': q['faction'].title()} if q.get('faction') else {}),
               'items': q.get('items', [])} for q in d.get('quests') or []]
    out[key] = {'n': d['name'], 'url': url, 'bosses': bosses, 'quests': quests, 'items': items}
    print(f"{key:26} {d['name']:28} bosses {len(bosses):2}  quests {len(quests):2}  items {len(items):3}")

json.dump({'source': "MSPaintWoW's WoW Forever dungeon guides (www.mspaintwow.com): pull order, boss difficulty, quests, "
           "drop chances and best-in-slot marks. Guides, maps and tips are on their pages.",
           'fetched': time.strftime('%Y-%m-%d'), 'dungeons': out}, open(OUT, 'w'), separators=(',', ':'), ensure_ascii=False)
print(os.path.getsize(OUT), 'bytes')
