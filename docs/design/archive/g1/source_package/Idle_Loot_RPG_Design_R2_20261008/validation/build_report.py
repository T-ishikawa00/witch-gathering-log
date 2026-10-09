from __future__ import annotations
from pathlib import Path
import csv,json,statistics,hashlib
from core import ROOT,DATA,SLOTS,fight,make_stats
from check_balance import batch
from progression import initial_state,settle
rows=list(csv.DictReader((ROOT/'validation/all_loadouts.csv').open()))
byboss={b:[r for r in rows if r['boss']==b and float(r['win_rate'])>=.875] for b in DATA['bosses']}
best={b:min(int(r['median_win_ms']) for r in v) for b,v in byboss.items()}
near={b:set(r['loadout'] for r in v if int(r['median_win_ms'])<=best[b]*1.1) for b,v in byboss.items()}
p=DATA['presets']['poison'];q=p.copy();q[3]='boots_g';q[5]='ring_g'
example={'boss':'sentinels','seed_range':[1001,1300],'before':{'items':p,**batch(p,'sentinels',range(1001,1301))},'after':{'items':q,**batch(q,'sentinels',range(1001,1301))},'attack_before':make_stats(p)['attack'],'attack_after':make_stats(q)['attack']}
holdout=[]
for boss,vals in byboss.items():
 top=sorted(vals,key=lambda r:int(r['median_win_ms']))[:3]
 for v in top:
  lo=[f'{s}_{f}' for s,f in zip(SLOTS,v['loadout'])]
  holdout.append({'boss':boss,'loadout':v['loadout'],**batch(lo,boss,range(2001,2301))})
sensitivity=[]
for scale in [9000,10000,11000]:
 for name,lo in DATA['presets'].items():
  for boss in DATA['bosses']:
   rr=[fight(lo,boss,seed,scale_bp=scale) for seed in range(3001,3101)]
   wins=[r for r in rr if r['win']]
   sensitivity.append({'scale_bp':scale,'preset':name,'boss':boss,'win_rate':len(wins)/len(rr),'median_win_ms':int(statistics.median(r['time_ms'] for r in wins)) if wins else None})
s,r=settle(initial_state(seed=12345),8*3600000,'sample-8h')
report={'scope':'Design-model tests, not user tests or iOS runtime tests','content_sha256':hashlib.sha256((ROOT/'data/content.json').read_bytes()).hexdigest(),
 'enumeration':{'unique_loadouts':729,'bosses':3,'seeds_per_case':32,'seed_range':[101,132],'fight_runs':729*3*32,'reliable_threshold':.875,'reliable_loadout_counts':{b:len(v) for b,v in byboss.items()},'best_median_win_ms':best,'within_10pct_best_counts':{b:len(v) for b,v in near.items()},'intersection_all_bosses_within_10pct':sorted(set.intersection(*near.values()))},
 'curated':json.loads((ROOT/'validation/curated_results.json').read_text()),'lower_attack_example':example,'heldout_top_configs':holdout,'boss_stat_sensitivity':sensitivity,'offline_8h_example':r,
 'limitations':['Only 18 fixed items and 3 bosses; no random affixes, levels, awakening, or late game modeled.','Equal crafting budget and tier are not proof of equal intrinsic stat efficiency.','A 32-seed search is a limited numerical screen; statistics are not player retention, purchase probability, or proof of fun.','Extremes of armor, haste and counter still need future expansion testing.','Long-term contents, visual quality, native save interruption, ads and IAP are not tested by this package.']}
(ROOT/'validation/report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
fixtures=[]
for name,lo in DATA['presets'].items():
 for b in DATA['bosses']:
  for seed in [0,1,17]:fixtures.append({'preset':name,'items':lo,'boss':b,'seed':seed,'expected':fight(lo,b,seed)})
fixtures.append({'preset':'poison_defense','items':q,'boss':'sentinels','seed':1001,'expected':fight(q,'sentinels',1001)})
(ROOT/'validation/golden_fights.json').write_text(json.dumps(fixtures,ensure_ascii=False,indent=2),encoding='utf-8')
(ROOT/'validation/example_traces.json').write_text(json.dumps({'before':fight(p,'sentinels',1001,trace=True),'after':fight(q,'sentinels',1001,trace=True)},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'enumeration':report['enumeration'],'example':example,'offline':r},ensure_ascii=False,indent=2))
