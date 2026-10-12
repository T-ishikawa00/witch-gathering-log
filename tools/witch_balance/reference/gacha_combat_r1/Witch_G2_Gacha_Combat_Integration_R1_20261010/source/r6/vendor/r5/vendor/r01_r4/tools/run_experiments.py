"""Bounded source-based combat/economy experiments; no player or device test."""
from dataclasses import asdict
from collections import Counter
import copy,json,csv,statistics,time
from progression_bridge import *
RESULT=ROOT/'results'
def write_json(path,x):path.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n')
def quant(a,p):
    if not a:return None
    s=sorted(a);x=(len(s)-1)*p;i=int(x);return s[i]+(s[min(i+1,len(s)-1)]-s[i])*(x-i)
def summarize(rows):
    wins=[r for r in rows if r['outcome']=='VICTORY'];ts=[r['elapsed_ms']/1000 for r in wins]
    n=len(rows);w=len(wins);p=w/n;z=1.96
    center=(p+z*z/(2*n))/(1+z*z/n);half=z*((p*(1-p)/n+z*z/(4*n*n))**.5)/(1+z*z/n)
    return {'n':n,'wins':w,'win_rate':p,'wilson95':[center-half,center+half],
            'defeats':sum(r['outcome']=='DEFEAT' for r in rows),'timeouts':sum(r['outcome']=='TIMEOUT' for r in rows),
            'win_seconds_p10':quant(ts,.1),'win_seconds_p50':quant(ts,.5),'win_seconds_p90':quant(ts,.9),
            'mean_end_boss_hp':statistics.mean(r['boss_remaining_hp'] for r in rows),
            'mean_metrics':{k:statistics.mean(r['metrics'].get(k,0) for r in rows) for k in ['effective_heal','barrier_absorbed','cover_hits','damage_dot','damage_counter','damage_chase','echo_consumed','deaths']}}
def snap(st,label):
    return {'id':label,'gates':sorted(st.gates),'cleared':sorted(st.clears),'joined':list(st.eco.roster_xp),'credited_hours':st.eco.credited_ms/3600000,
            'xp':st.eco.roster_xp,'dust_remaining':st.eco.dust,'materials_remaining':st.eco.materials,
            'spent_materials':st.spent_materials,'spent_dust':st.spent_dust,'natural_gear_count_not_equipped':len(st.eco.gear),
            'loadout':[{'actor_id':p.actor_id,'level':p.level,'awakening':p.awakening,'items':[asdict(i) for i in p.items],
                        'stats':g.actor_stats(p.actor_id,p.level,list(p.items))} for p in st.loadout()],
            'inventory_sha256':st.inventory_hash(),'history':st.history}
