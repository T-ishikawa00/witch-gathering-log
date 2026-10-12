"""Small development sweep. Results are hypotheses, not held-out acceptance."""
from pathlib import Path
import sys,json,copy,time,statistics
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'vendor/r01_r4/tools'))
from progression_bridge import prepared,post_miniboss, intro_state,LOCAL,g
from battle_model import Battle as LegacyBattle
from battle_r5 import BattleR5
from precision_rules import Profile

def prepared_at(kind='protect',hours=12):
    s=prepared(kind)
    if hours*3600000>s.eco.last_wall_ms:s.advance(hours*3600000-s.eco.last_wall_ms)
    return s

def boss_variant(name='original',power=190):
    b=copy.deepcopy(LOCAL['bosses']['B_R01_B']);b['power']=power
    if name.startswith('redistribute'):
        root,area={'redistribute1':(9500,13500),'redistribute2':(10500,12750),'redistribute3':(11500,12000),'redistribute_pause':(10500,12750)}[name]
        b['actions'][0]['coefficient_bp']=root;b['actions'][1]['coefficient_bp']=area
    if name=='rest_only':b['actions'][1]['rest_ms']+=1000
    if name=='redistribute_pause':b['actions'][1]['rest_ms']+=800
    return b

def metric(results):
    wins=[r for r in results if r['outcome']=='VICTORY']
    scale=results[0].get('unit_scale',1)
    return {'n':len(results),'wins':len(wins),'win_rate':len(wins)/len(results),
            'median_win_seconds':statistics.median(r['elapsed_ms']/1000 for r in wins) if wins else None,
            'mean_healing':statistics.mean(r['metrics'].get('effective_heal',0)/r.get('unit_scale',1) for r in results),
            'mean_deaths':statistics.mean(r['metrics'].get('deaths',0) for r in results),
            'timeouts':sum(r['outcome']=='TIMEOUT' for r in results)}

def main():
    states={k:prepared_at(k) for k in ['protect','offense']};seeds=range(2001,2051);rows=[]
    for label,cls,p in [('R4',LegacyBattle,None),('R5_precision',BattleR5,Profile(10000,False,False,False)),('R5_cover',BattleR5,Profile(10000,True,False,False)),('R5_urgent',BattleR5,Profile(10000,True,True,False))]:
        for power in [190,209]:
            kw={'profile':p} if p else {}
            rs=[cls(states['protect'].loadout(),boss_variant(power=power),seed,**kw).run() for seed in seeds]
            row={'model':label,'pattern':'original','power':power,'party':'protect',**metric(rs)};rows.append(row);print(row,flush=True)
    for name in ['redistribute1','redistribute2','redistribute3','rest_only','redistribute_pause']:
        for kind in ['protect','offense']:
            for power in [190,209]:
                rs=[BattleR5(states[kind].loadout(),boss_variant(name,power),seed,profile=Profile(10000,True,True,False)).run() for seed in seeds]
                row={'model':'R5_urgent','pattern':name,'power':power,'party':kind,**metric(rs)};rows.append(row);print(row,flush=True)
    (OUT/'DEVELOPMENT_SWEEP.json').write_text(json.dumps({'seed_range':[2001,2050],'note':'R4 previously used these seeds; development not holdout','rows':rows},ensure_ascii=False,indent=2))
if __name__=='__main__':
    import argparse
    from datetime import datetime,timezone
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path);args=ap.parse_args()
    OUT=args.output.resolve() if args.output else ROOT/'reruns'/datetime.now(timezone.utc).strftime('development_%Y%m%dT%H%M%S_%fZ')
    if OUT.resolve()==(ROOT/'results').resolve():ap.error('Choose a new output directory')
    OUT.mkdir(parents=True,exist_ok=True);main()
