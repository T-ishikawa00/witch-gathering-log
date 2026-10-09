"""Specification reference ONLY. No real payments, network, production RNG or saves.

Implements the proposed R2 commercial rules with frozen test catalogs. Uses mock
receipts and deterministic/hash RNG for reproducibility, NOT cryptographic IAP
verification or secure paid draws. External combat/economy R2-R6 is not present.
"""
from __future__ import annotations
from dataclasses import dataclass, field, asdict
from copy import deepcopy
from pathlib import Path
from fractions import Fraction
from hashlib import sha256
from collections import defaultdict
from typing import Callable
import json

ROOT=Path(__file__).resolve().parents[1]
GACHA=json.loads((ROOT/'data/GACHA_CANDIDATE.json').read_text())
GEAR={x['id']:x for x in json.loads((ROOT/'data/GEAR_METADATA_AND_NEW_AFFIX_PROPOSAL.json').read_text())['items']}
LIVING=json.loads((ROOT/'data/PRODUCT_AND_LIVING_CANDIDATE.json').read_text())
PRODUCTS={x['id']:x for x in LIVING['outfits']+LIVING['furniture']}
PRODUCTION=json.loads((ROOT/'data/PRODUCTION_CONTRACT.json').read_text())
ALL_ACTORS=('C_WITCH','C_APPRENTICE','C_SMITH','C_FAMILIAR')
BOSSES=tuple(GACHA['free_supply']['region_boss_ids'])
DAY=86400

class Rejected(ValueError): pass

def digest(v):
    def default(x):
        if isinstance(x,set):return sorted(x)
        raise TypeError(type(x).__name__)
    return sha256(json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(',',':'),default=default).encode()).hexdigest()

def fixture_roll(secret:str,kind:str,seq:int,n:int)->int:
    # modulo/hash here is test data, not an approved production generator.
    return int(digest([secret,kind,seq]),16)%n

@dataclass
class Pity:
    top_miss:int=0
    mid_miss:int=0
    force_target_on_top:bool=False

    def resolve(self,quality_roll:int,type_roll:int,other_roll:int,target:str,pool:tuple[str,...]):
        if not 0<=self.top_miss<40 or not 0<=self.mid_miss<10:raise Rejected('invalid pity')
        if not all(0<=x<10000 for x in (quality_roll,type_roll)):raise Rejected('invalid roll')
        if len(set(pool))!=len(pool) or len(pool)<2 or target not in pool:raise Rejected('invalid pool')
        if self.top_miss==39 or quality_roll<300:q='Q4'
        elif self.mid_miss==9 or quality_roll<2000:q='Q3'
        else:q='Q2'
        forced=q=='Q4' and self.force_target_on_top
        if forced or type_roll<5000:chosen=target
        else:
            others=tuple(x for x in pool if x!=target)
            chosen=others[other_roll%len(others)]
        if q=='Q4':
            self.top_miss=0
            self.force_target_on_top=chosen!=target
        else:self.top_miss+=1
        self.mid_miss=self.mid_miss+1 if q=='Q2' else 0
        return q,chosen,forced

    def maximum_remaining(self):
        return {'any_top':40-self.top_miss,'selected_top':(40 if self.force_target_on_top else 80)-self.top_miss}

