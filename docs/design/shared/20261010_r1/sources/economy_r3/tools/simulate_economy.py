"""Resource-preparation proxy and Monte Carlo loot experiment, NOT a battle/playtest.
The proxy assumes boss victories when hand-authored shopping lists + XP anchors are met.
Natural gear benefits/salvage are intentionally excluded from the preparation proxy.
"""
from collections import Counter, deque
from pathlib import Path
import json, math, csv
from fractions import Fraction
import numpy as np
import economy_model as e
ROOT=e.ROOT

def mult(ops,n):return [(x,n) for x in ops]
def enh(a,b,n):return [(f'ENHANCE_{v}',n) for v in range(a,b+1)]
def aw(n):return [(f'AW_{a}_{n}',1) for a in e.ACTORS]
base=mult(['RC_EQ_BODY_01','RC_EQ_HAND_01','RC_EQ_FEET_01','RC_EQ_RING_01'],3)+[('RC_EQ_AMU_01',4)]+mult(['RC_EQ_F_BODY_01','RC_EQ_F_HAND_01','RC_EQ_F_FEET_01','RC_EQ_F_RING_01'],1)
STAGES=[
 (6,[]),
 (12,base+enh(1,3,24)),
 (18,[('RS_THEORY_2',1)]+aw(1)+[('ATTUNE_1_2',12)]+enh(4,5,12)+[('QUALITY_Q0_Q1',3),('QUALITY_Q1_Q2',3)]),
 (24,[('ATTUNE_1_2',12)]+enh(4,5,12)+mult(['RC_EQ_W_P1','RC_EQ_F_02'],1)+[('RC_EQ_BODY_02',3),('RC_EQ_AMU_02',4)]),
 (30,[('RS_THEORY_3',1),('ATTUNE_2_3',12),('RC_EQ_A_02',1)]+enh(6,7,12)),
 (36,[('ATTUNE_2_3',12)]+enh(6,7,12)+mult(['RC_EQ_HAND_02','RC_EQ_FEET_02','RC_EQ_RING_02'],3)),
 (42,[('RS_THEORY_4',1)]+aw(2)+[('ATTUNE_3_4',12),('RC_EQ_S_02',1)]+enh(8,9,12)),
 (48,[('ATTUNE_3_4',12)]+enh(8,9,12)+mult(['RC_EQ_BODY_03','RC_EQ_FEET_03','RC_EQ_RING_03'],3)),
 (54,[('RS_THEORY_5',1),('ATTUNE_4_5',12)]+enh(10,10,12)),
 (60,[('ATTUNE_4_5',12)]+enh(10,10,12)+mult(['RC_EQ_W_P2','RC_EQ_A_03','RC_EQ_S_03','RC_EQ_F_03'],1)+[('RC_EQ_HAND_03',3)])]
# Explicit scripted fixture, not required shopping lists before actual boss challenges.
ROWS=[]
for idx,(level,ops) in enumerate(STAGES):
 gate='G_START' if idx==0 else f'G_R{(idx+1)//2:02}_'+('A' if idx%2 else 'B')
 output=f'G_R{idx//2+1:02}_'+('A' if idx%2==0 else 'B')
 mats,dust=e.aggregate_cost(ops)
 for mid in mats:
  src=next(s for s in e.SOURCES.values() if s['material_id']==mid)
  assert src['available_gate'] in e.closure(gate),(idx,mid,gate)
 for oid,n in ops:assert e.COSTS[oid]['gate'] in e.closure(gate),(idx,oid,gate)
 ROWS.append({'index':idx,'available_gate':gate,'assumed_clear_gate':output,'xp_anchor_level':level,'operations':[{'id':i,'count':n} for i,n in ops],'materials':mats,'dust':dust})
(ROOT/'data/PREPARATION_FIXTURE_NOT_BATTLE.json').write_text(json.dumps({'boundary':'Shop-list/resource readiness fixture; boss win is ASSUMED; full 24-slot strengthening is not a gameplay gate; natural gear and salvage excluded.','stages':ROWS},ensure_ascii=False,indent=2)+'\n')

