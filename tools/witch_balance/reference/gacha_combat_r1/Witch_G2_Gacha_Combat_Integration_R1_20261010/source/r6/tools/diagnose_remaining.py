from bootstrap import *
from fixtures_r6 import *
from selected_final import FinalBattleR6
import json,copy

def choices(r):return [(e['t_ms'],e['source'],e['skill'],e['target']) for e in r['log'] if e['kind']=='cast_start']
entries=[]
# Preserve R6-B proof for the two originally known failures.
for seed in [100049,100069]:
    s=make_state();t=upgrade(s)
    for tag,state in [('before',s),('after',t)]:
        result=FinalBattleR6(state.loadout(),boss_variant('redistribute_pause'),seed,record=True,decision_trace=True).run()
        (ROOT/'results'/f'R6B_KNOWN_{seed}_{tag}.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
for p in sorted((ROOT/'results/validation_b_cells').glob('*.json')):
    v=json.loads(p.read_text());job=v['job']
    for pair in v['paired']:
        if pair['model']!='r6b':continue
        for seed in pair['win_to_loss']:
            s=make_state(job['kind'],job['hours'],job.get('craft_seed'));t=upgrade(s,pair['upgrade'])
            b=boss_variant('redistribute_pause',job['power']);b['hp']=b['hp']*job['hp_bp']//10000
            results=[]
            for tag,state in [('before',s),('after',t)]:
                result=FinalBattleR6(state.loadout(),b,seed,record=True,decision_trace=True).run();results.append(result)
                (ROOT/'results'/f'RESIDUAL_{job["id"]}_{seed}_{tag}.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
            lo,hi=results;cs1,cs2=choices(lo),choices(hi)
            first=next((i for i,(a,c) in enumerate(zip(cs1,cs2)) if a!=c),min(len(cs1),len(cs2)))
            a=cs1[first] if first<len(cs1) else None;c=cs2[first] if first<len(cs2) else None
            time=min(x[0] for x in [a,c] if x is not None)
            contexts=[]
            for tag,r in [('before',lo),('after',hi)]:
                contexts.append({'side':tag,'nearby_events':[e for e in r['log'] if time-250<=e['t_ms']<=time+350 and e['kind'] in ['support_decision','heal','barrier','enemy_hit','cast_start']]})
            entry={'job':job['id'],'seed':seed,'upgrade':pair['upgrade'],'before':{k:lo[k] for k in ['outcome','elapsed_ms','boss_remaining_hp']},'after':{k:hi[k] for k in ['outcome','elapsed_ms','boss_remaining_hp']},'first_choice_divergence':{'before':a,'after':c},'context':contexts,'diagnosis_status':'FIRST_OBSERVED_DIVERGENCE_ONLY_NOT_COMPLETE_CAUSAL_PROOF'}
            entries.append(entry)
            print(job['id'],seed,'first',a,c,flush=True)
(ROOT/'results/RESIDUAL_DIAGNOSES.json').write_text(json.dumps({'count':len(entries),'entries':entries,'all_saved':True},ensure_ascii=False,indent=2))
