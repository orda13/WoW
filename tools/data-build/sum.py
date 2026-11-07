import json,sys
def strip(o):
  if isinstance(o,dict): return {k:strip(v) for k,v in o.items() if k not in('_links','key','media','character')}
  if isinstance(o,list): return [strip(x) for x in o]
  return o
for f in sys.argv[1:]:
  d=strip(json.load(open(f)))
  s=json.dumps(d,ensure_ascii=False)
  print('==',f, len(s)); print(s[:900]); print()