@dataclass
class Account:
    revision:int=0
    roster:tuple[str,...]=ALL_ACTORS
    gates:set[str]=field(default_factory=lambda:{'G_START','G_R01_A'})
    first_crafted:set[str]=field(default_factory=set)
    tutorial_done:bool=True
    linked:bool=True
    free:int=0
    paid:int=0
    paid_lots:dict=field(default_factory=dict)
    pity:Pity=field(default_factory=Pity)
    natural_pity:int=0
    seq:int=0
    refinement_cap:int=1
    inventory:dict=field(default_factory=dict)
    results:dict=field(default_factory=dict)
    tx_receipts:dict=field(default_factory=dict)
    grants:dict=field(default_factory=dict)
    selected_outfits:dict=field(default_factory=dict)
    placed_furniture:dict=field(default_factory=dict)
    reward_once:set[str]=field(default_factory=set)
    daily_last:int=0
    pending_local_journal:bool=False
    authoritative_version:str='COMMERCE_CANDIDATE_R2'

    def state_hash(self):return digest(asdict(self))
    def eligible(self):
        return tuple(sorted(k for k,t in GEAR.items() if t['catalog_enabled_in_mock'] and t['gate'] in self.gates
            and set(t['actors'])&set(self.roster) and (t['parent'] is None or k in self.first_crafted)))
    def quote(self,target:str):
        if not self.linked:raise Rejected('link/restore account before purchase-compatible draw')
        if not self.tutorial_done or 'G_R01_A' not in self.gates or set(self.roster)!=set(ALL_ACTORS):raise Rejected('gacha not unlocked')
        if self.pending_local_journal:raise Rejected('sync journal first')
        pool=self.eligible()
        if len(pool)<2 or target not in pool:raise Rejected('unavailable target')
        return {'revision':self.revision,'version':self.authoritative_version,'target':target,'pool':pool,'refinement_cap':self.refinement_cap,'pity':asdict(self.pity)}

    def purchase_tickets_mock(self,tx:str,qty:int,verified:bool=True):
        if not verified or not self.linked or qty not in (1,10):raise Rejected('invalid mock transaction')
        sig=digest(['tickets',qty])
        if tx in self.tx_receipts:
            if self.tx_receipts[tx]!=sig:raise Rejected('transaction collision')
            return
        self.tx_receipts[tx]=sig;self.paid_lots[tx]={'qty':qty,'remaining':qty,'revoked':False}
        self.paid+=qty;self.revision+=1

    def _consume(self,n):
        free_used=min(n,self.free);paid_used=n-free_used
        if paid_used>self.paid:raise Rejected('insufficient tickets')
        self.free-=free_used;self.paid-=paid_used
        labels=[{'kind':'free','transaction':None} for _ in range(free_used)]
        remaining=paid_used
        for tx,lot in self.paid_lots.items():
            take=min(lot['remaining'],remaining);lot['remaining']-=take;remaining-=take
            labels += [{'kind':'paid','transaction':tx} for _ in range(take)]
        if remaining:raise Rejected('wallet/lot mismatch')
        return labels

    def draw(self,op:str,quote:dict,n:int=1,secret='test-seed',online=True,fail_before_commit=False,
             rolls:Callable[[str,int,int],int]|None=None):
        sig=digest([quote,n])
        # Repeated op returns persisted results BEFORE old-version/old-revision checks.
        if op in self.results:
            if self.results[op]['signature']!=sig:raise Rejected('operation collision')
            return deepcopy(self.results[op]['outcome'])
        if not online:raise Rejected('draw requires online ledger')
        if n not in (1,10):raise Rejected('unsupported batch')
        if quote!=self.quote(quote.get('target','')):raise Rejected('stale or changed quote')
        if self.free+self.paid<n:raise Rejected('insufficient tickets')
        nxt=deepcopy(self);funding=nxt._consume(n);items=[]
        rng=rolls or (lambda kind,seq,m:fixture_roll(secret,kind,seq,m))
        for source in funding:
            seq=nxt.seq;nxt.seq+=1
            q,tid,forced=nxt.pity.resolve(rng('quality',seq,10000),rng('type',seq,10000),rng('other',seq,100000),quote['target'],tuple(quote['pool']))
            template=GEAR[tid];pool=template['affix_pool'];core=template['core_affix']
            rest=[x for x in pool if x!=core];count=2 if q=='Q2' else 3
            aff=[core]
            for slot in range(count-1):aff.append(rest.pop(rng('affix'+str(slot),seq,len(rest))))
            qs=[5000+rng('roll'+str(i),seq,5001) for i in range(count)]
            uid='DRAW_R2_'+str(seq)
            if uid in nxt.inventory:raise Rejected('item identity collision')
            item={'id':uid,'template_id':tid,'quality':q,'affixes':[{'id':a,'quantile_within_existing_quality_range_bp':v} for a,v in zip(aff,qs)],
                  'native_refinement_rank':quote['refinement_cap'],'enhancement':0,'actual_investment_dust':0,
                  'origin':'gacha','funding':source,'target_forced':forced,'pool_version':quote['version'],
                  'locked_by_default':q=='Q4','production_r2_stats_computed':False}
            nxt.inventory[uid]=item;items.append(deepcopy(item))
        outcome={'items':items,'free_used':sum(x['kind']=='free' for x in funding),'paid_used':sum(x['kind']=='paid' for x in funding),
                 'pity_after':asdict(nxt.pity),'natural_pity_after':nxt.natural_pity,'target':quote['target'],'odds_version':quote['version']}
        nxt.results[op]={'signature':sig,'outcome':deepcopy(outcome)};nxt.revision+=1
        if fail_before_commit:raise RuntimeError('injected precommit failure')
        self.__dict__.update(nxt.__dict__)
        return deepcopy(outcome)

    def grant_content_mock(self,tx:str,content_ids:tuple[str,...],verified=True):
        if not verified or any(x not in PRODUCTS for x in content_ids):raise Rejected('invalid entitlement')
        sig=digest(['content',sorted(content_ids)])
        if tx in self.tx_receipts:
            if self.tx_receipts[tx]!=sig:raise Rejected('transaction collision')
            return
        self.tx_receipts[tx]=sig;self.grants[tx]={'items':tuple(content_ids),'revoked':False};self.revision+=1

    def active_content(self):
        return {i for v in self.grants.values() if not v['revoked'] for i in v['items']}

    def revoke_content_mock(self,tx,verified=True):
        if not verified or tx not in self.grants:raise Rejected('invalid revocation')
        if self.grants[tx]['revoked']:return
        self.grants[tx]['revoked']=True;active=self.active_content()
        self.selected_outfits={a:(v if v in active else 'DEFAULT:'+a) for a,v in self.selected_outfits.items()}
        self.placed_furniture={s:(v if v in active else 'DEFAULT:'+s) for s,v in self.placed_furniture.items()}
        self.revision+=1

    def refund_unspent_ticket_mock(self,tx):
        if tx not in self.paid_lots:raise Rejected('unknown purchase')
        lot=self.paid_lots[tx]
        if lot['revoked']:return
        if lot['remaining']!=lot['qty']:raise Rejected('spent-ticket refund requires full lineage policy; NOT IMPLEMENTED')
        self.paid-=lot['remaining'];lot['remaining']=0;lot['revoked']=True;self.revision+=1

    def select_outfit(self,actor,item,downloaded=True):
        if actor not in self.roster:raise Rejected('unknown actor')
        if item=='DEFAULT:'+actor:self.selected_outfits[actor]=item;return
        if item not in self.active_content() or PRODUCTS[item].get('actor')!=actor:raise Rejected('not owned or wrong actor')
        if not downloaded:raise Rejected('download content before activation; entitlement stays owned')
        self.selected_outfits[actor]=item

    def place(self,slot,item):
        if item not in self.active_content() or PRODUCTS[item].get('slot')!=slot:raise Rejected('wrong placement or unowned')
        self.placed_furniture[slot]=item

    def living_score(self):
        earned=20*sum(x in self.gates for x in BOSSES)
        return min(100,earned+sum(PRODUCTS[x]['score'] for x in self.active_content()))
    def living_bp(self):return self.living_score()*3
    def stats_snapshot_mock(self,base:dict,flat:dict,percent:dict,stat_caps:dict|None=None):
        # Exact Fraction here; production R6 fixed point adapter remains unimplemented.
        b=self.living_bp();out={}
        for k in ('hp','power','defense'):
            total=percent.get(k,0)+b
            if stat_caps is not None:total=min(total,stat_caps[k])
            out[k]=Fraction(base[k]+flat.get(k,0))*(10000+total)/10000
        return out

    def reward_intro(self):
        if not self.tutorial_done or 'G_R01_A' not in self.gates or set(self.roster)!=set(ALL_ACTORS):raise Rejected('locked')
        if 'intro' not in self.reward_once:self.free+=10;self.reward_once.add('intro');self.revision+=1
    def reward_region(self,gate):
        if gate not in BOSSES or gate not in self.gates:raise Rejected('no verified clear in mock')
        if gate not in self.reward_once:self.free+=5;self.reward_once.add(gate);self.revision+=1
    def accrue_free(self,now:int):
        if not self.linked or not self.tutorial_done or 'G_R01_A' not in self.gates or set(self.roster)!=set(ALL_ACTORS):raise Rejected('daily accrual locked')
        if now<self.daily_last:raise Rejected('clock rollback')
        days=(now-self.daily_last)//DAY
        if not days:return 0
        award=min(7,days);self.free+=award
        # Advance by all elapsed days, not just 7: no repeated recovery of capped time.
        self.daily_last+=days*DAY;self.revision+=1;return award


