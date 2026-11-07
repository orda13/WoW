import json,glob,collections
A={'Darnassus','Stormwind','Ironforge','Gnomeregan Exiles','Silverwing Sentinels','Stormpike Guard','The League of Arathor','Wildhammer Clan','Alliance'}
H={'Orgrimmar','Thunder Bluff','Darkspear Trolls','Undercity','Warsong Outriders','Frostwolf Clan','The Defilers','Horde'}
ARACE={'Human','Dwarf','Night Elf','Gnome'}; HRACE={'Orc','Undead','Tauren','Troll'}
def load():
    Q={}
    for f in glob.glob('qd/q/*.json'):
        d=json.load(open(f)); Q[d['id']]=d
    return Q
def fac(q):
    r=q.get('requirements') or {}
    if r.get('faction'): return r['faction']['type'][0]
    races={x['name'] for x in r.get('races',[])}
    if races and races<=ARACE: return 'A'
    if races and races<=HRACE: return 'H'
    reps={x['reward']['name'] for x in (q.get('rewards') or {}).get('reputations',[])}
    if reps&A and not reps&H: return 'A'
    if reps&H and not reps&A: return 'H'
    return None
if __name__=='__main__':
    Q=load()
    for zone in ['Ashenvale','The Barrens','Stonetalon Mountains','Teldrassil','Darkshore','Durotar','Duskwood','Hillsbrad Foothills']:
        qs=[q for q in Q.values() if q['area'].get('name')==zone]
        print(zone,len(qs),dict(collections.Counter(fac(q) for q in qs)))
    print('all',dict(collections.Counter(fac(q) for q in Q.values())))
    qs=[q['title'] for q in Q.values() if q['area'].get('name')=='Ashenvale' and not fac(q)]; print(qs)
