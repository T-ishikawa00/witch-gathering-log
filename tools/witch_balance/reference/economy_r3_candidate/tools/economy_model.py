"""R3 economic reference only. No combat engine, SDK, network or user's Mac access.
Run tests with: python -m unittest discover -s tools -p 'test_*.py'
All saved numbers are integers. Advance is a copy/commit memory transaction;
it does NOT prove durable database/power-failure safety.
"""
from __future__ import annotations
from dataclasses import dataclass, asdict, field
from pathlib import Path
from collections import Counter
import json, hashlib, copy

ROOT=Path(__file__).resolve().parents[1]
CFG=json.loads((ROOT/'data/economy_R3.json').read_text())
GROWTH=json.loads((ROOT/'reference/growth_gear_skills_R2_UNCHANGED.json').read_text())
WORLD=json.loads((ROOT/'reference/world_catalog_R1_UNCHANGED.json').read_text())
SOURCES={s['id']:s for s in CFG['sources']}
RATES={s['region_id']:s for s in CFG['rates']}
TEMPLATES={s['template_id']:s for s in GROWTH['gear_templates']}
GATES={s['id']:s for s in WORLD['gates']}
ACTORS={s['id']:s for s in WORLD['actors']}
COSTS={s['operation_id']:s for s in CFG['costs']}
WORK_MS=CFG['expedition']['work_seconds']*1000
CAP_MS=CFG['expedition']['unattended_cap_seconds']*1000

def canon(x): return json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':'))
def digest(x): return hashlib.sha256(canon(x).encode()).hexdigest()
def randbelow(seed,domain,index,n):
    if n<=0: raise ValueError('empty random domain')
    limit=(1<<256)-((1<<256)%n)
    for retry in range(1000):
        v=int.from_bytes(hashlib.sha256(canon([str(seed),str(domain),int(index),retry]).encode()).digest(),'big')
        if v<limit: return v%n
    raise RuntimeError('rng rejection bound')
def xp_threshold(level):
    if not 1<=level<=60: raise ValueError('level 1..60')
    return sum(100+30*(l-1)+4*(l-1)**2 for l in range(1,level))
def level_from_xp(xp):
    if xp<0: raise ValueError('negative xp')
    return max(l for l in range(1,61) if xp>=xp_threshold(l))
def closure(gate):
    if gate not in GATES: raise ValueError('unknown gate')
    return {gate}|set().union(*(closure(p) for p in GATES[gate]['requires']))
def unlocked_rank(gates):
    return max(x['rank'] for x in GROWTH['attunement_ranks'] if x['gate'] in gates)

@dataclass(frozen=True)
class Snapshot:
    region_id:str
    gates:tuple[str,...]
    joined:tuple[str,...]
    known_evolved:tuple[str,...]=()
    focus_source:str|None=None
    wished_template:str|None=None
    cleared_area_ids:tuple[str,...]=()
    content_version:str='witch_economy_r3.0'

    def validate(self):
        if self.region_id not in RATES or self.content_version!=CFG['meta']['schema']: raise ValueError('unsupported snapshot')
        gs=set(self.gates)
        if 'G_START' not in gs or any(x not in GATES for x in gs): raise ValueError('invalid gates')
        if any(not set(GATES[x]['requires']).issubset(gs) for x in gs): raise ValueError('gate missing ancestors')
        if not self.joined or len(set(self.joined))!=len(self.joined) or any(x not in ACTORS for x in self.joined): raise ValueError('invalid roster')
        if any(ACTORS[x]['join_gate'] not in gs for x in self.joined): raise ValueError('future member')
        entry=next(r['entry_gate'] for r in WORLD['regions'] if r['id']==self.region_id)
        if entry not in gs: raise ValueError('future region')
        if any(x not in TEMPLATES for x in self.known_evolved): raise ValueError('unknown discovery')
        valid_area={x['id'] for x in WORLD['areas'] if x['unlock_gate'] in gs}
        if not set(self.cleared_area_ids).issubset(valid_area): raise ValueError('future area clearance')
        if self.focus_source:
            if self.focus_source not in SOURCES: raise ValueError('missing source')
            s=SOURCES[self.focus_source]
            if s['region_id']!=self.region_id or s['available_gate'] not in gs: raise ValueError('locked source')
            if s['source_type']!='boss' and s['area_id'] not in self.cleared_area_ids: raise ValueError('uncleared route')
        elif not eligible_sources(self): raise ValueError('no cleared survey source')
        if not eligible_templates(self): raise ValueError('empty gear pool')

