"""Execute frozen gacha-to-R6 comparisons; never modify original evidence."""
from bridge import *
import gzip,csv,time,statistics,argparse
PLAN=json.loads((ROOT/'data/EXPERIMENT_PLAN.json').read_text())
def dump(p,o):p.write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n')
def summarize(rows):
    groups=defaultdict(list)
    for r in rows:groups[r['case'],r['arm'],r['stage']].append(r)
    out=[]
    for (case,arm,stage),rs in groups.items():
        wins=[r for r in rs if r['outcome']=='VICTORY']
        row={'case':case,'arm':arm,'stage':stage,'n':len(rs),'acquisition_clusters':len(set(r['acquisition'] for r in rs)),'wins':len(wins),'baseline_wins':sum(r['baseline_win'] for r in rs),
            'loss_to_win':sum(not r['baseline_win'] and r['outcome']=='VICTORY' for r in rs),'win_to_loss':sum(r['baseline_win'] and r['outcome']!='VICTORY' for r in rs),
            'median_win_seconds':statistics.median(r['elapsed_ms']/1000 for r in wins) if wins else None}
        for k in ('new_equipped','low_equipped','high_equipped','new_powder','extra_steps','hidden_future_difference_disposals','power_pct_change','hp_pct_change'):
            row['mean_'+k]=statistics.mean(r[k] for r in rs)
        out.append(row)
    return out

