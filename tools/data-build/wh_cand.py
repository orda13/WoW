import json, sys, glob, os
S = './work/'
sys.path.insert(0, S)
exec(open(S + 'build_dungeons_a.py').read().split('# --- inspect bosses')[0])  # items (Forever deltas applied), npcs, inst_npcs
inst_members = set().union(*inst_npcs.values())
dun = [i for i, row in items.items() if i >= 200000 and row and row[1] and any(n in inst_members for n in row[1])]
def missing(dd):
    out = set()
    for f in glob.glob(S + dd + '/*.json'):
        try: x = json.load(open(f))
        except Exception: continue
        if 'id' not in x: out.add(int(os.path.basename(f)[:-5]))
    return out
crafted = missing('pr/crafted') | missing('pr/reag')
print('new items dropped in instances:', len(dun), '| crafted/reagents missing:', len(crafted))
json.dump(sorted(set(dun) | crafted), open(S + 'wh/candidates.json', 'w'))
print('total', len(set(dun) | crafted))
