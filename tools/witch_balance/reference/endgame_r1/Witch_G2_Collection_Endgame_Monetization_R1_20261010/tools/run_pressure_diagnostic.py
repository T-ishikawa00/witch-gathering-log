"""Reproduce the exploratory 128-battle pressure sweep, not the main study."""
import sys,copy,json,statistics
from pathlib import Path
import argparse
ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);args=ap.parse_args();args.output.mkdir(parents=True,exist_ok=False)
import lab
rows=[]
for power in (1200,1800,2400,3000):
 for hp in (90000,150000):
  bo=copy.deepcopy(lab.bosses()['PRESSURE']);bo['power']=power;bo['hp']=hp
  for name in lab.BUILD_NAMES:
   rs=[lab.fight(name,bo,s) for s in (101,102,103,104)]
   wins=[r for r in rs if r['outcome']=='VICTORY']
   d={'hp':hp,'power':power,'build':name,'wins':len(wins),'n':len(rs),'seconds':statistics.median(r['elapsed_ms']/1000 for r in wins) if wins else None}
   rows.append(d);print(d,flush=True)
(args.output/'CALIBRATION.json').write_text(json.dumps(rows,indent=2))