def target_top_distribution(p=.03,pity=40,target_prob=.5):
    """Exact finite-state probability arithmetic (floating point), no random samples.
    time to selected Q4 from empty counters; 2 top encounters at most.
    """
    states={(0,False):1.0};pmf=[]
    for step in range(1,pity*2+1):
        nxt=defaultdict(float);success=0.0
        for (miss,force),mass in states.items():
            q=1.0 if miss==pity-1 else p
            success+=mass*q*(1.0 if force else target_prob)
            if not force:nxt[(0,True)]+=mass*q*(1-target_prob)
            if q<1:nxt[(miss+1,force)]+=mass*(1-q)
        pmf.append(success);states=nxt
    mean=sum((i+1)*v for i,v in enumerate(pmf));cdf=0;percentiles={}
    for i,v in enumerate(pmf):
        cdf+=v
        for pctl in (.5,.9,.95,.99):
            if str(pctl) not in percentiles and cdf>=pctl-1e-12:percentiles[str(pctl)]=i+1
    return {'pmf':pmf,'mass':sum(pmf),'mean':mean,'percentiles':percentiles,'maximum':pity*2,'residual_mass':sum(states.values())}


def quality_horizon(draws:int,p=.03,pity=40,mid_pity=10,mid_plus_prob=.20):
    states={(0,0):1.0};expected={'Q2':0.,'Q3':0.,'Q4':0.}
    for _ in range(draws):
        nxt=defaultdict(float)
        for (hi,lo),mass in states.items():
            a=1. if hi==pity-1 else p
            b=0. if a==1. else (1.-a if lo==mid_pity-1 else mid_plus_prob-p)
            c=1.-a-b
            for q,prob,newstate in [('Q4',a,(0,0)),('Q3',b,(hi+1,0)),('Q2',c,(hi+1,lo+1))]:
                if prob>1e-15:expected[q]+=mass*prob;nxt[newstate]+=mass*prob
        states=nxt
    return {'draws':draws,'expected_counts':expected,'mass':sum(states.values())}


def check_outfit_manifest(m):
    errors=[]
    for k in PRODUCTION['content_manifest_fields']:
        if k not in m:errors.append('missing:'+k)
    for ctx in PRODUCTION['required_outfit_contexts']:
        if ctx not in m.get('contexts',[]):errors.append('context:'+ctx)
    for typ in ('combat','home','detail'):
        for a in PRODUCTION['required_'+typ]:
            if a not in m.get('action_coverage',{}).get(typ,[]):errors.append('action:'+typ+'/'+a)
    if len(m.get('editable_components',[]))<2:errors.append('flat_source_not_rig')
    if not m.get('underpaint'):errors.append('missing_underpaint')
    for k in PRODUCTION['required_bindings']:
        if k not in m.get('bindings',[]):errors.append('binding:'+k)
    if not m.get('compatible_weapon_ids'):errors.append('no_weapon_coverage')
    if m.get('changes_combat_logic'):errors.append('visual_must_not_change_combat')
    return errors


def check_furniture_fit(socket,furniture):
    return (socket['category']==furniture['category'] and
        set(socket['required_interactions'])<=set(furniture.get('supported_interactions',[])) and
        furniture.get('has_underpaint',False) and furniture.get('anchors_valid',False) and
        furniture.get('within_bounds',False))