def run_prep(interval_hours=8,bonus=False,work_seconds=300):
    mats=Counter(e.CFG['onboarding']['materials']);dust=e.CFG['onboarding']['dust_total'];xp=e.CFG['onboarding']['xp_total']
    earned_dust=earned_xp=spent_dust=0;spent=Counter();stage=0;times=[];costhist=[];t=0;work=0;source_progress=Counter();offerwork=ox=od=0;offers=[];ad_x=ad_d=0;rest_units=0
    queue=deque();survey=Counter();max_seconds=120*86400
    def ready():return xp>=e.xp_threshold(ROWS[stage]['xp_anchor_level']) and dust>=ROWS[stage]['dust'] and all(mats[k]>=v for k,v in ROWS[stage]['materials'].items())
    while stage<len(ROWS) and t<=max_seconds:
        # At login only. Resource readiness is not used to claim actual combat wins.
        while stage<len(ROWS) and ready():
            row=ROWS[stage];dust-=row['dust'];spent_dust+=row['dust'];mats.subtract(row['materials']);spent.update(row['materials'])
            assert min(mats.values(),default=0)>=0 and dust>=0
            times.append({'gate':row['assumed_clear_gate'],'hours':t/3600,'level':e.level_from_xp(xp),'dust_after':dust,'stock_total':sum(mats.values())})
            boss=f"B_R{stage//2+1:02}_{'A' if stage%2==0 else 'B'}";src=next(s for s in e.SOURCES.values() if s['enemy_id']==boss);mats[src['material_id']]+=1
            costhist.append(row);stage+=1
        if stage==len(ROWS):break
        row=ROWS[stage];jobs=e.goal_units(row['materials'],dict(mats),dict(source_progress));queue=deque()
        for job in jobs:queue.extend([job['source_id']]*job['units'])
        region=f'R{stage//2+1:02}';gs=e.closure(row['available_gate']);pool=sorted(s['id'] for s in e.SOURCES.values() if s['region_id']==region and s['source_type']!='boss' and s['available_gate'] in gs)
        real_s=interval_hours*3600;credited_s=min(real_s,172800);count=int(credited_s//work_seconds);rest_units+=int((real_s-credited_s)//work_seconds)
        for _ in range(count):
            if queue:s=e.SOURCES[queue.popleft()]
            else:
                idx=survey[region]%len(pool);s=e.SOURCES[pool[idx]];survey[region]+=1
            rate=e.RATES[s['region_id']];x,d=rate['xp_per_work'],rate['dust_per_work'];xp=min(e.xp_threshold(60),xp+x);dust+=d;earned_xp+=x;earned_dust+=d;work+=1
            source_progress[s['id']]+=1
            if source_progress[s['id']]>=s['work_units_per_yield']:
                source_progress[s['id']]-=s['work_units_per_yield'];mats[s['material_id']]+=1
            offerwork+=1;ox+=x;od+=d
            if offerwork==96:
                if len(offers)<6:offers.append((ox//16,od//16))
                offerwork=ox=od=0
        t+=real_s
        if bonus:
            for x,d in offers:xp=min(e.xp_threshold(60),xp+x);dust+=d;ad_x+=x;ad_d+=d
            offers=[]
    return {'login_interval_h':interval_hours,'bonus':bonus,'supply_work_seconds':work_seconds,'completed_resource_stages':stage,'elapsed_days':round(t/86400,6),'credited_hours':work*work_seconds/3600,'uncredited_hours':rest_units*work_seconds/3600,'milestones':times,'earned_base_xp':earned_xp,'earned_base_dust':earned_dust,'spent_dust':spent_dust,'ad_xp':ad_x,'ad_dust':ad_d,'ending_dust':dust,'spent_materials':dict(spent),'loot_not_used_in_budget':work//6,'actual_combat_evaluated':False}

def loot_mc(n=2000,days=90,seed=20261009):
    rng=np.random.default_rng(seed);draws=days*48;miss=np.zeros(n,dtype=int);first=np.zeros(n,dtype=int);legend=np.zeros(n,dtype=int);good=np.zeros(n,dtype=int)
    desired='EQ_W_P2';ss=e.snapshot('R05','G_R05_B',discovered=tuple(k for k,t in e.TEMPLATES.items() if t['parent_template_id']))
    pool=e.eligible_templates(ss);local=[x for x in e.CFG['regional_gear_theme_pools']['R05'] if x in pool]
    aff=[]
    for a in e.GROWTH['affixes']:
        if a['actor_capability']=='all' or 'C_WITCH' in a['actor_capability']:aff.append(a['affix_id'])
    # Count-only Monte Carlo: choose rarity, desired form and visible desired-affix matches.
    N=len(aff);desired_count=3 # AF_DOT, AF_CDR, AF_POWER
    checkpoints={};initial_8h_quality=None
    for i in range(1,draws+1):
        u=rng.integers(0,10000,n);q=np.select([u<4500,u<7500,u<9300,u<9900],[0,1,2,3],default=4)
        q=np.where(miss>=99,4,q);miss=np.where(q==4,0,miss+1);legend+=q==4
        first=np.where((first==0)&(q==4),i,first)
        if i%6==0:is_target=np.ones(n,dtype=bool)
        else:
            p=.6/len(local)+.4/len(pool)
            is_target=rng.random(n)<p
        # Uniform sampling without replacement of three latent groups; revealed prefix 2 for Q2.
        wanted_left=np.full(n,desired_count);hits2=np.zeros(n,dtype=int);hits3=np.zeros(n,dtype=int)
        for j in range(3):
            h=rng.random(n)<wanted_left/(N-j);wanted_left-=h;hits3+=h
            if j<2:hits2+=h
        acceptable=is_target&(((q==2)&(hits2>=2))|((q>=3)&(hits3>=2)))
        good=np.where((good==0)&acceptable,i,good)
        if i in [16,48,96,336,1440,4320]:
            checkpoints[str(i)]={'hours':i/2,'mean_legends':float(legend.mean()),'any_legend_probability':float((legend>0).mean()),'two_desired_visible_probability':float((good>0).mean())}
    def qtiles(a):
        found=a[a>0]/48
        return {'censor_days':days,'observed_fraction':float((a>0).mean()),'days_p10':float(np.quantile(found,.1)) if len(found) else None,'days_p50':float(np.quantile(found,.5)) if len(found) else None,'days_p90':float(np.quantile(found,.9)) if len(found) else None}
    exact_mean=(1-.99**100)/.01
    return {'samples':n,'days':days,'seed':seed,'generator':'NumPy PCG64 distribution experiment, separate from game SHA256 counter vectors','natural_rolls_per_day':48,'max_level_full_discovery_fixture':True,'desired_template':desired,'eligible_template_count':len(pool),'local_pool_count':len(local),'affix_pool_count':N,'good_condition':'Q2 has 2 visible desired groups, or Q3/Q4 has >=2 of DOT/CDR/POWER among 3 visible; no q requirement; NOT a perfect build','condition_two_visible':qtiles(good),'first_legend':qtiles(first),'checkpoints':checkpoints,'exact_first_legend_expected_rolls':exact_mean,'exact_first_legend_expected_hours':exact_mean/2,'exact_pity_effective_rate':1/exact_mean,'reforge_and_crafting_excluded':True,'natural_full_triplet_q800_probability_per_target_roll_no_pity_mix':((.06+.01)*((201/1001)**3))/math.comb(N,3)}

def main():
    results=[run_prep(h,b) for h,b in [(8,False),(8,True),(24,False),(24,True),(48,False),(72,False)]]
    sensitivity=[run_prep(24,False,sec) for sec in [400,300,240]]
    mc=loot_mc()
    out={'boundary':e.CFG['simulation_boundary'],'preparation_profiles':results,'sensitivity_work_period':sensitivity,'loot_monte_carlo':mc}
    (ROOT/'validation/SIMULATION_RESULTS.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
    rows=[]
    for r in results:
        rows.append({k:r[k] for k in ['login_interval_h','bonus','elapsed_days','completed_resource_stages','credited_hours','uncredited_hours','ad_xp','ad_dust']})
    with (ROOT/'data/preparation_scenarios.csv').open('w',encoding='utf-8-sig',newline='') as f:
        wr=csv.DictWriter(f,fieldnames=list(rows[0]));wr.writeheader();wr.writerows(rows)
    print(json.dumps(rows,ensure_ascii=False,indent=2));print(json.dumps(mc,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
