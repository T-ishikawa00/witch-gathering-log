"""Rarity/catalog design probes. No purchase, app, server or persistent save code.
Reads unmodified reference files in source/. Does not write them or contact network.
"""
from __future__ import annotations
from pathlib import Path
from dataclasses import asdict
from functools import partial
from unittest.mock import patch
import sys,json,copy,hashlib
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'source/integration_r1/tools'))
import bridge as b
import precision_rules
from precision_rules import PrecisionRules
RARITY=json.loads((ROOT/'data/RARITY_CANDIDATES.json').read_text())
CATALOG=json.loads((ROOT/'data/PRODUCT_CATALOG.json').read_text())
PRODUCTS={p['id']:p for p in CATALOG['products']}
MODELS={k:tuple(v) for k,v in RARITY['models'].items()}

def digest(x):return hashlib.sha256(json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()

class RarityRules(PrecisionRules):
    def __init__(self,base,scale=10000,*,multipliers=MODELS['H0_EXISTING']):
        super().__init__(base,scale)
        if len(multipliers)!=5 or min(multipliers)<=0:raise ValueError('Bad rarity table')
        self.multipliers=tuple(multipliers)
    def item_primary(self,item):
        self.base.validate_item(item)
        r=self.base.RANKS[item.rank]['multiplier_bp'];enh=10000+300*item.enhancement
        q=self.multipliers[int(item.quality[1:])]
        return {s:v*r*enh*q*self.scale//10**12 for s,v in self.base.GEAR[item.template_id]['item_stat_budget'].items()}

def battle_with_rarity(state,seed,model,record=False):
    """Temporary constructor substitution in a single-threaded isolated process.
    No source edits, no changes to the R6 policy, original damage/AI logic retained.
    H0 is checked against unmodified R6. Do not use this test seam in production.
    """
    ms=MODELS[model]
    with patch.object(precision_rules,'PrecisionRules',partial(RarityRules,multipliers=ms)):
        combat=b.FinalBattleR6(state.loadout(),b.boss_variant('redistribute_pause'),seed,record=record)
        combat.input_fingerprint=digest({'original':combat.input_fingerprint,'rarity_model':model,'multipliers':ms})
        out=combat.run()
    out['rarity_model']=model;out['rarity_multipliers_bp']=ms
    return out

def prepare_case(case,seed):
    kind='fresh' if case=='JOINED_C50' else 'protect'
    state=b.build_state(kind,6,'catalog-fixture-'+str(seed))
    b.recommend_equipment(state);b.spend_for_enhancement(state,'baseline')
    if case!='SIX_HOUR_NO_GACHA':
        draws=b.DrawBridge(b.C,'catalog-draw-'+str(seed),state).draw(50)
        b.accept_draws(state,draws,'probe50')
        # Freeze the same H0 noninferior selection for ALL candidate models;
        # the experiment is conditional on this loadout, not best-equipment play.
        b.recommend_equipment(state)
    return state

def offered_products_for_budget_label(label):
    # Audience names are analytic labels, not eligibility inputs.
    return tuple(sorted(PRODUCTS))

def plan_projection(purchases:list[tuple[str,int]],horizon_days:int):
    """Deterministic allowance schedule for hypothetical verified purchases.
    Day 0 inclusive purchases; horizon end excludes new purchase at that day.
    DELVERY30 earns 1/day after 24h, independent of login; no receipt validation.
    """
    if type(horizon_days)!=int or horizon_days<0:raise ValueError('horizon')
    for pid,day in purchases:
        if pid not in PRODUCTS or type(day)!=int or day<0:raise ValueError('unknown product/day')
    eligible=[(pid,day) for pid,day in purchases if day<horizon_days]
    used={};owned=set();spent=0;granted=0;scheduled=0;score=0;ad=False
    history=[]
    for pid,day in sorted(eligible,key=lambda x:x[1]):
        p=PRODUCTS[pid];prev=used.get(pid,[])
        if p['purchase_limit']=='once' and prev:raise ValueError('duplicate once-only purchase')
        if p['purchase_limit'] in ('cooldown','no_overlap') and prev and day-prev[-1]<p['cadence_days']:
            raise ValueError('purchase window violation')
        used.setdefault(pid,[]).append(day);spent+=p['price_jpy']
        if pid=='DELIVERY30':
            n=max(0,min(30,horizon_days-day));granted+=n;scheduled+=30-n
        else:n=p['tickets'];granted+=n
        if p['type_candidate']=='non_consumable':owned.add(pid)
        if pid=='AD_SKIP':ad=True
        score+=p.get('power_score_if_separately_approved',0)
        history.append({'id':pid,'day':day,'tickets_earned_at_horizon':n})
    return {'days':horizon_days,'spend_jpy':spent,'tickets_from_products':granted,'tickets_remaining_scheduled':scheduled,'owned':sorted(owned),'ad_skip':ad,'living_score_if_approved':min(100,score),'bp_if_approved_without_free_progression':min(100,score)*3,'purchase_events':history}

def repeat(pid,days):return [(pid,t) for t in range(0,days,30)]

def personas(days):
    allcos=[p['id'] for p in PRODUCTS.values() if any(x in p['purposes'] for x in ['outfit','home'])]
    return {
      'FREE_NO_AD':([],False), 'FREE_OPTIONAL_AD':([],True),
      'AD_ONLY':([('AD_SKIP',0)],True), 'ONE_SMALL_PURCHASE':([('STARTER',0)],False),
      'VALUE_PACK_ONLY':(repeat('VALUE30',days),False),
      'DELIVERY_ONLY':(repeat('DELIVERY30',days),False),
      'VALUE_PLUS_DELIVERY':(repeat('VALUE30',days)+repeat('DELIVERY30',days),False),
      'ONE_OUTFIT':([('OUT_C_WITCH_MOON_01',0)],False),
      'TWO_FURNITURE':([('FUR_MOON_LIGHT',0),('FUR_MOON_PLANT',0)],False),
      'ALL_CURRENT_COSMETICS':([(p,0) for p in allcos],False),
      'REGULAR_100_PER_30D':([(p,t) for t in range(0,days,30) for p in ['TICKET50','TICKET50']],False),
      'HIGH_BUDGET_400_PER_30D':([(p,t) for t in range(0,days,30) for p in ['TICKET200','TICKET200']],False),
      'COMFORT_OUTFIT_VALUE':([('AD_SKIP',0),('OUT_C_WITCH_MOON_01',0)]+repeat('VALUE30',days)+repeat('DELIVERY30',days),True)
    }

def top_expectation(n:int,p=.01,pity=100):
    """Renewal expectation; Q3 guarantee doesn't change Q4 hazard."""
    f=[0.]+[p*(1-p)**(k-1) for k in range(1,pity)]+[(1-p)**(pity-1)]
    e=[0.]*(n+1);cdf=0.
    for t in range(1,n+1):
        if t<=pity:cdf+=f[t]
        e[t]=cdf+sum(f[k]*e[t-k] for k in range(1,min(t,pity)+1))
    return e[n]

if __name__=='__main__':
    print('Design model only. Run run_analysis.py or test_model.py.')
