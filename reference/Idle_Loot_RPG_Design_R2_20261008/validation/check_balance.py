from __future__ import annotations
import csv,json,statistics,time,itertools
from core import ROOT,DATA,SLOTS,fight

def batch(loadout,boss,seeds):
    out=[fight(loadout,boss,s) for s in seeds]
    wins=[r for r in out if r['win']]
    return {'win_rate':len(wins)/len(out),'median_win_ms':int(statistics.median(r['time_ms'] for r in wins)) if wins else None,
    'median_hp':int(statistics.median(r['hp_remaining'] for r in wins)) if wins else 0,
    'mean_normal':round(statistics.mean(r['totals']['normal'] for r in out),2),
    'mean_poison':round(statistics.mean(r['totals']['poison'] for r in out),2),
    'mean_counter':round(statistics.mean(r['totals']['counter'] for r in out),2)}

if __name__=='__main__':
    begin=time.monotonic()
    curated=[]
    for name,loadout in DATA['presets'].items():
        for boss in DATA['bosses']:
            r={'preset':name,'boss':boss,**batch(loadout,boss,range(1,301))};curated.append(r); print(r)
    (ROOT/'validation/curated_results.json').write_text(json.dumps(curated,ensure_ascii=False,indent=2))
    rows=[]
    for fams in itertools.product('cpg', repeat=6):
        loadout=[f'{slot}_{fam}' for slot,fam in zip(SLOTS,fams)]
        for boss in DATA['bosses']:
            rows.append({'loadout':''.join(fams),'boss':boss,**batch(loadout,boss,range(101,133))})
    with (ROOT/'validation/all_loadouts.csv').open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=rows[0].keys());w.writeheader();w.writerows(rows)
    for boss in DATA['bosses']:
        opts=[r for r in rows if r['boss']==boss and r['win_rate']>=.875]
        opts.sort(key=lambda r:r['median_win_ms'])
        print(boss,'stable',len(opts),'best',opts[:5])
    print('seconds',time.monotonic()-begin)