def main(out):
    out.mkdir(parents=True,exist_ok=True)
    if (out/'EXPERIMENT_RESULTS.json').exists():raise RuntimeError('choose fresh output')
    beg=time.time();rows=[];sessions=[];examples=[];runs=0
    with gzip.open(out/'SCENARIOS_AND_DRAWS.jsonl.gz','wt',encoding='utf-8') as store:
        for case in PLAN['case_definition']:
            for index in range(PLAN['acquisition_seeds']):
                initial=build_state(case['kind'],case['hours'],PLAN['acquisition_seed_prefix']+str(index));initial_record=state_record(initial)
                base=copy.deepcopy(initial);base_changes=recommend_equipment(base);base_spend=spend_for_enhancement(base,'original-powder');base_record=state_record(base)
                bs=boss_variant('redistribute_pause',case['boss_power']);bs['hp']=bs['hp']*case['boss_hp_bp']//10000
                seeds=[1700001+index*100+j for j in range(PLAN['combat_seeds_per_acquisition'])]
                before_results={seed:battle(base,seed,bs) for seed in seeds};runs+=len(seeds)
                powerbase=sum(x['power'] for x in base_record['stats'].values());hpbase=sum(x['hp'] for x in base_record['stats'].values())
                for seed,r in before_results.items():
                    rows.append({'case':case['id'],'arm':'NO_GACHA','stage':'BASE','acquisition':index,'seed':seed,'outcome':r['outcome'],'elapsed_ms':r['elapsed_ms'],'boss_remaining_hp':r['boss_remaining_hp'],'baseline_win':r['outcome']=='VICTORY','new_equipped':0,'low_equipped':0,'high_equipped':0,'new_powder':0,'extra_steps':0,'hidden_future_difference_disposals':0,'power_pct_change':0,'hp_pct_change':0,'input_fingerprint':r['input_fingerprint']})
                arms=list(PLAN['arms'])
                if case['id']=='FOREST6_PROTECT':arms += [{'id':'C_1500_LEGACY29','candidate':C.id,'draws':50,'mode':'29'},{'id':'C_1500_GROWTH_POOL','candidate':C.id,'draws':50,'affix_mode':'growth'}]
                rec={'case':case,'acquisition':index,'initial':initial_record,'baseline':base_record,'baseline_changes':base_changes,'baseline_spend':base_spend,'arms':[]}
                for arm in arms:
                    generator=DrawBridge(CANDIDATES[arm['candidate']],PLAN['gacha_seed_prefix']+str(index),base,arm.get('mode','33'),arm.get('affix_mode','commerce'))
                    draws=generator.draw(arm['draws']);s=copy.deepcopy(base);accept_draws(s,draws,'draw:'+arm['id']);changes=recommend_equipment(s);eq=copy.deepcopy(s)
                    quote=cleanup_quote(s,draws);commit_cleanup(s,quote,draws,'scrap:'+arm['id'],True);spend=spend_for_enhancement(s,'new-powder:'+arm['id']);full=s
                    newids={x['item'].uid for x in draws}&actual_owned(eq);low=sum(eq.items[u].quality in ('Q0','Q1') for u in newids)
                    sess={'case':case['id'],'acquisition':index,'arm':arm['id'],'draws':len(draws),'quality_counts':dict(Counter(x['item'].quality for x in draws)),
                         'new_equipped':len(newids),'new_low_equipped':low,'offered_low':len(quote['ids']),'dust_from_new_low':quote['dust'],'hidden_future_difference_disposals':len(quote['hidden_future_difference_ids']),
                         'extra_steps':spend['steps'],'extra_powder_spent':spend['spent'],'powder_left':full.eco.dust,'items_after':len(full.items)}
                    sessions.append(sess);rec['arms'].append({'definition':arm,'summary':sess,'draws':[{**x,'item':asdict(x['item'])} for x in draws],'equipment_changes':changes,'cleanup':quote,'enhancement':spend,'equipped_state':state_record(eq),'full_state':state_record(full)})
                    for stage,st in [('EQUIP',eq),('FULL',full)]:
                        sr=state_record(st)
                        for k in ('gates','xp','materials','credited_ms'):
                            if sr[k]!=base_record[k]:raise AssertionError('unearned progression: '+k)
                        power=sum(x['power'] for x in sr['stats'].values());hp=sum(x['hp'] for x in sr['stats'].values())
                        for seed in seeds:
                            r=battle(st,seed,bs);runs+=1;br=before_results[seed]
                            row={'case':case['id'],'arm':arm['id'],'stage':stage,'acquisition':index,'seed':seed,'outcome':r['outcome'],'elapsed_ms':r['elapsed_ms'],'boss_remaining_hp':r['boss_remaining_hp'],'baseline_win':br['outcome']=='VICTORY',
                                 'new_equipped':len(newids),'low_equipped':low,'high_equipped':len(newids)-low,'new_powder':quote['dust'] if stage=='FULL' else 0,'extra_steps':spend['steps'] if stage=='FULL' else 0,
                                 'hidden_future_difference_disposals':len(quote['hidden_future_difference_ids']) if stage=='FULL' else 0,'power_pct_change':100*(power/powerbase-1),'hp_pct_change':100*(hp/hpbase-1),'input_fingerprint':r['input_fingerprint']}
                            rows.append(row)
                            typ='regression' if row['baseline_win'] and r['outcome']!='VICTORY' else 'improvement' if not row['baseline_win'] and r['outcome']=='VICTORY' else None
                            if typ and sum(x['type']==typ for x in examples)<3 and arm['id']=='C_1500' and stage=='FULL':
                                eid=f'{typ}_{case["id"]}_{index}_{seed}'
                                dump(out/(eid+'.json'),{'case':case,'type':typ,'arm':arm,'acquisition':index,'seed':seed,'before':base_record,'after':sr,'draws':[{**x,'item':asdict(x['item'])} for x in draws],'baseline_log':battle(base,seed,bs,True),'after_log':battle(st,seed,bs,True)})
                                examples.append({'id':eid,'type':typ,'case':case['id'],'acquisition':index,'seed':seed})
                store.write(json.dumps(rec,ensure_ascii=False,separators=(',',':'))+'\n')
            print(case['id'],'done',runs,'reference battles',round(time.time()-beg,1),'seconds',flush=True)
            dump(out/'CHECKPOINT.json',{'finished_case':case['id'],'computed_cells':runs,'summary':summarize(rows)})
    with (out/'BATTLE_ROWS.csv').open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    dump(out/'SESSION_SUMMARIES.json',sessions)
    result={'plan_sha256':hashlib.sha256((ROOT/'data/EXPERIMENT_PLAN.json').read_bytes()).hexdigest(),'actual_reference_battle_cells':runs,'full_trace_recomputations':len(examples)*2,'rows':len(rows),'summary':summarize(rows),'trace_examples':examples,'elapsed_seconds':time.time()-beg,
            'not_claimed':['enjoyment','willingness to pay','unique players','30/90-day integrated economy','advanced R6 battle support','real StoreKit/DB','optimal selection','no regressions'],
            'code_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/'tools').glob('*.py'))}}
    assert runs==PLAN['planned_reference_battles'] and len(rows)==runs
    dump(out/'EXPERIMENT_RESULTS.json',result);print('DONE',runs,round(time.time()-beg,1),flush=True)
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);args=ap.parse_args();main(args.output.resolve())