def main():
    t=time.time();scenarios={};raw=[];summary={};snapshotdata=[]
    seeds=list(range(1001,1101));intro=intro_state()
    sc=[('A_INTRO_Q2',intro,'B_R01_A'),('A_START_L1',copy.deepcopy(intro),'B_R01_A')]
    sc[1][1].eco.roster_xp={a:0 for a in intro.eco.roster_xp};sc[1][1].equip('grant:C_WITCH','C_WITCH')
    one=copy.deepcopy(intro);one.enhance('intro:relic','once');sc.append(('A_INTRO_PLUS1',one,'B_R01_A'))
    three=copy.deepcopy(intro)
    for i in range(3):three.enhance('intro:relic','en'+str(i))
    sc.append(('A_INTRO_PLUS3',three,'B_R01_A'))
    post,_=post_miniboss();sc.append(('B_JOINED_NO_WAIT',post,'B_R01_B'))
    for policy in ['protect','offense']:
        base=prepared(policy)
        for hour in [6,12,24]:
            st=copy.deepcopy(base)
            if hour*3600000>st.eco.last_wall_ms:st.advance(hour*3600000-st.eco.last_wall_ms)
            sc.append((f'B_{policy.upper()}_{hour}H',st,'B_R01_B'))
    swapped=copy.deepcopy(next(st for label,st,_ in sc if label=='B_PROTECT_12H'))
    for aid in swapped.equipped:swapped.equipped[aid]=[u for u in swapped.equipped[aid] if u not in ('craft:0','craft:1','craft:2','craft:3')]
    for i,aid in enumerate(['C_WITCH','C_APPRENTICE','C_SMITH','C_FAMILIAR']):swapped.equip('craft:'+str(i),aid)
    sc.append(('B_SAME_ITEMS_REALLOCATED_12H',swapped,'B_R01_B'))
    for label,st,bid in sc:
        rows=[];scenarios[label]=(st,bid);snapshotdata.append(snap(st,label));party=st.loadout()
        for seed in seeds:
            r=Battle(party,LOCAL['bosses'][bid],seed).run();rows.append(r)
            raw.append({'scenario':label,'seed':seed,'outcome':r['outcome'],'elapsed_ms':r['elapsed_ms'],'boss_hp_left':r['boss_remaining_hp'],'party_hp_left':sum(r['party_remaining_hp'].values())})
        summary[label]={'boss':bid,'credited_h':st.eco.credited_ms/3600000,'level':g.level_from_xp(st.eco.roster_xp['C_WITCH']),**summarize(rows)}
        print(label,summary[label]['wins'],len(rows),summary[label]['win_seconds_p50'],flush=True)
        write_json(RESULT/'PRIMARY_CHECKPOINT.json',{'summary':summary,'rows':raw})
    write_json(RESULT/'SCENARIOS.json',snapshotdata)
    st=scenarios['B_PROTECT_12H'][0];party=st.loadout();ablation={}
    for name,disabled in [('no_support',{'heal','ward','cover','counter','echo'}),('no_heal',{'heal','echo'}),('no_dot',{'poison'}),('no_chase',{'chase'}),('no_counter',{'counter'})]:
        rows=[Battle(party,LOCAL['bosses']['B_R01_B'],s,disabled=frozenset(disabled)).run() for s in seeds[:50]]
        ablation[name]={'disabled_for_diagnostic_only':sorted(disabled),**summarize(rows)}
        print('ablation',name,ablation[name]['wins'],flush=True)
    sensitivity=[]
    for hp_scale in [.9,1,1.1]:
        for power_scale in [.9,1,1.1]:
            boss=copy.deepcopy(LOCAL['bosses']['B_R01_B']);boss['hp']=round(boss['hp']*hp_scale);boss['power']=round(boss['power']*power_scale)
            rows=[Battle(party,boss,s).run() for s in range(2001,2051)]
            sensitivity.append({'hp_scale':hp_scale,'power_scale':power_scale,'hp':boss['hp'],'power':boss['power'],**summarize(rows)})
            print('sensitivity',hp_scale,power_scale,sensitivity[-1]['wins'],flush=True)
    timing=[]
    for mode in ['first_impact_at_interval','first_start_at_interval']:
        rows=[Battle(party,LOCAL['bosses']['B_R01_B'],s,timing_mode=mode).run() for s in range(3001,3051)]
        timing.append({'mode':mode,**summarize(rows)})
    craft_variance=[]
    for cseed in range(20):
        s=copy.deepcopy(st)
        for i in range(4):
            uid='craft:'+str(i);old=s.items[uid];s.items[uid]=g.create_item(uid,old.template_id,'Q2',seed='craft-variation-'+str(cseed),crafted=True)
        craft_party=s.loadout()
        rows=[Battle(craft_party,LOCAL['bosses']['B_R01_B'],bseed).run() for bseed in range(4001,4011)]
        craft_variance.append({'craft_seed':cseed,**summarize(rows)})
    trace=copy.deepcopy(st);r,receipt=trace.battle('B_R01_B',1001,True);before=trace.inventory_hash()
    if r['outcome']=='VICTORY':trace.commit_victory(receipt)
    after=trace.inventory_hash()
    if r['outcome']=='VICTORY':trace.commit_victory(receipt)
    evidence={'receipt':receipt,'before_hash':before,'after_hash':after,'repeat_commit_same_hash':trace.inventory_hash()==after,
              'gates_after':sorted(trace.gates),'boss_materials':{m:trace.eco.materials.get(m,0) for m in ('M_R01_BA','M_R01_BB')},
              'implicit_unlocks_not_granted':['awake1_requires_level12_and_cost','research2_requires_cost','attune2_requires_cost'],
              'note':'R3 credited time/materials + R2 paid crafting + actual R4 battle receipt. UI/intro/deep-area surveys remain explicit fixtures.'}
    write_json(RESULT/'GOLDEN_TREE_LOG.json',r)
    ra=Battle(intro.loadout(),LOCAL['bosses']['B_R01_A'],1001,True).run();write_json(RESULT/'GOLDEN_BOAR_LOG.json',ra)
    write_json(RESULT/'PROGRESSION_RECEIPT.json',evidence)
    enh=[]
    for tid in ['EQ_W_01','EQ_F_01','EQ_HAND_01','EQ_RING_01','EQ_BODY_01','EQ_FEET_01','EQ_AMU_01']:
        it=g.create_item('check:'+tid,tid,starter=True);points=[g.item_primary(it)]
        for k in range(3):it,_=g.enhance_item(it,'G_R01_A');points.append(g.item_primary(it))
        enh.append({'template_id':tid,'name':g.GEAR[tid]['name'],'plus0_to_plus3':points,'cumulative_cost':[0,5,15,30]})
    q2_bad=[]
    for s in range(1000):
        it=g.create_item('sample:'+str(s),'EQ_W_01','Q2',seed='craft-study',crafted=True)
        if set(a.affix_id for a in g.visible_affixes(it)).issubset({'AF_STATUS_RESIST','AF_DOT_RESIST'}):q2_bad.append(s)
    out={'boundary':'R01-first-clear reference only; R2/R3 unchanged; enemy/timing and intro-affix types local proposals. No real UI/device/retention validation.',
         'seeds':{'main':seeds,'sensitivity':[2001,2050],'timing':[3001,3050],'craft':[4001,4010]},
         'candidate_sha256':sha(LOCAL),'scenarios':summary,'ablations':ablation,'sensitivity':sensitivity,'timing_ambiguity':timing,'craft_variance':craft_variance,
         'enhancement_rounding':enh,'q2_crafted_wand_two_inactive_for_test_bosses':{'samples':1000,'count':len(q2_bad),'sample_indices':q2_bad[:20]},
         'primary_experiment_battles':len(raw),'diagnostic_battles':1000,'total_experiment_battles':len(raw)+1000,
         'golden_evidence_battles':2,'wall_seconds_on_this_machine':time.time()-t}
    write_json(RESULT/'EXPERIMENT_RESULTS.json',out)
    with (RESULT/'BATTLE_ROWS.csv').open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(raw[0]));w.writeheader();w.writerows(raw)
    print('DONE',out['total_experiment_battles'],time.time()-t,flush=True)
if __name__=='__main__':
    import argparse
    from datetime import datetime, timezone
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,help='Empty output directory; never overwrite the delivered evidence.')
    args=parser.parse_args()
    RESULT=args.output.resolve() if args.output else ROOT/'rerun_results'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    if RESULT.exists() and any(RESULT.iterdir()):
        parser.error('Output directory must be empty. Original results are preserved.')
    RESULT.mkdir(parents=True,exist_ok=True)
    main()
    print('Saved to:',RESULT)

