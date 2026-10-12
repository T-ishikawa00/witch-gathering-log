"""Source-based gacha-to-cleanup reference, not a production game or payment system.

Uses original R3 quality step and Commerce R2 template metadata. Normalized affix
quantiles have NO implicit damage/HP values. Comparisons only within identical
quality/template/rank/enhancement; no claim of combat-win dominance.
"""
from __future__ import annotations
from dataclasses import dataclass, field, asdict, replace
from pathlib import Path
from collections import defaultdict, Counter
from copy import deepcopy
from hashlib import sha256
import sys,json,random
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'source/research_r3/tools'))
from compare_gacha import Candidate,Counters,candidates,step,quality_horizons
GEAR={x['id']:x for x in json.loads((ROOT/'source/commerce_r2/data/GEAR_METADATA_AND_NEW_AFFIX_PROPOSAL.json').read_text())['items']}
PLAN=json.loads((ROOT/'data/EXPERIMENT_PLAN.json').read_text())
ACTORS=('C_WITCH','C_APPRENTICE','C_SMITH','C_FAMILIAR')
INITIAL_GATES=frozenset(['G_START','G_R01_A'])
QUALITIES=('普通','良質','希少','特級','伝説')

def digest(x):
    return sha256(json.dumps(x,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
def rng_for(seed,domain):return random.Random(int(sha256(f'{seed}|{domain}'.encode()).hexdigest(),16))
def eligible(gates=INITIAL_GATES,roster=ACTORS,crafted=frozenset()):
    return tuple(sorted(k for k,t in GEAR.items() if t['catalog_enabled_in_mock'] and t['gate'] in gates and set(t['actors'])&set(roster) and (t['parent'] is None or k in crafted)))

@dataclass(frozen=True)
class Item:
    uid:str
    template_id:str
    quality:int
    affixes:tuple[tuple[str,int],...]=()
    rank:int=1
    enhancement:int=0
    invested_powder:int=0
    invested_materials:int=0
    locked:bool=False
    equipped:bool=False
    saved:bool=False
    first_discovery:bool=False
    origin:str='fixture'
    def protected_reasons(self):
        return [name for name,v in [('locked',self.locked),('equipped',self.equipped),('saved',self.saved),('invested',self.invested_powder>0 or self.invested_materials>0),('first_discovery',self.first_discovery),('enhanced',self.enhancement>0)] if v]
    def as_json(self):
        o=asdict(self);o['affixes']=[list(x) for x in self.affixes];return o
    def validate(self):
        if self.template_id not in GEAR or not 0<=self.quality<=4:raise ValueError('invalid item')
        if self.rank<1 or self.enhancement<0 or self.invested_powder<0 or self.invested_materials<0:raise ValueError('invalid investment')
        expected=(0,1,2,3,3)[self.quality]
        if len(self.affixes)!=expected or len(set(x[0] for x in self.affixes))!=expected:raise ValueError('affix count/duplicates')
        if any(a not in GEAR[self.template_id]['affix_pool'] or not 0<=q<=10000 for a,q in self.affixes):raise ValueError('affix range')

class Generator:
    def __init__(self,candidate:Candidate,seed,target='EQ_W_01',pool=None,known=(),rank=1):
        self.c=candidate;self.pool=tuple(pool or eligible());self.target=target
        if target not in self.pool or len(set(self.pool))!=len(self.pool) or len(self.pool)<2:raise ValueError('pool/target')
        self.state=Counters();self.seq=0;self.known=set(known);self.rank=rank
        self.rngs={x:rng_for(seed,x) for x in ('quality','target','other','affix','quantile')}
    def draw(self,n:int):
        if not isinstance(n,int) or n<0:raise ValueError('bad count')
        out=[]
        for _ in range(n):
            q,hit,self.state=step(self.c,self.state,self.rngs['quality'].randrange(10000),self.rngs['target'].randrange(10000))
            others=[t for t in self.pool if t!=self.target];other=self.rngs['other'].choice(others)
            tid=self.target if hit else other;count=(0,1,2,3,3)[q]
            selected=[]
            if count:
                # core guarantee for any quality that actually owns affix slots.
                selected=[GEAR[tid]['core_affix']]
                p=[a for a in GEAR[tid]['affix_pool'] if a not in selected]
                selected+=self.rngs['affix'].sample(p,count-1)
            aff=tuple(sorted((a,self.rngs['quantile'].randint(5000,10000)) for a in selected))
            new=tid not in self.known;self.known.add(tid)
            it=Item(f'draw:{self.seq}',tid,q,aff,self.rank,locked=q==4,first_discovery=new,origin='gacha')
            it.validate();out.append(it);self.seq+=1
        return out


def fixture_item(uid,tid,q,quantile=6500,**kw):
    n=(0,1,2,3,3)[q];t=GEAR[tid];names=[t['core_affix']]+[x for x in t['affix_pool'] if x!=t['core_affix']]
    it=Item(uid,tid,q,tuple(sorted((a,quantile) for a in names[:n])),**kw);it.validate();return it

def profile(name):
    items=[]
    if name=='first_box':
        for tid in eligible():
            if GEAR[tid]['slot']=='weapon':items.append(fixture_item('owned:'+tid,tid,0,equipped=True))
    elif name=='established_box':
        for tid in eligible():
            for j in range(len(GEAR[tid]['actors'])):
                items.append(fixture_item(f'owned:{tid}:equipped:{j}',tid,2,equipped=True))
                items.append(fixture_item(f'owned:{tid}:spare1:{j}',tid,1))
                items.append(fixture_item(f'owned:{tid}:spare0:{j}',tid,0))
    else:raise ValueError('unknown profile')
    return items


def comparable_ge(a:Item,b:Item):
    """Numerical non-inferiority in same-quality normalized affix coordinates only."""
    if (a.template_id,a.quality,a.rank,a.enhancement)!=(b.template_id,b.quality,b.rank,b.enhancement):return False
    va,vb=dict(a.affixes),dict(b.affixes)
    return set(va)==set(vb) and all(va[k]>=v for k,v in vb.items())


def offer_cleanup(existing:list[Item],new:list[Item],qmax=1):
    """Offer, never execute. Only NEW unprotected items; cannot churn old inventory.

    Keep capacity-many survivors for each exact quality/affix-signature group.
    This is deliberately conservative: higher rarity does NOT discard all lower
    rarity; tradeoffs do not collapse into a single "power" score.
    """
    if qmax not in (1,2):raise ValueError('qmax must be1 or2')
    allitems=existing+new;uids=[x.uid for x in allitems]
    if len(set(uids))!=len(uids):raise ValueError('duplicate UID')
    newset={x.uid for x in new};bykey=defaultdict(list);protected={}
    for x in allitems:
        x.validate()
        reasons=x.protected_reasons()
        if x.quality>qmax:reasons+=['quality_preserved']
        if x.uid not in newset:reasons+=['existing_item_untouched']
        if reasons:protected[x.uid]=reasons
        k=(x.template_id,x.quality,x.rank,x.enhancement,tuple(a for a,v in x.affixes));bykey[k].append(x)
    offered=[];witnesses={}
    for k,group in bykey.items():
        if k[1]>qmax:continue
        capacity=len(GEAR[k[0]]['actors'])
        survivors=[x for x in group if x.uid in protected]
        # Descending sum ensures a subsequently retained weak item cannot be the
        # only witness for a deleted stronger item. Crossing vectors survive.
        candidates_=sorted((x for x in group if x.uid not in protected),key=lambda x:(-sum(v for a,v in x.affixes),x.uid))
        for x in candidates_:
            dominating=[y for y in survivors if comparable_ge(y,x)]
            if len(dominating)>=capacity:
                offered.append(x.uid);witnesses[x.uid]=[y.uid for y in dominating[:capacity]]
            else:survivors.append(x)
    if set(offered)&set(protected):raise AssertionError('protected offered')
    if any(set(ws)&set(offered) for ws in witnesses.values()):raise AssertionError('discarded witness')
    return {'ids':sorted(offered),'witnesses':witnesses,'protections':protected,'qmax':qmax,'retained_new_ids':[x.uid for x in new if x.uid not in set(offered)]}


def enhancement_probe(powder:int,already_capped=False):
    if powder<0:raise ValueError('negative powder')
    if already_capped:return {'affordable_steps':0,'full_plus3_items':0,'spent':0,'left':powder,'wand_enhancement':3,'reason':'all_three_probe_items_at_current_cap'}
    balance=powder;steps=complete=0;levels=[0,0,0]
    for i in range(3):
        for cost in PLAN['enhancement_probe']['incremental_costs']:
            if balance<cost:return {'affordable_steps':steps,'full_plus3_items':complete,'spent':powder-balance,'left':balance,'wand_enhancement':levels[0]}
            balance-=cost;steps+=1;levels[i]+=1
        complete+=1
    return {'affordable_steps':steps,'full_plus3_items':complete,'spent':powder-balance,'left':balance,'wand_enhancement':levels[0]}

@dataclass
class ReviewLedger:
    inventory:dict[str,Item]
    inbox:dict[str,Item]=field(default_factory=dict)
    dust:int=0
    revision:int=0
    drawn_receipts:dict=field(default_factory=dict)
    operations:dict=field(default_factory=dict)
    def state(self):
        return {'inventory':{k:v.as_json() for k,v in sorted(self.inventory.items())},'inbox':{k:v.as_json() for k,v in sorted(self.inbox.items())},'dust':self.dust,'revision':self.revision,'drawn_receipts':self.drawn_receipts,'operations':self.operations}
    def accept(self,op,items,capacity=120):
        if capacity<0:raise ValueError('capacity')
        sig=digest([i.as_json() for i in items])
        if op in self.drawn_receipts:
            if self.drawn_receipts[op]!=sig:raise ValueError('receipt collision')
            return
        ids=[x.uid for x in items]
        if len(set(ids))!=len(ids) or set(ids)&(set(self.inventory)|set(self.inbox)):raise ValueError('duplicate ID')
        nxt=deepcopy(self)
        for it in items:
            it.validate()
            if len(nxt.inventory)<capacity:nxt.inventory[it.uid]=it
            else:nxt.inbox[it.uid]=it
        nxt.drawn_receipts[op]=sig;nxt.revision+=1;self.__dict__.update(nxt.__dict__)
    def quote(self,ids,schedule,allowed):
        ids=tuple(sorted(ids));allitems={**self.inventory,**self.inbox}
        if not ids or len(set(ids))!=len(ids) or not set(ids)<=set(allowed):raise ValueError('invalid selection')
        for uid in ids:
            if uid not in allitems or allitems[uid].protected_reasons() or allitems[uid].quality>=3:raise ValueError('protected/unavailable')
        owned=[x for x in allitems.values() if x.origin!='gacha']
        acquired=[x for x in allitems.values() if x.origin=='gacha']
        qmax=max(1,max(allitems[u].quality for u in ids))
        server_allowed=set(offer_cleanup(owned,acquired,qmax)['ids'])
        if not set(ids)<=server_allowed:raise ValueError('not currently redundant or witness unavailable')
        if len(schedule)!=5 or min(schedule)<0:raise ValueError('invalid yield')
        return {'revision':self.revision,'state_hash':digest(self.state()),'ids':ids,'schedule':list(schedule),'powder':sum(schedule[allitems[u].quality] for u in ids)}
    def commit_scrap(self,op,quote,allowed,fail=False):
        signature=digest(quote)
        if op in self.operations:
            if self.operations[op]!=signature:raise ValueError('op collision')
            return
        current=self.quote(quote['ids'],quote['schedule'],allowed)
        if current!=quote:raise ValueError('stale quote')
        nxt=deepcopy(self)
        for uid in quote['ids']:
            nxt.inventory.pop(uid,None);nxt.inbox.pop(uid,None)
        nxt.dust+=quote['powder'];nxt.operations[op]=signature;nxt.revision+=1
        if fail:raise RuntimeError('injected before atomic commit')
        self.__dict__.update(nxt.__dict__)
    def lock(self,uid):
        d=self.inventory if uid in self.inventory else self.inbox
        d[uid]=replace(d[uid],locked=True);self.revision+=1


def summarize_session(c,seed,profile_name,n,qmax=1):
    existing=profile(profile_name);g=Generator(c,seed,known={x.template_id for x in existing});new=g.draw(n)
    p=offer_cleanup(existing,new,qmax);offered=set(p['ids']);count=Counter(x.quality for x in new)
    powder={name:sum(schedule[x.quality] for x in new if x.uid in offered) for name,schedule in PLAN['powder_schedules'].items()}
    keep=[x for x in new if x.uid not in offered];high=[x for x in new if x.quality>=2]
    # Potential equipment comparisons, NOT proven upgrades or AI win changes.
    fresh=sum(x.first_discovery for x in new)
    owned=[x for x in existing if x.equipped]
    strict_improvements=0
    for x in new:
        if any(comparable_ge(x,y) and dict(x.affixes)!=dict(y.affixes) for y in owned):strict_improvements+=1
    return {'candidate':c.id,'seed':seed,'profile':profile_name,'draws':n,'quality_counts':[count[q] for q in range(5)],
        'retained':len(keep),'offered_for_optional_scrap':len(offered),'retained_low':sum(x.quality<2 for x in keep),'higher_quality_for_review':len(high),
        'new_types':fresh,'target_legendary':sum(x.quality==4 and x.template_id==g.target for x in new),
        'same_quality_affix_noninferior_candidates':strict_improvements,'powder':powder,
        'enhancement_probe':{name:enhancement_probe(v) for name,v in powder.items()},
        'no_new_type_high_or_plus1':fresh==0 and len(high)==0 and powder['low']<5,
        'qmax':qmax,'proof_protected_offered':len(offered&set(p['protections']))},new,p
