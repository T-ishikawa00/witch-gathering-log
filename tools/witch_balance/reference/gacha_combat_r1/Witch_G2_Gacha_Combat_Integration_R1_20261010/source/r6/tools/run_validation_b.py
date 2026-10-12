"""Locked comparison cells; resume without rewriting previous results.
No model selection uses held-out seeds. Each result pins input + code hashes.
"""
from bootstrap import *
from fixtures_r6 import *
from support_ai import *
from support_ai_b import CoordinatedBattleR6, CANDIDATES
from dataclasses import asdict
from pathlib import Path
import hashlib,json,time,argparse,statistics

POLICY=CANDIDATES['healing_ward_only']

def code_hash():
    files=['support_ai.py','support_ai_b.py','selected_final.py','fixtures_r6.py','bootstrap.py','run_validation_b.py']
    return sha({f:hashlib.sha256((ROOT/'tools'/f).read_bytes()).hexdigest() for f in files})

def jobs():
    out=[]
    # Old R5 seed group is a replay set, NOT new held-out evidence.
    out.append(dict(id='legacy_replay_protect6',kind='protect',hours=6,power=190,hp_bp=10000,seed_start=100001,n=200,upgrades=['paid90'],set='legacy_replay'))
    for label,kind,h,powr,hp in [('protect6','protect',6,190,10000),('offense6','offense',6,190,10000),('protect12_power110','protect',12,209,10000),('protect12_joint110','protect',12,209,11000)]:
        out.append(dict(id='holdout_'+label,kind=kind,hours=h,power=powr,hp_bp=hp,seed_start=900001,n=500,upgrades=['paid90'],set='heldout_combat_seeds'))
    # New gear randomness as a separate axis. Ten fixed crafting seeds, four
    # legal upgrades each; base battles reused, not double-counted.
    for index in range(10):
        kind='protect' if index%2==0 else 'offense'
        out.append(dict(id=f'gear_{index:02d}_{kind}',kind=kind,hours=6,power=190,hp_bp=10000,craft_seed=f'r6b-holdout-craft-{index}',seed_start=950001,n=50,upgrades=['paid90','witch5','healer5','armor5'],set='heldout_gear_and_combat'))
    return out

def run_job(job,output):
    path=output/(job['id']+'.json');lock=ROOT/'data/EXPERIMENT_LOCK_R6B.json'
    lock_sha=hashlib.sha256(lock.read_bytes()).hexdigest();fingerprint=code_hash()
    if path.exists():
        old=json.loads(path.read_text())
        assert old['lock_sha256']==lock_sha and old['code_sha256']==fingerprint
        print('reused',job['id'],flush=True);return old
    base=make_state(job['kind'],job['hours'],job.get('craft_seed'))
    states={'before':base,**{up:upgrade(base,up) for up in job['upgrades']}}
    boss=boss_variant('redistribute_pause',job['power']);boss['hp']=boss['hp']*job['hp_bp']//10000
    results=[];beg=time.time()
    for model in ['r5','r6b']:
        for mode,state in states.items():
            for seed in range(job['seed_start'],job['seed_start']+job['n']):
                cls=BattleR5 if model=='r5' else CoordinatedBattleR6;kw={} if model=='r5' else {'support_policy':POLICY}
                r=cls(state.loadout(),boss,seed,**kw).run()
                met=r['metrics'];scale=r['unit_scale']
                results.append({'job':job['id'],'model':model,'upgrade':mode,'seed':seed,'outcome':r['outcome'],'elapsed_ms':r['elapsed_ms'],'boss_hp':r['boss_remaining_hp'],'party_hp':sum(r['party_remaining_hp'].values()),'effective_heal':met.get('effective_heal',0),'barrier_absorbed':met.get('barrier_absorbed',0),'barrier_granted':met.get('barrier_granted',0),'barrier_expired_unused':met.get('barrier_expired_unused',0),'heal_casts':met.get('cast_SK_A_HEAL',0),'ward_casts':met.get('cast_SK_A_WARD',0),'cover_casts':met.get('cast_SK_S_GUARD',0),'whiffs':met.get('whiff',0),'deaths':met.get('deaths',0),'input_fingerprint':r['input_fingerprint'],'unit_scale':scale})
    paired=[]
    lookup={(r['model'],r['upgrade'],r['seed']):r for r in results}
    for model in ['r5','r6b']:
        for up in job['upgrades']:
            low=[lookup[model,'before',s] for s in range(job['seed_start'],job['seed_start']+job['n'])]
            hi=[lookup[model,up,s] for s in range(job['seed_start'],job['seed_start']+job['n'])]
            paired.append({'model':model,'upgrade':up,'n':job['n'],'wins_before':sum(x['outcome']=='VICTORY' for x in low),'wins_after':sum(x['outcome']=='VICTORY' for x in hi),'win_to_loss':[x['seed'] for x,y in zip(low,hi) if x['outcome']=='VICTORY' and y['outcome']!='VICTORY'],'loss_to_win':[x['seed'] for x,y in zip(low,hi) if x['outcome']!='VICTORY' and y['outcome']=='VICTORY']})
    record={'job':job,'lock_sha256':lock_sha,'code_sha256':fingerprint,'boss':boss,'inputs':{k:input_record(v) for k,v in states.items()},'battle_count':len(results),'paired':paired,'rows':results,'wall_seconds':time.time()-beg}
    tmp=path.with_suffix('.tmp');tmp.write_text(json.dumps(record,ensure_ascii=False));tmp.replace(path)
    print(job['id'],'battles',len(results),'seconds',round(record['wall_seconds'],2),flush=True)
    for x in paired:print({k:(len(v) if k in ['win_to_loss','loss_to_win'] else v) for k,v in x.items()},flush=True)
    return record

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--job',required=True);p.add_argument('--output',type=Path,default=ROOT/'results/validation_b_cells');a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=True)
    job=next(j for j in jobs() if j['id']==a.job);run_job(job,a.output)
