from pathlib import Path
import sys,copy,json
p=Path(__file__).resolve().parents[1];sys.path.insert(0,str(p/'tools'))
from compare_candidates import *
import argparse
from datetime import datetime,timezone
ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path);args=ap.parse_args()
out=args.output.resolve() if args.output else p/'reruns'/datetime.now(timezone.utc).strftime('development2_%Y%m%dT%H%M%S_%fZ')
if out.resolve()==(p/'results').resolve():ap.error('Choose new output')
out.mkdir(parents=True,exist_ok=True)
results=[]
for name,profile in [('temporal',Profile(10000,True,False,True)),('urgent_temporal',Profile(10000,True,True,True))]:
 for kind in ['protect','offense']:
  for hours in [6,12,24]:
   s=prepared_at(kind,hours)
   for power in [190,209]:
    rows=[BattleR5(s.loadout(),boss_variant('redistribute_pause',power),seed,profile=profile).run() for seed in range(2001,2051)]
    rec={'profile':name,'kind':kind,'hours':hours,'power':power,**metric(rows)};results.append(rec);print(rec,flush=True)
(out/'DEVELOPMENT_SWEEP_2.json').write_text(json.dumps(results,indent=2))
