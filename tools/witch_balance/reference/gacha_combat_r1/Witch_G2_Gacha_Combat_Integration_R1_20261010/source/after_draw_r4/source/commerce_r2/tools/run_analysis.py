"""Math-only checks for proposed gacha, purchase value and production footprint.
R6 combat and economic spending choices are deliberately not simulated.
"""
from commerce_model import *
from pathlib import Path
import argparse,json,random,statistics,math

def top_expected_in_horizon(n,p,limit):
    dist=[1.]+[0.]*(limit-1);expect=0.
    for _ in range(n):
        nxt=[0.]*limit
        for miss,m in enumerate(dist):
            q=1. if miss==limit-1 else p;expect+=m*q;nxt[0]+=m*q
            if q<1:nxt[miss+1]+=m*(1-q)
        dist=nxt
    return expect

def analyze():
    target=target_top_distribution()
    alt=[]
    for p,cap in [(.02,40),(.03,30),(.03,40),(.03,50),(.05,40)]:
        a=target_top_distribution(p,cap);e=(1-(1-p)**cap)/p
        alt.append({'base_q4_probability':p,'top_pity':cap,'mean_first_top':e,'q4_stationary_rate':1/e,
          'mean_selected_top':a['mean'],'p50_selected_top':a['percentiles']['0.5'],'p95_selected_top':a['percentiles']['0.95'],
          'max_selected_top':a['maximum'],'selected_cost_jpy_at150_all_paid':a['mean']*150})
    # Bounded reproducible sampling to cross-check analytic distribution, not production RNG.
    rng=random.Random(261010);samples=[]
    for _ in range(50000):
        pity=Pity()
        for n in range(1,81):
            q,t,_=pity.resolve(rng.randrange(10000),rng.randrange(10000),rng.randrange(10000),'target',('target','other'))
            if q=='Q4' and t=='target':samples.append(n);break
    hist={n:samples.count(n)/len(samples) for n in range(1,81)}
    empirical_cdf=0.;exact_cdf=0.;maxerr=0.
    for n in range(1,81):empirical_cdf+=hist[n];exact_cdf+=target['pmf'][n-1];maxerr=max(maxerr,abs(empirical_cdf-exact_cdf))
    supply=[]
    for days,clears,paid in [(30,0,0),(30,2,0),(30,5,0),(30,5,10),(30,5,20),(30,5,40),(90,5,0)]:
        tickets=days+10+clears*5+paid
        supply.append({'days_after_gacha_unlock':days,'first_region_boss_clears_assumed':clears,'paid_tickets_assumed':paid,'total_tickets':tickets,
          'earnings_conditions':'all accrued tickets claimed before 7-day cap; no predicted clear times','gacha_expected':quality_horizon(tickets),
          'natural_q4_expected_if_24h_per_day_same_R3_rate':top_expected_in_horizon(days*48,.01,100),
          'note':'natural R3 rates taken from conversation; not executed with missing R3 runner. Distinct reward channels.'})
    price=[{'price_per_ticket_candidate':p,'ten_tickets':10*p,'mean_cost_selected_top_all_paid_no_start_pity':p*target['mean'],
            'max_cost_selected_top_all_paid_no_start_pity':80*p} for p in [100,150,200]]
    living=[]
    for clears in range(6):
        for outfits,furniture in [(0,0),(1,0),(1,5),(4,10)]:
            score=min(100,clears*20+outfits*20+furniture*2)
            living.append({'region_boss_clears':clears,'outfits_owned':outfits,'furniture_owned':furniture,'score':score,'additive_bp':score*3})
    proof={'outfit_context_cells':PRODUCTION['rollout_hypothesis']['outfit_context_action_cells'],
           'weapon_templates':sum(t['slot']=='weapon' for t in GEAR.values()),'look_weapon_pairs':2*sum(t['slot']=='weapon' for t in GEAR.values()),
           'first_proof_cells':2*2*(7+3+1),'not_images_or_hours':True}
    memory={'formula':'width*height*4 bytes per RGBA8 decoded texture, excluding GPU copies/mips/metadata',
            'one_512_rgba_mib':512*512*4/2**20,'120_512_rgba_mib':120*512*512*4/2**20,
            'seven_24frame_clips_per_outfit_mib':7*24*512*512*4/2**20,
            'four_active_outfits_naive_full_decode_mib':4*7*24*512*512*4/2**20,
            'not_device_observation':True}
    return {'status':'PROPOSED_REFERENCE_RULES_TESTED_NOT_PRODUCTION_ACCEPTANCE','target_first_distribution':target,'candidates':alt,
      'simulation_cross_check':{'seed':261010,'sample_count':len(samples),'total_mock_pulls':sum(samples),'observed_mean':statistics.mean(samples),'exact_mean':target['mean'],'max_cdf_absolute_error':maxerr,'support_min':min(samples),'support_max':max(samples)},
      'quality_horizons':[quality_horizon(n) for n in [1,10,20,40,50,65,80,115,1000]],
      'supply_scenarios':supply,'price_sensitivity':price,'living_scenarios':living,'production_arithmetic':proof,'memory_arithmetic':memory,
      'product_price_sum_jpy_proposal':{'four_outfits':sum(x['price_jpy_proposal'] for x in LIVING['outfits']),'ten_furniture_individuals':sum(x['price_jpy_proposal'] for x in LIVING['furniture'])},
      'limitations':['not human purchase demand','not R6 combat or 30/90 day game-clear simulation','mock receipts not cryptographic checks','not server concurrency/real crash persistence','not actual new art/device testing','not legal approval']}

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=ROOT/'results/ANALYSIS_RESULTS_R2.json');args=parser.parse_args()
    data=analyze();args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    print('mean first selected Q4:',data['target_first_distribution']['mean']);print('percentiles:',data['target_first_distribution']['percentiles'])
    print('simulation:',data['simulation_cross_check']);print('quality horizon65:',next(x for x in data['quality_horizons'] if x['draws']==65))
    print('prices:',data['product_price_sum_jpy_proposal']);print('Saved:',args.output)
