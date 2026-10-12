"""Deterministic rarity/cost comparison. Standard library; no network or real purchases.
Not a game simulator: no R6 combat, crafting decisions, receipt validation, or revenue.
"""
from __future__ import annotations
from dataclasses import dataclass
from collections import defaultdict
from pathlib import Path
import argparse, csv, json, math, random, statistics

ROOT=Path(__file__).resolve().parents[1]
@dataclass(frozen=True)
class Candidate:
    id:str
    name:str
    probability_bp:tuple[int,...]
    yen_equivalent_per_pull:int
    free_pulls_per_day:int
    top_pity:int
    mid_pity:int
    target_probability_bp:int=5000
    def __post_init__(self):
        if len(self.probability_bp)!=5 or sum(self.probability_bp)!=10000 or min(self.probability_bp)<0:
            raise ValueError('Expected five non-negative probabilities summing to 10000bp.')
        if min(self.yen_equivalent_per_pull,self.free_pulls_per_day,self.top_pity,self.mid_pity)<1:
            raise ValueError('Positive prices/counts required.')
        if not 0<=self.target_probability_bp<=10000:raise ValueError('Bad target probability.')

@dataclass(frozen=True)
class Counters:
    top_miss:int=0
    mid_miss:int=0
    force_target:bool=False

def candidates()->list[Candidate]:
    cfg=json.loads((ROOT/'data/CANDIDATES_R3.json').read_text())
    fields=set(Candidate.__dataclass_fields__)
    return [Candidate(**{k:(tuple(v) if k=='probability_bp' else v) for k,v in d.items() if k in fields}) for d in cfg['candidates']]

def step(c:Candidate,s:Counters,quality_roll:int,target_roll:int)->tuple[int,bool,Counters]:
    """0..9999 rolls, high-end ordered cumulative interval; matches previous R2."""
    if not(0<=quality_roll<10000 and 0<=target_roll<10000):raise ValueError('Bad roll')
    if not(0<=s.top_miss<c.top_pity and 0<=s.mid_miss<c.mid_pity):raise ValueError('Bad counters')
    if s.top_miss==c.top_pity-1:q=4
    else:
        cumulative=0;q=0
        for k in range(4,-1,-1):
            cumulative+=c.probability_bp[k]
            if quality_roll<cumulative:q=k;break
        if q<3 and s.mid_miss==c.mid_pity-1:q=3
    selected=(q==4 and s.force_target) or target_roll<c.target_probability_bp
    ns=Counters(0 if q==4 else s.top_miss+1,
                0 if q>=3 else s.mid_miss+1,
                (not selected) if q==4 else s.force_target)
    return q,selected,ns

def first_top_pmf(c:Candidate)->list[float]:
    p=c.probability_bp[4]/10000
    return [p*(1-p)**i for i in range(c.top_pity-1)]+[(1-p)**(c.top_pity-1)]

def selected_top_pmf(c:Candidate)->list[float]:
    """First top selected with t, otherwise second top guaranteed. Float arithmetic."""
    first=first_top_pmf(c);t=c.target_probability_bp/10000
    out=[0.]*(2*c.top_pity)
    for i,x in enumerate(first):
        out[i]+=t*x
        for j,y in enumerate(first):out[i+j+1]+=(1-t)*x*y
    return out

def quantile(pmf:list[float],p:float)->int:
    if not 0<p<=1:raise ValueError('Quantile needs 0<p<=1')
    total=0.
    for i,m in enumerate(pmf,1):
        total+=m
        if total>=p-1e-11:return i
    raise ArithmeticError('Distribution incomplete')

