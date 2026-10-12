from pathlib import Path
from dataclasses import asdict
import json,statistics,copy,argparse
from lab import *
ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);ap.add_argument('--count',type=int,default=64);args=ap.parse_args();args.output.mkdir(parents=True,exist_ok=False)
inputs={'builds':{n:[asdict(p) for p in party(n)] for n in BUILD_NAMES},'bosses':bosses(),'seed_start':710000,'count':args.count,'scope':'conditional Lv60/R5 basic-weapon affix lab; excludes evolved cores/research/awakening'}
(args.output/'INPUTS.json').write_text(json.dumps(inputs,ensure_ascii=False,indent=2));rows=[];summaries=[]
for scenario,bo in bosses().items():
 for build in BUILD_NAMES:
  rs=[]
  for seed in range(710000,710000+args.count):
   v=fight(build,bo,seed);row={'scenario':scenario,'build':build,'seed':seed,'outcome':v['outcome'],'elapsed_ms':v['elapsed_ms'],'boss_remaining_hp':v['boss_remaining_hp'],'remaining_party_hp':sum(v['party_remaining_hp'].values()),'metrics':v['metrics']};rows.append(row);rs.append(row)
  w=[v for v in rs if v['outcome']=='VICTORY'];d={'scenario':scenario,'build':build,'wins':len(w),'n':len(rs),'median_win_seconds':statistics.median(v['elapsed_ms']/1000 for v in w) if w else None,'median_remaining_party_hp':statistics.median(v['remaining_party_hp']/10000 for v in rs),'damage_dot_share_mean':statistics.mean(v['metrics'].get('damage_dot',0)/max(1,sum(x for k,x in v['metrics'].items() if k.startswith('damage_'))) for v in rs),'counter_count_mean':statistics.mean(v['metrics'].get('reaction_counter',0) for v in rs)}
  summaries.append(d);print(d,flush=True)
(args.output/'BATTLE_ROWS.json').write_text(json.dumps(rows,ensure_ascii=False));(args.output/'SUMMARY.json').write_text(json.dumps(summaries,ensure_ascii=False,indent=2))
for scenario,bu in [('OPENINGS','BURST'),('ARMORED','TOXIN'),('COUNTERS','FORTRESS')]:
 r=fight(bu,bosses()[scenario],710000,record=True);(args.output/f'GOLDEN_{scenario}_{bu}.json').write_text(json.dumps(r,ensure_ascii=False,indent=2))