def snapshot(region='R01',gate='G_START',focus=None,wish=None,discovered=()):
    gs=closure(gate)
    joined=tuple(a['id'] for a in WORLD['actors'] if a['join_gate'] in gs)
    # Fixture factory: assumes the available field areas have been surveyed.
    # Runtime must explicitly record clearance; this is not an automatic gate policy.
    clear=tuple(a['id'] for a in WORLD['areas'] if a['unlock_gate'] in gs and '採集' in a['purpose'])
    s=Snapshot(region,tuple(sorted(gs)),joined,tuple(discovered),focus,wish,clear);s.validate();return s

def eligible_sources(s):
    return sorted(x['id'] for x in SOURCES.values() if x['region_id']==s.region_id and x['source_type']!='boss' and x['available_gate'] in s.gates and x['area_id'] in s.cleared_area_ids)
def eligible_templates(s):
    return sorted(k for k,t in TEMPLATES.items() if t['unlock_gate'] in s.gates and set(t['actor_ids'])&set(s.joined) and (not t['parent_template_id'] or k in s.known_evolved))
def choose_quality(seed,index,misses):
    if misses>=CFG['loot']['legend_pity_natural_rolls']-1: return 'Q4',0,True
    draw=randbelow(seed,'natural.quality',index,10000);total=0
    for q,weight in CFG['loot']['base_weights'].items():
        total+=weight
        if draw<total:return q,(0 if q=='Q4' else misses+1),False
    raise ValueError('invalid weights')
def gear_roll(seed,index,s,misses):
    gs=eligible_templates(s)
    local=[x for x in CFG['regional_gear_theme_pools'][s.region_id] if x in gs]
    use_wish=(index%6==0 and s.wished_template in gs)
    if use_wish: t=s.wished_template
    else:
        pool=local if local and randbelow(seed,'natural.pool',index,10000)<6000 else gs
        t=pool[randbelow(seed,'natural.template',index,len(pool))]
    q,misses,pity=choose_quality(seed,index,misses)
    members=set(TEMPLATES[t]['actor_ids'])&set(s.joined)
    apool=[]
    for a in GROWTH['affixes']:
        cap=a['actor_capability']
        if cap!='all' and not members&set(cap):continue
        if t in {'EQ_W_01','EQ_W_G1','EQ_W_G2'} and a['affix_id']=='AF_DOT':continue
        apool.append(a['affix_id'])
    apool.sort();latent=[]
    for j in range(3):
        pos=randbelow(seed,f'natural.affix.{j}',index,len(apool))
        latent.append({'affix_id':apool.pop(pos),'roll_q':randbelow(seed,f'natural.q.{j}',index,1001)})
    return {'uid':digest([str(seed),'natural',index])[:32],'template_id':t,'quality':q,'rank':min(int(s.region_id[1:]),unlocked_rank(s.gates)),'enhancement':0,'latent_affixes':latent,'invested_dust':0,'natural_index':index,'pity':pity,'wish':use_wish,'origin':{'kind':'relic_search','region_id':s.region_id,'content_version':s.content_version}},misses

@dataclass
class State:
    seed:str='fixture'
    last_wall_ms:int=0
    partial_ms:int=0
    work_index:int=0
    active_snapshot:dict|None=None
    requested_snapshot:dict|None=None
    materials:dict=field(default_factory=dict)
    roster_xp:dict=field(default_factory=lambda:{'C_WITCH':0,'C_FAMILIAR':0})
    dust:int=0
    credited_ms:int=0
    resting_ms:int=0
    unacknowledged_credit_ms:int=0
    presence_ids:dict=field(default_factory=dict)
    source_progress:dict=field(default_factory=dict)
    bag_counts:dict=field(default_factory=dict)
    gear_index:int=0
    gear_snapshot:dict|None=None
    legend_misses:int=0
    gear:list=field(default_factory=list)
    offer_work:int=0
    offer_xp:int=0
    offer_dust:int=0
    offer_xp_by_actor:dict=field(default_factory=dict)
    offer_index:int=0
    offers:list=field(default_factory=list)
    receipts:dict=field(default_factory=dict)
    first_rewards:dict=field(default_factory=dict)
    earned_xp:int=0
    earned_dust:int=0
    ad_xp:int=0
    ad_dust:int=0