def quality_horizons(c:Candidate,horizons:list[int])->dict[int,dict]:
    """Finite state DP. Top and mid counters, with conditional low-quality promotion.
    Returns expected item counts including pity, not a Monte Carlo mean.
    """
    if any(n<0 for n in horizons):raise ValueError('Negative horizon')
    wanted=set(horizons);result={};counts=[0.]*5;states={(0,0):1.}
    if 0 in wanted:result[0]={'draws':0,'expected_quality_counts':counts.copy(),'probability_mass':1.}
    probs=[x/10000 for x in c.probability_bp];low=sum(probs[:3])
    for n in range(1,max(horizons,default=0)+1):
        nxt=defaultdict(float)
        for (hi,mid),mass in states.items():
            if hi==c.top_pity-1:
                counts[4]+=mass;nxt[0,0]+=mass;continue
            p4=probs[4];p3=(1-p4) if mid==c.mid_pity-1 else probs[3]
            counts[4]+=mass*p4;counts[3]+=mass*p3
            if p4:nxt[0,0]+=mass*p4
            if p3:nxt[hi+1,0]+=mass*p3
            if mid<c.mid_pity-1 and low:
                for q in range(3):counts[q]+=mass*probs[q]
                nxt[hi+1,mid+1]+=mass*low
        states=nxt
        if n in wanted:
            result[n]={'draws':n,'expected_quality_counts':counts.copy(),'probability_mass':sum(states.values())}
    return result

def no_rare_probability(c:Candidate,draws:int)->float:
    """No Q2+ from empty counters. Mid/top guarantees can make this zero."""
    if draws<0:raise ValueError('Negative draws')
    if draws>=min(c.top_pity,c.mid_pity):return 0.
    return ((c.probability_bp[0]+c.probability_bp[1])/10000)**draws

def simulate_selected(c:Candidate,samples:int,seed:int)->dict:
    rng=random.Random(seed);hist=[0]*(2*c.top_pity);totalpulls=0
    # Independent per-pull Bernoulli sampling; mid pity does not alter Q4 hazard.
    for _ in range(samples):
        miss=0;forced=False
        for n in range(1,2*c.top_pity+1):
            top=(miss==c.top_pity-1 or rng.randrange(10000)<c.probability_bp[4])
            if not top:miss+=1;continue
            miss=0
            if forced or rng.randrange(10000)<c.target_probability_bp:
                hist[n-1]+=1;totalpulls+=n;break
            forced=True
        else:raise AssertionError('Pity failed')
    pmf=selected_top_pmf(c);emp=exact=0.;err=0.
    for observed,p in zip(hist,pmf):
        emp+=observed/samples;exact+=p;err=max(err,abs(emp-exact))
    return {'sample_count':samples,'seed':seed,'total_mock_pulls':totalpulls,'sample_mean':totalpulls/samples,'analytic_mean':sum((i+1)*p for i,p in enumerate(pmf)), 'max_cdf_absolute_difference':err,'histogram':hist}

