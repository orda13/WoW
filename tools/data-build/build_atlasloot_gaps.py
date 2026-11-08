# Builds app/public/dungeons-atlasloot-forever.json: boss loot from AtlasLoot Continued's WoW Forever module
# (AtlasLootContinued_DungeonsAndRaids/data-forever.lua) for the dungeons where it lists Forever's new items.
#   BLIZZARD_TOKEN=... python3 -I build_atlasloot_gaps.py <AtlasLoot Continued folder> [<out json>]
# Facts only (which boss drops which item ID, with the item's name from the file's comments); no AtlasLoot code or
# files are copied. The file is read as text; nothing in it is run. The page merges this like dungeons-curated-forever.json
# and keeps only items it doesn't list yet.
# Which items: Forever's new items (IDs from 250000) are taken as they are, since Blizzard's Forever item data is still
# missing many of them; older classic items only when Blizzard's Forever item data (static-forever-us) has them,
# the same rule as the rest of the dungeon loot. Without BLIZZARD_TOKEN, classic items are left out.
import sys, os, re, json, time, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
PUB = os.path.join(HERE, '..', '..', 'app', 'public')
SRC = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(PUB, 'dungeons-atlasloot-forever.json')
TOKEN = os.environ.get('BLIZZARD_TOKEN')

# AtlasLoot's Forever dungeons that list Forever's own loot -> ours (wing where it is one)
OURS = {'RagefireForever': ('RAGEFIRE_CHASM', None), 'TheHallOfThanes': ('THE_HALL_OF_THANES', None),
        'RuinsOfLordaeron': ('RUINS_OF_LORDAERON', None), 'WailingCavernsForever': ('WAILING_CAVERNS', None),
        'TheDeadminesForever': ('THE_DEADMINES', None), 'ShadowfangKeepForever': ('SHADOWFANG_KEEP', None),
        'ExcavationSiteWetlands': ('EXCAVATION_SITE_WETLANDS', None), 'BlackfathomDeepsForever': ('BLACKFATHOM_DEEPS', None),
        'TheStockadeForever': ('THE_STOCKADE', None), 'ScarletMonasteryGraveyardForever': ('SCARLET_MONASTERY', 'Graveyard'),
        'CityOfDalaran': ('CITY_OF_DALARAN', None), 'RazorfenKraulForever': ('RAZORFEN_KRAUL', None),
        'GnomereganForever': ('GNOMEREGAN', None), 'ScarletMonasteryLibraryForever': ('SCARLET_MONASTERY', 'Library')}

s = open(os.path.join(SRC, 'AtlasLootContinued_DungeonsAndRaids', 'data-forever.lua'), encoding='utf-8').read()
blocks = [(m.start(), m.group(1)) for m in re.finditer(r'^data\["([A-Za-z]+)"\]', s, re.M)]
known = set(json.load(open(os.path.join(PUB, 'dungeons-forever.json')))['items'])
for f in ('dungeons-curated-forever.json', 'dungeon-guides-forever.json'):
    p = os.path.join(PUB, f)
    if os.path.exists(p):
        d = json.load(open(p))
        known |= set(d.get('items') or {})
        for g in (d.get('dungeons') or {}).values() if isinstance(d.get('dungeons'), dict) else []: known |= set(g.get('items') or {})

checked = {}
def in_forever(iid):
    if iid >= 250000 or str(iid) in known: return True
    if not TOKEN: return False
    if iid not in checked:
        req = urllib.request.Request(f'https://us.api.blizzard.com/data/wow/item/{iid}?namespace=static-forever-us&locale=en_US',
                                     headers={'Authorization': 'Bearer ' + TOKEN})
        try: checked[iid] = urllib.request.urlopen(req, timeout=20).status == 200
        except Exception: checked[iid] = False
        time.sleep(0.1)
    return checked[iid]

out, items = {}, {}
for (a, k), (b, _) in zip(blocks, blocks[1:] + [(len(s), '')]):
    if k not in OURS: continue
    key, wing = OURS[k]
    blk = s[a:b]
    # each boss: a name, then its loot lines "{ n, itemID }, -- Item name", until the next name
    names = list(re.finditer(r'^\s*name = (?:AL\["([^"]+)"\]|"([^"]+)")', blk, re.M))[1:]   # the first is the dungeon's
    e = out.setdefault(key, {'key': key, 'bosses': [], 'other': []})
    for i, nm in enumerate(names):
        body = blk[nm.end(): names[i + 1].start() if i + 1 < len(names) else len(blk)]
        boss = nm.group(1) or nm.group(2)
        loot = []
        for m in re.finditer(r'\{\s*\d+\s*,\s*(\d{3,})\s*[,}][^\n]*?(?:--\s*(.+))?$', body, re.M):
            iid = int(m.group(1))
            if not in_forever(iid): continue
            loot.append(iid)
            if str(iid) not in items: items[str(iid)] = {'n': (m.group(2) or f'Item {iid}').strip(), 'src': 'atlasloot'}
        loot = list(dict.fromkeys(loot))
        if not loot: continue
        if re.match(r'(?i)trash|keys|quest items?', boss): e['other'] += [[iid, ['Trash' if boss.lower().startswith('trash') else boss]] for iid in loot]
        else: e['bosses'].append({'n': boss, 'loot': loot, **({'wing': wing} if wing else {})})
# keep only what the page doesn't list yet: the rest is already there from Wowhead, MSPaintWoW or QuestieDB.
# A name that isn't one of the dungeon's bosses (a quest object, an event) goes in its other drops with that name.
bn = lambda t: re.sub(r'[^a-z0-9]', '', (t or '').lower())
bosses_of = {}
for f in ('dungeons-forever.json', 'dungeons-curated-forever.json'):
    for d in json.load(open(os.path.join(PUB, f)))['dungeons']:
        bosses_of.setdefault(d['key'], set()).update(bn(x) for b in d['bosses'] for x in [b['n']] + re.split(r'\s*&\s*', b['n']))
for e in out.values():
    names = bosses_of.get(e['key'], set())
    for b in [b for b in e['bosses'] if not any(bn(b['n']) == n or bn(b['n']).startswith(n) or n.startswith(bn(b['n'])) for n in names if n)]:
        e['other'] += [[i, [b['n']]] for i in b['loot']]; e['bosses'].remove(b)
for e in out.values():
    for b in e['bosses']: b['loot'] = [i for i in b['loot'] if str(i) not in known]
    e['bosses'] = [b for b in e['bosses'] if b['loot']]
    e['other'] = [o for o in e['other'] if str(o[0]) not in known]
    print(f"{e['key']:26} new items {sum(len(b['loot']) for b in e['bosses']) + len(e['other']):3}  on", ', '.join(b['n'] for b in e['bosses']) + (' + trash' if e['other'] else ''))
out = {k: e for k, e in out.items() if e['bosses'] or e['other']}
used = {str(i) for e in out.values() for i in [x for b in e['bosses'] for x in b['loot']] + [o[0] for o in e['other']]}
items = {k: v for k, v in items.items() if k in used}
json.dump({'source': "AtlasLoot Continued's WoW Forever loot tables (which boss drops which item); Forever's new items as listed, "
           "older items only where Blizzard's Forever item data has them.",
           'curated': "AtlasLoot Continued's Forever loot tables", 'dungeons': list(out.values()), 'items': items},
          open(OUT, 'w'), indent=1, ensure_ascii=False)
print(len(items), 'items;', sum(1 for v in checked.values() if v), 'of', len(checked), 'classic items checked exist in Forever')
