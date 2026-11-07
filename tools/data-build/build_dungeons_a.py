import json, re, sys, collections
S = './work/'
sys.path.insert(0, S)
exec(open(S + 'build_recipes.py').read().split('# Blizzard recipe items')[0])  # items, npcs, objs, quests (Forever deltas applied), ZN, ZID, zname, npc_info
lines = open(R + 'src/corrections/enum/zones.lua').read().split('\n')
def section(start_pat, stop_pat):
    on = False; out = {}
    for l in lines:
        if re.search(start_pat, l): on = True; continue
        if on and re.search(stop_pat, l): break
        m = re.match(r'\s*([A-Z0-9_]+)\s*=\s*(\d+),', l)
        if on and m: out[m.group(1)] = int(m.group(2))
    return out
classic = section(r'-- Classic dungeons and raids', r'^\s*--')
forever = section(r'-- Forever: instance areas', r'^\s*--')
# Extra Forever instance-like zones seen in quest data
extra = {k: v for k, v in ZID.items() if re.match(r'^(BLACKMAW_HOLD|KROL_?DOK_STRONGHOLD|ALCAZ_PRISON|THE_DROWNED_CITY|THE_BARROW_DEEPS|SCARLET_ENCLAVE|SHEN_?DRALAS)\b', k)}
PARENTS = ['SHADOWFANG_KEEP', 'WAILING_CAVERNS', 'BLACKFATHOM_DEEPS', 'GNOMEREGAN', 'SCARLET_MONASTERY', 'ULDAMAN', 'THE_DEADMINES', 'BLACKROCK_SPIRE', 'BLACKROCK_DEPTHS',
           'STRATHOLME', 'SCHOLOMANCE', 'MARAUDON', 'DIRE_MAUL', 'NAXXRAMAS', 'CITY_OF_DALARAN', 'RUINS_OF_LORDAERON', 'EXCAVATION_SITE_WETLANDS']
inst = {}
for k, v in {**classic, **forever, **extra}.items():
    parent = next((p for p in PARENTS if k.startswith(p)), None)
    if k.startswith('AQ40_'): parent = 'AHN_QIRAJ'
    if k == 'THE_TEMPLE_OF_ATAL_HAKKAR': parent = 'SUNKEN_TEMPLE'
    inst[v] = parent or k
print('instance zone ids', len(inst), 'groups', len(set(inst.values())))
print('extra:', extra)
def npc_zones(nid):
    n = npcs.get(nid)
    if not n: return set()
    zs = set()
    if len(n) > 8 and isinstance(n[8], int) and n[8]: zs.add(n[8])
    if isinstance(n[6], dict): zs |= {z for z in n[6] if isinstance(z, int)}
    return zs
inst_npcs = collections.defaultdict(set)
for nid in npcs:
    for z in npc_zones(nid):
        if z in inst: inst_npcs[inst[z]].add(nid)
droppers = {}
for iid, row in items.items():
    if row and row[1]: droppers[iid] = row[1]
loot = collections.defaultdict(lambda: collections.defaultdict(list))
npc_group = collections.defaultdict(set)
for g, members in inst_npcs.items():
    for n in members: npc_group[n].add(g)
for iid, ds in droppers.items():
    if len(ds) > 30: continue
    per = collections.Counter(g for n in ds for g in npc_group.get(n, ()))
    if not per: continue
    g, c = per.most_common(1)[0]
    if c < 0.8 * len(ds): continue          # mostly dropped outside this instance: a world drop
    for nid in ds:
        if g in npc_group.get(nid, ()): loot[g][nid].append(iid)
summary = []
for g in sorted(inst_npcs):
    bosses = loot.get(g, {})
    summary.append((g, len(inst_npcs[g]), len(bosses), sum(len(v) for v in bosses.values())))
for s_ in summary: print('%-32s npcs %4d  droppers %3d  items %4d' % s_)
ids = sorted({i for g in loot.values() for v in g.values() for i in v})
open(S + 'jd/loot_item_ids.txt', 'w').write('\n'.join(map(str, ids)) + '\n')
json.dump({g: {str(n): v for n, v in d.items()} for g, d in loot.items()}, open(S + 'jd/loot_raw.json', 'w'))
print('unique loot items', len(ids))

# --- inspect bosses
for g in ('THE_DEADMINES', 'SHADOWFANG_KEEP', 'MOLTEN_CORE', 'THE_STOCKADE'):
    rows = []
    for nid in inst_npcs[g]:
        n = npcs[nid]
        rows.append((n[5] or 0, n[4] or 0, n[0], len(loot[g].get(nid, []))))
    rows.sort(reverse=True)
    print(g, [r for r in rows if r[0] >= 1][:14])

def spawn_count(nid):
    n = npcs[nid]; sp = n[6] if isinstance(n[6], dict) else {}
    return sum(len(v) if isinstance(v, list) else 1 for v in sp.values())
def is_boss(nid):
    n = npcs[nid]
    return (n[5] or 0) >= 1 and spawn_count(nid) <= 1 and not (len(n) > 13 and n[13])  # elite, single spawn, no vendor/guard title
for g in ('THE_DEADMINES', 'SHADOWFANG_KEEP', 'MOLTEN_CORE', 'THE_STOCKADE', 'WAILING_CAVERNS', 'SCARLET_MONASTERY'):
    print(g, sorted(npcs[n][0] for n in inst_npcs[g] if is_boss(n)))