def snap_from(d):
    if d is None: raise ValueError('snapshot missing')
    return Snapshot(**{k:tuple(v) if k in {'gates','joined','known_evolved','cleared_area_ids'} else v for k,v in d.items()})

def single_work(st,s):
    s.validate();rate=RATES[s.region_id]
    # Shared resources issued once; experience credited to the snapshot roster.
    st.work_index+=1
    if (st.work_index-1)%6==0:st.gear_snapshot=asdict(s)
    st.dust+=rate['dust_per_work'];st.earned_dust+=rate['dust_per_work'];st.earned_xp+=rate['xp_per_work']
    for a in s.joined:
        if a not in st.roster_xp:raise ValueError('must settle and join before snapshot activation')
        st.roster_xp[a]=min(xp_threshold(60),st.roster_xp[a]+rate['xp_per_work'])
    if s.focus_source: source=SOURCES[s.focus_source]
    else:
        pool=eligible_sources(s);key=digest(pool);n=st.bag_counts.get(key,0)
        bag=n//len(pool);order=sorted(pool,key=lambda a:(randbelow(st.seed,'survey.'+key+'.'+a,bag,1<<63),a))
        source=SOURCES[order[n%len(pool)]];st.bag_counts[key]=n+1
    sid=source['id'];v=st.source_progress.get(sid,0)+1
    qty,v=divmod(v,source['work_units_per_yield']);st.source_progress[sid]=v
    if qty:st.materials[source['material_id']]=st.materials.get(source['material_id'],0)+qty
    if st.work_index%CFG['expedition']['gear_period_work_units']==0:
        st.gear_index+=1;item,st.legend_misses=gear_roll(st.seed,st.gear_index,snap_from(st.gear_snapshot),st.legend_misses);st.gear.append(item)
    for actor_id in s.joined:st.offer_xp_by_actor[actor_id]=st.offer_xp_by_actor.get(actor_id,0)+rate['xp_per_work']
    st.offer_work+=1;st.offer_xp+=rate['xp_per_work'];st.offer_dust+=rate['dust_per_work']
    if st.offer_work==96:
        st.offer_index+=1
        if len(st.offers)<6:st.offers.append({'offer_id':f'offer-{st.offer_index}','xp':st.offer_xp//16,'dust':st.offer_dust//16,'xp_by_actor':{a:v//16 for a,v in st.offer_xp_by_actor.items()},'content_version':s.content_version})
        st.offer_work=0;st.offer_xp=0;st.offer_dust=0;st.offer_xp_by_actor={}

def advance_to(state,now_ms,s,op_id,fail_before_commit=False):
    """Pure return of a new state; caller persists it atomically with the op receipt.
    Requested snapshot changes after any unfinished 5-minute old work unit.
    Negative clock adjustments earn nothing and are reported by an exception.
    """
    if not isinstance(now_ms,int) or now_ms<0 or not op_id:raise ValueError('invalid operation')
    s.validate();payload=digest([now_ms,asdict(s)])
    if op_id in state.receipts:
        if state.receipts[op_id]!=payload:raise ValueError('op_id payload mismatch')
        return copy.deepcopy(state)
    if state.requested_snapshot is not None and canon(state.requested_snapshot)!=canon(asdict(s)):raise ValueError('settle old snapshot then select_route; no retroactive change')
    if now_ms<state.last_wall_ms:raise ValueError('CLOCK_REWIND: requires explicit no-credit reanchor')
    st=copy.deepcopy(state);gap=now_ms-st.last_wall_ms;credit=min(gap,max(0,CAP_MS-st.unacknowledged_credit_ms));st.unacknowledged_credit_ms+=credit
    st.last_wall_ms=now_ms;st.credited_ms+=credit;st.resting_ms+=gap-credit
    st.requested_snapshot=asdict(s)
    if st.partial_ms==0:st.active_snapshot=asdict(s)
    remain=credit
    while remain:
        take=min(remain,WORK_MS-st.partial_ms);remain-=take;st.partial_ms+=take
        if st.partial_ms==WORK_MS:
            single_work(st,snap_from(st.active_snapshot));st.partial_ms=0;st.active_snapshot=st.requested_snapshot
            if len(st.gear)>CFG['inventory']['runtime_safety_ceiling_instances']:raise RuntimeError('STORAGE_BLOCKED: preserve prior state and pending transaction')
    if fail_before_commit:raise RuntimeError('INJECTED_BEFORE_COMMIT')
    st.receipts[op_id]=payload;return st

def select_route(state,s,settled_wall_ms):
    s.validate()
    if settled_wall_ms!=state.last_wall_ms:raise ValueError('must settle elapsed time before route change')
    if any(a not in state.roster_xp for a in s.joined):raise ValueError('join actor first')
    st=copy.deepcopy(state);st.requested_snapshot=asdict(s)
    if st.partial_ms==0:st.active_snapshot=asdict(s)
    return st

def acknowledge_presence(state,now_ms,session_id):
    # Runtime must call only on real foreground entry/user interaction, not each frame/timer.
    if now_ms!=state.last_wall_ms or not session_id:raise ValueError('settle before presence acknowledgement')
    st=copy.deepcopy(state)
    if session_id in st.presence_ids:return st
    st.presence_ids[session_id]=now_ms;st.unacknowledged_credit_ms=0
    return st

def reanchor_without_credit(state,now_ms,acknowledged):
    if not acknowledged or not isinstance(now_ms,int) or now_ms<0:raise ValueError('explicit acknowledgement required')
    st=copy.deepcopy(state);st.last_wall_ms=now_ms;return st

def join_actor(state,actor_id,gates):
    if actor_id not in ACTORS or ACTORS[actor_id]['join_gate'] not in gates:raise ValueError('join gate')
    st=copy.deepcopy(state)
    if actor_id not in st.roster_xp:st.roster_xp[actor_id]=max(st.roster_xp.values(),default=0)
    return st

def redeem_offer(state,offer_id,method,op_id):
    if method not in {'rewarded_verified','premium_entitled'}:raise ValueError('verified view or entitlement required')
    payload=digest([offer_id,method]);key='ad:'+op_id
    if key in state.receipts:
        if state.receipts[key]!=payload:raise ValueError('op collision')
        return copy.deepcopy(state)
    if not any(o['offer_id']==offer_id for o in state.offers):raise ValueError('offer missing or already consumed')
    st=copy.deepcopy(state);offer=next(o for o in st.offers if o['offer_id']==offer_id)
    st.offers.remove(offer);st.dust+=offer['dust'];st.ad_dust+=offer['dust'];st.ad_xp+=offer['xp']
    for a,xp in offer['xp_by_actor'].items():
        if a in st.roster_xp:st.roster_xp[a]=min(xp_threshold(60),st.roster_xp[a]+xp)
    st.receipts[key]=payload;return st

def first_boss_reward(state,boss_id,already_cleared,*,victory_confirmed,gates):
    if not boss_id.startswith('B_R') or boss_id not in {e['id'] for e in WORLD['enemies'] if e['id'].startswith('B_')}:raise ValueError('unknown boss')
    enemy=next(x for x in WORLD['enemies'] if x['id']==boss_id)
    if not victory_confirmed or enemy['encounter_gate'] not in gates:raise ValueError('confirmed eligible first battle receipt required')
    st=copy.deepcopy(state)
    if already_cleared or boss_id in st.first_rewards:return st
    source=next(x for x in SOURCES.values() if x['enemy_id']==boss_id)
    st.materials[source['material_id']]=st.materials.get(source['material_id'],0)+1;st.first_rewards[boss_id]=True
    return st

def goal_units(required_materials,inventory,progress=None):
    """Exact required credited work for guaranteed source yields; ignores XP/dust and travel.
    Only already accessible sources may be dispatched by the caller.
    """
    progress=progress or {};jobs=[]
    for mid,qty in sorted(required_materials.items()):
        if qty<0:raise ValueError('negative goal')
        deficit=max(0,qty-inventory.get(mid,0))
        if not deficit:continue
        s=next((x for x in SOURCES.values() if x['material_id']==mid),None)
        if s is None:raise ValueError('unknown material')
        units=deficit*s['work_units_per_yield']-progress.get(s['id'],0)
        if units>0:jobs.append({'source_id':s['id'],'units':units})
    return jobs

def aggregate_cost(operations):
    mats=Counter();dust=0
    for oid,count in operations:
        if oid not in COSTS or count<0:raise ValueError('invalid cost')
        c=COSTS[oid];dust+=c['dust']*count
        for x in c['ingredients']:mats[x['material_id']]+=x['quantity']*count
    return dict(mats),dust
