"""R4 vs locked R5, paired unseen combat seeds. Writes evidence, not game state."""
from compare_candidates import *
from dataclasses import replace,asdict
from collections import Counter
import csv,hashlib
LOCK=json.loads((ROOT/'data/EXPERIMENT_LOCK_R5.json').read_text())
SEEDS=list(range(100001,100201)); PROFILE=Profile(**LOCK['selected_profile']);RESULT=ROOT/'results'

def expanded_stats(rs):
    d=metric(rs);n=d['n'];p=d['win_rate'];z=1.96
    den=1+z*z/n;mid=(p+z*z/(2*n))/den;half=z*((p*(1-p)/n+z*z/(4*n*n))**.5)/den
    d['wilson95']=[mid-half,mid+half]
    for k in ['damage_basic','damage_active','damage_dot','damage_counter','damage_chase','received_hp','effective_heal','barrier_absorbed','barrier_expired_unused']:
        d['mean_'+k]=statistics.mean(q['metrics'].get(k,0)/q.get('unit_scale',1) for q in rs)
    return d

def main():
    rows=[];cells=[];pairs={};beg=time.time();new_count=0
    cell_dir=RESULT/'holdout_cells';cell_dir.mkdir(exist_ok=True)
    lock_sha=hashlib.sha256((ROOT/'data/EXPERIMENT_LOCK_R5.json').read_bytes()).hexdigest()
    def run(label,party,model='r5',power=190,hp_scale=1,old_pattern=False,profile=PROFILE,disabled=frozenset(),boss_override=None):
        nonlocal new_count
        saved=cell_dir/(label+'.json')
        if saved.exists():
            old=json.loads(saved.read_text());assert old['lock_sha256']==lock_sha
            cells.append(old['summary']);pairs[label]=old['outcomes'];rows.extend(old['rows']);return
        if new_count>=MAX_NEW:return
        new_count+=1
        b=copy.deepcopy(boss_override or boss_variant('original' if model=='r4' or old_pattern else 'redistribute_pause',power));b['hp']=round(b['hp']*hp_scale)
        results=[]
        for seed in SEEDS:
            cls=LegacyBattle if model=='r4' else BattleR5;kw={} if model=='r4' else {'profile':profile}
            q=cls(party,b,seed,disabled=disabled,**kw).run();results.append(q)
            rows.append({'cell':label,'seed':seed,'model':model,'outcome':q['outcome'],'elapsed_ms':q['elapsed_ms'],'boss_hp_left':q['boss_remaining_hp']/q.get('unit_scale',1),'party_hp_left':sum(q['party_remaining_hp'].values())/q.get('unit_scale',1),'deaths':q['metrics'].get('deaths',0)})
        rec={'label':label,'model':model,'power':b['power'],'hp_scale':hp_scale,'pattern':('B_R01_A_UNCHANGED' if b['id']=='B_R01_A' else ('original' if model=='r4' or old_pattern else 'redistribute_pause')),**expanded_stats(results)}
        cells.append(rec);pairs[label]=[q['outcome'] for q in results]
        cell_data={'lock_sha256':lock_sha,'summary':rec,'outcomes':pairs[label],'rows':rows[-len(SEEDS):]}
        tmp=saved.with_suffix('.tmp');tmp.write_text(json.dumps(cell_data,ensure_ascii=False));tmp.replace(saved)
        print(label,rec['wins'],'/',len(results),'median',rec['median_win_seconds'],flush=True)
        (RESULT/'HOLDOUT_CHECKPOINT.json').write_text(json.dumps({'complete':False,'cells':cells,'battles':len(rows)},indent=2))
    for kind in ['protect','offense']:
        for h in [6,12,24]:
            s=prepared_at(kind,h)
            for model in ['r4','r5']:run(f'{model}_{kind}_{h}h_p190',s.loadout(),model)
    for model in ['r4','r5']:
        for power in [171,209,228]:run(f'{model}_protect_12h_p{power}',prepared_at().loadout(),model,power)
    for kind in ['protect','offense']:
        for hs in [0.9,1.1]:run(f'r5_{kind}_12h_hp{hs}_p209',prepared_at(kind,12).loadout(),power=209,hp_scale=hs)
    for power in [190,209]:run(f'r5_arithmetic_only_12h_p{power}',prepared_at().loadout(),power=power,old_pattern=True,profile=Profile(10000,False,False,False))
    joined,_=post_miniboss();run('r5_joined_no_wait_p190',joined.loadout())
    intro=intro_state()
    for plus in [0,1,3]:
        s=copy.deepcopy(intro)
        for j in range(plus):s.enhance('intro:relic',f'enh{j}')
        for model in ['r4','r5']:run(f'{model}_intro_plus{plus}',s.loadout(),model,boss_override=LOCAL['bosses']['B_R01_A'])
    s=copy.deepcopy(intro);s.eco.roster_xp={a:0 for a in s.eco.roster_xp};s.equip('grant:C_WITCH','C_WITCH')
    run('r5_start_level1',s.loadout(),boss_override=LOCAL['bosses']['B_R01_A'])
    s=prepared_at()
    for aid in s.equipped:s.equipped[aid]=[u for u in s.equipped[aid] if not u.startswith('craft:')]
    for i,aid in enumerate(['C_WITCH','C_APPRENTICE','C_SMITH','C_FAMILIAR']):s.equip(f'craft:{i}',aid)
    run('r5_same_items_reallocated_12h',s.loadout())
    s=prepared_at('protect',6)
    for uid in ['intro:relic','grant:C_APPRENTICE','craft:0']:
        for i in range(3):s.enhance(uid,f'paid:{uid}:{i}')
    run('r5_protect_6h_paid90dust',s.loadout())
    for name,off in [('no_heal',{'heal','echo'}),('no_support',{'heal','ward','cover','counter','echo'}),('no_dot',{'poison'})]:
        run(f'r5_12h_{name}',prepared_at().loadout(),disabled=frozenset(off))
    if len(cells)!=37:
        print('CHECKPOINT_CELLS',len(cells),'expected 37');return
    final={'lock_sha256':hashlib.sha256((ROOT/'data/EXPERIMENT_LOCK_R5.json').read_bytes()).hexdigest(),'seed_range':[SEEDS[0],SEEDS[-1]],'n_per_cell':len(SEEDS),'cells':cells,'battle_count':len(rows),'last_invocation_wall_seconds':time.time()-beg,'all_invocations_total_wall_seconds':'NOT_RECORDED','model_scope':'R01 2 bosses only; no actual UI/device; loot not equipped','paired_outcomes':pairs}
    (RESULT/'HOLDOUT_RESULTS.json').write_text(json.dumps(final,ensure_ascii=False,indent=2))
    with (RESULT/'HOLDOUT_BATTLE_ROWS.csv').open('w',newline='',encoding='utf-8-sig') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    (RESULT/'HOLDOUT_CHECKPOINT.json').write_text(json.dumps({'complete':True,'cells_completed':len(cells),'battles':len(rows),'authoritative_result':'HOLDOUT_RESULTS.json'},indent=2))
    print('COMPLETE',len(rows),time.time()-beg)
if __name__=='__main__':
    import argparse
    from datetime import datetime,timezone
    ap=argparse.ArgumentParser();ap.add_argument('--max-new-cells',type=int,default=5);ap.add_argument('--output',type=Path)
    a=ap.parse_args();MAX_NEW=a.max_new_cells
    RESULT=a.output.resolve() if a.output else ROOT/'reruns'/datetime.now(timezone.utc).strftime('holdout_%Y%m%dT%H%M%S_%fZ')
    if RESULT.resolve()==(ROOT/'results').resolve():ap.error('Delivered results are immutable; choose a new output directory.')
    RESULT.mkdir(parents=True,exist_ok=True);main()
