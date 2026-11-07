# Usage: python3 -I build_collections.py <dir with Blizzard JSON> <out.json>
import json, sys, os, time
d = sys.argv[1]
def L(n):
    p = os.path.join(d, n)
    try: return json.load(open(p))
    except Exception: return {}
prof = L('professions.json'); profs = []
for group, kind in (('primaries', 'primary'), ('secondaries', 'secondary')):
    for x in prof.get(group, []):
        for t in x.get('tiers', []):
            profs.append({'name': x['profession']['name'], 'kind': kind, 'skill': t.get('skill_points', 0), 'max': t.get('max_skill_points', 0),
                          'recipes': sorted(r['name'] for r in t.get('known_recipes', []))})
mounts = sorted(m['mount']['name'] for m in L('collections_mounts.json').get('mounts', []))
pets = sorted({p['species']['name'] for p in L('collections_pets.json').get('pets', [])})
toys = sorted(t['toy']['name'] for t in L('collections_toys.json').get('toys', []))
heir = sorted(h['heirloom']['name'] for h in L('collections_heirlooms.json').get('heirlooms', []) if 'heirloom' in h)
titles = sorted(t['name'] for t in L('titles.json').get('titles', []) if 'name' in t)
reps = [{'name': r['faction']['name'], 'standing': r['standing']['name'], 'value': r['standing'].get('value', 0), 'max': r['standing'].get('max', 0), 'tier': r['standing'].get('tier', 0)}
        for r in L('reputations.json').get('reputations', [])]
reps.sort(key=lambda r: (-r['tier'], -r['value']))
tm = {s['slot']['name']: len(s.get('appearances', [])) for s in L('collections_transmogs.json').get('slots', [])}
ach = L('achievements.json')
out = {'professions': profs, 'mounts': mounts, 'pets': pets, 'toys': toys, 'heirlooms': heir, 'titles': titles, 'reputations': reps,
       'transmogBySlot': tm, 'transmogTotal': sum(tm.values()), 'questsCompleted': len(L('quests_completed.json').get('quests', [])),
       'achievements': ach.get('total_quantity', 0), 'achievementPoints': ach.get('total_points', 0), 'syncedAt': int(time.time() * 1000)}
json.dump(out, open(sys.argv[2], 'w'))
print({k: (len(v) if isinstance(v, (list, dict)) else v) for k, v in out.items()})