def analyze()->dict:
    output=[]
    for index,c in enumerate(candidates()):
        pmf=selected_top_pmf(c);mean=sum((i+1)*m for i,m in enumerate(pmf));one=sum((i+1)*m for i,m in enumerate(first_top_pmf(c)))
        budgetdraws=1500//c.yen_equivalent_per_pull
        h=quality_horizons(c,sorted({c.free_pulls_per_day,budgetdraws,c.free_pulls_per_day*30}))
        counts=h[budgetdraws]['expected_quality_counts']
        # Long-run high-grade reset: age distribution since Q3 or Q4, with top pity
        # overridden. Daily low-grade mean below uses the actual first 30-day DP.
        daycounts=[x/30 for x in h[c.free_pulls_per_day*30]['expected_quality_counts']]
        dust=[]
        for q0,q1 in [(1,2),(2,5),(5,10)]:
            add=daycounts[0]*q0+daycounts[1]*q1
            budgetadd=counts[0]*q0+counts[1]*q1
            dust.append({'hypothetical_scrap_yield_Q0':q0,'hypothetical_scrap_yield_Q1':q1,
                         'free_daily_additional_powder_30day_average':add,'ratio_to_R3_forest_144_per_day':add/144,
                         'powder_from_1500yen_batch_low_only':budgetadd,
                         'forest_hours_equivalent_at12_per_hour':budgetadd/12,
                         'note':'Sensitivity only. Assumes ALL new low grades voluntarily scrapped, no investment refunds, no high-grade recycling, no new official salvage rule.'})
        output.append({'id':c.id,'name':c.name,'input':c.__dict__,'first_top_mean_pulls':one,
                       'selected_top_mean_pulls':mean,'selected_top_mean_yen_equivalent':mean*c.yen_equivalent_per_pull,
                       'selected_top_percentiles_pulls':{str(p):quantile(pmf,p) for p in [.5,.9,.95,.99]},
                       'selected_top_max_pulls':2*c.top_pity,'selected_top_max_yen_equivalent':2*c.top_pity*c.yen_equivalent_per_pull,
                       'selected_top_mean_free_days_continuous_equivalent':mean/c.free_pulls_per_day,
                       'selected_top_max_free_days_continuous_equivalent':2*c.top_pity/c.free_pulls_per_day,
                       'budget1500':{'draws':budgetdraws,'unspent_yen':1500% c.yen_equivalent_per_pull,
                                     'expected_quality_counts':counts,'expected_Q2plus':sum(counts[2:]),'expected_Q3plus':sum(counts[3:]),
                                     'probability_selected_top_by_budget':sum(pmf[:budgetdraws])},
                       'probability_no_Q2plus_in10_from_empty':no_rare_probability(c,10),
                       'horizons':h,'low_grade_powder_sensitivity':dust,
                       'sampling_crosscheck':simulate_selected(c,20000,261010+index),
                       'selected_top_pmf':pmf})
    natural=Candidate('NATURAL_CONTEXT','自然ドロップ旧R3の会話記録・別経路',(4500,3000,1800,600,100),1,48,100,100000)
    first=first_top_pmf(natural);one=sum((i+1)*p for i,p in enumerate(first))
    return {'status':'RESEARCH_AND_MATH_ONLY_NOT_FINAL_ECONOMY','date':'2026-10-10','candidates':output,
            'baseline_natural_context':{'source':'Prior R3 parameter statements and unchanged commerce R2 report; original R3 runner unavailable.',
                                       'gear_per_day_at24h':48,'base_Q4_probability':.01,'Q4_pity':100,
                                       'mean_first_top_pulls':one,'longrun_Q4_per_day_at24h':48/one,'forest_powder_per_day':144,
                                       'no_combined_gameplay_simulation':True},
            'preserved_rules':['4 characters fully automatic; no manual tactics','No characters/costumes/furniture in equipment pool','R2 quality/evolution/type distinction','Same purchased/free odds and batch/sequential logic','Gate + first-crafted evolution eligibility and item protection remain required, not implemented in this math module'],
            'limits':['No competitor live play or verified live 2026 odds','No controlled user study of enjoyment or willingness to pay','No server/StoreKit/real refund tests','No R6 battle regression','No complete crafting/salvage or 30/90-day progression simulation','Candidate C changes generosity as well as rarity; cannot attribute improvement to commons alone','Money values are hypothetical per-pull pack equivalents, not published IAP prices or revenue estimates']}

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    if (args.output/'ANALYSIS_R3.json').exists():parser.error('Refuse to overwrite existing evidence; choose a new folder.')
    data=analyze();(args.output/'ANALYSIS_R3.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    rows=[]
    for d in data['candidates']:
        b=d['budget1500'];row={'candidate':d['id'],'name':d['name'],'yen_per_pull':d['input']['yen_equivalent_per_pull'],
        'free_per_day':d['input']['free_pulls_per_day'],'pulls_for_1500':b['draws'],'Q4_expected_for_1500':b['expected_quality_counts'][4],
        'selected_Q4_chance_for1500':b['probability_selected_top_by_budget'],'mean_selected_Q4_yen':d['selected_top_mean_yen_equivalent'],
        'max_selected_Q4_yen':d['selected_top_max_yen_equivalent'],'Q2plus_expected_for1500':b['expected_Q2plus'],'no_Q2plus_in10':d['probability_no_Q2plus_in10_from_empty']}
        rows.append(row)
        print(row)
    with (args.output/'COST_COMPARISON.csv').open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    print('Output:',args.output)
if __name__=='__main__':main()
