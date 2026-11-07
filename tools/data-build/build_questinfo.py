# Adds quest level, minimum level, start/end NPCs with coordinates, objectives and real chain links
# from QuestieDB's Forever data to leveling/quests-forever.json.
import json, sys, collections
S = './work/'
sys.path.insert(0, S)
exec(open(S + 'build_recipes.py').read().split('# Blizzard recipe items')[0])  # items, npcs, objs, quests, ZID, zname, apply()
dq = parse_return_table(open(R + 'src/corrections/Forever/generated/foreverBaseQuest.lua').read(), 'Load(')
QK = {'name': 0, 'startedBy': 1, 'finishedBy': 2, 'requiredLevel': 3, 'questLevel': 4, 'objectivesText': 7, 'preQuestGroup': 11, 'preQuestSingle': 12, 'nextQuestInChain': 21}
for qid, d in dq.items():
    row = list(quests.get(qid) or [None] * 36)
    while len(row) < 36: row.append(None)
    for k, v in d.items():
        if not (isinstance(k, tuple) and k[0] == 'id'): continue
        f = k[1].split('.', 1)[1]; add = f.endswith('_add'); f = f[:-4] if add else f
        if f not in QK: continue
        i = QK[f]
        if add and isinstance(v, list) and isinstance(row[i], list):
            row[i] = [list(dict.fromkeys((a or []) + (b or []))) if isinstance(a, list) or isinstance(b, list) else (a or b) for a, b in zip((row[i] + [None] * 3)[:3], (v + [None] * 3)[:3])]
        else: row[i] = v
    quests[qid] = row
name_to_zid = collections.defaultdict(set)
for zid in ZN:
    n = zname(zid)
    if n: name_to_zid[n].add(zid)
def spot(spawns, prefer):
    if not isinstance(spawns, dict) or not spawns: return None
    keys = [z for z in spawns if isinstance(z, int)]
    z = next((k for k in keys if k in prefer), keys[0] if keys else None)
    pts = spawns.get(z) or []
    if not pts or not isinstance(pts, list) or not isinstance(pts[0], list) or len(pts[0]) < 2: return [zname(z)] if zname(z) else None
    x, y = pts[0][0], pts[0][1]
    if not isinstance(x, (int, float)) or x < 0: return [zname(z)] if zname(z) else None
    return [zname(z), round(x, 1), round(y, 1)]
def who(group, prefer):
    out = []
    if not isinstance(group, list): return out
    kinds = [('npc', 0), ('object', 1), ('item', 2)]
    for kind, gi in kinds:
        ids = group[gi] if gi < len(group) and isinstance(group[gi], list) else []
        for i in ids[:2]:
            if kind == 'npc' and i in npcs and npcs[i]: e = [kind, i, npcs[i][0]] + (spot(npcs[i][6], prefer) or [])
            elif kind == 'object' and i in objs and objs[i]: e = [kind, i, objs[i][0]] + (spot(objs[i][3], prefer) or [])
            elif kind == 'item' and i in items and items[i]: e = [kind, i, items[i][0]]
            else: continue
            out.append(e)
        if len(out) >= 2: break
    return out
qp = S + 'leveling/quests-forever.json'; qf = json.load(open(qp))
ours = {q['i']: (q, z) for z in qf['zones'] for q in z['q']}
links = collections.defaultdict(set); n_lv = n_s = n_o = 0
for qid, (q, z) in ours.items():
    for k in ('lv', 'rl', 'qs', 'qe', 'ob'): q.pop(k, None)
    row = quests.get(qid)
    if not row: continue
    row = list(row) + [None] * max(0, 36 - len(row))
    prefer = name_to_zid.get(z['z'], set())
    if isinstance(row[4], int) and row[4] > 0: q['lv'] = row[4]; n_lv += 1
    if isinstance(row[3], int) and row[3] > 0: q['rl'] = row[3]
    s = who(row[1], prefer); e = who(row[2], prefer)
    if s: q['qs'] = s; n_s += 1
    if e: q['qe'] = e
    ob = row[7]
    if isinstance(ob, list):
        t = ' '.join(x for x in ob if isinstance(x, str)).strip()
        if t: q['ob'] = t[:400]; n_o += 1
    pre = [p for p in ((row[11] or []) + (row[12] or [])) if isinstance(p, int) and p in ours]
    nxt = row[21] if isinstance(row[21], int) and row[21] in ours else None
    for p in pre: links[p].add(qid)
    if nxt: links[qid].add(nxt)
# Real chains: connected groups of linked quests, ordered by depth from the first quest
parent = {}
def find(a):
    parent.setdefault(a, a)
    while parent[a] != a: parent[a] = parent[parent[a]]; a = parent[a]
    return a
for a, bs in links.items():
    for b in bs: parent[find(a)] = find(b)
groups = collections.defaultdict(list)
for qid in set(links) | {b for bs in links.values() for b in bs}: groups[find(qid)].append(qid)
incoming = collections.defaultdict(set)
for a, bs in links.items():
    for b in bs: incoming[b].add(a)
nchains = 0
for gid, members in groups.items():
    if len(members) < 2: continue
    nchains += 1
    depth = {}
    def dep(x, seen=()):
        if x in depth: return depth[x]
        ins = [p for p in incoming.get(x, ()) if p not in seen]
        depth[x] = 1 + max((dep(p, seen + (x,)) for p in ins), default=0)
        return depth[x]
    for m in members: ours[m][0]['ch'] = [f'q{nchains}', dep(m), 'b']
json.dump(qf, open(qp, 'w'), separators=(',', ':'), ensure_ascii=False)
print(f'quests: {len(ours)}  with level {n_lv}  with giver {n_s}  with objectives {n_o}  real chains {nchains}')
for t in ('Crown of the Earth', 'Ursal the Mauler', 'The Relics of Wakening'):
    for qid, (q, z) in ours.items():
        if q['t'] == t and z['z'] == 'Teldrassil': print(t, {k: q.get(k) for k in ('lv', 'rl', 'qs', 'qe', 'ch')}, (q.get('ob') or '')[:80]); break
