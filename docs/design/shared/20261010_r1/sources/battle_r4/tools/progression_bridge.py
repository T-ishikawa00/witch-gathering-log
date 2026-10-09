"""R2 gear functions + R3 idle ledger + actual R4 battle receipt.
An in-memory, reference-only transaction bridge. No production saves touched.
Intro tasks/deep-forest survey completion are explicit authored fixtures, NOT
real battles or player elapsed-time measurements.
"""
from __future__ import annotations
from dataclasses import dataclass,field,asdict,replace
from collections import Counter
from pathlib import Path
import copy,json,sys
from battle_model import g,ROOT,Battle,PartyInput,ORDER,sha
sys.path.insert(0,str(ROOT/'source/economy_r3/tools'))
import economy_model as e
LOCAL=json.loads((ROOT/'data/LOCAL_CANDIDATES.json').read_text())
WEAPONS={'C_WITCH':'EQ_W_01','C_FAMILIAR':'EQ_F_01','C_APPRENTICE':'EQ_A_01','C_SMITH':'EQ_S_01'}
ENEMIES={x['id']:x for x in g.WORLD['enemies']}

@dataclass
class Campaign:
    eco:e.State
    gates:set=field(default_factory=lambda:{'G_START'})
    clears:set=field(default_factory=lambda:{'A_R01_01'})
    items:dict=field(default_factory=dict)
    equipped:dict=field(default_factory=dict)
    joined_events:set=field(default_factory=set)
    applied:dict=field(default_factory=dict)
    verified_battles:dict=field(default_factory=dict)
    completed_battles:set=field(default_factory=set)
    known_evolved:set=field(default_factory=set)
    spent_materials:dict=field(default_factory=dict)
    spent_dust:int=0
    history:list=field(default_factory=list)

    def snapshot(self,focus=None):
        return e.Snapshot('R01',tuple(sorted(self.gates)),tuple(a for a in ORDER if a in self.eco.roster_xp),tuple(sorted(self.known_evolved)),focus,None,tuple(sorted(self.clears)))
    def gate(self):return max(self.gates,key=lambda x:g.GATES[x])
    def inventory_hash(self):
        return sha({'eco':asdict(self.eco),'gates':sorted(self.gates),'clears':sorted(self.clears),'items':{u:asdict(i) for u,i in self.items.items()},'equipped':self.equipped,'joined':sorted(self.joined_events),'applied':self.applied,'known':sorted(self.known_evolved),'spent_materials':self.spent_materials,'spent_dust':self.spent_dust})
    def insert(self,item):
        if item.uid in self.items:
            if self.items[item.uid]!=item:raise ValueError('uid collision')
            return
        g.validate_item(item);self.items[item.uid]=item
    def equip(self,uid,aid):
        if aid not in self.eco.roster_xp:raise ValueError('unjoined actor')
        item=self.items[uid];template=g.GEAR[item.template_id]
        if aid not in template['actor_ids']:raise ValueError('wrong species/actor')
        if template['unlock_gate'] not in self.gates:raise ValueError('future gear')
        if any(uid in ids and actor!=aid for actor,ids in self.equipped.items()):raise ValueError('duplicate owner')
        slot=template['slot'];current=self.equipped.get(aid,[])
        nextids=[u for u in current if g.GEAR[self.items[u].template_id]['slot']!=slot]+[uid]
        load=copy.deepcopy(self.equipped);load[aid]=nextids
        g.validate_party_loadout({a:[self.items[u] for u in us] for a,us in load.items()});self.equipped=load
    def loadout(self):
        result=[]
        for aid in ORDER:
            if aid in self.eco.roster_xp:
                items=[self.items[u] for u in self.equipped.get(aid,[])]
                lev=g.level_from_xp(self.eco.roster_xp[aid]);g.validate_progression(aid,lev,0,self.gate(),items)
                result.append(PartyInput(aid,lev,tuple(items)))
        return result
    def natural_bridge(self):
        for r in self.eco.gear:
            it=g.Item(r['uid'],r['template_id'],r['quality'],r['rank'],r['enhancement'],tuple(g.Affix(**a) for a in r['latent_affixes']),invested_dust=r['invested_dust'])
            self.insert(it)
    def advance(self,ms,focus=None,op=None):
        if ms<0:raise ValueError('negative time')
        s=self.snapshot(focus);s.validate()
        self.eco=e.select_route(self.eco,s,self.eco.last_wall_ms)
        self.eco=e.advance_to(self.eco,self.eco.last_wall_ms+ms,s,op or f'work:{self.eco.last_wall_ms}:{ms}:{focus}')
        self.natural_bridge()
    def record_presence(self,key):
        self.eco=e.acknowledge_presence(self.eco,self.eco.last_wall_ms,key)
    def pay(self,mats,dust):
        if dust<0 or any(n<0 for n in mats.values()):raise ValueError('negative cost')
        if self.eco.dust<dust or any(self.eco.materials.get(m,0)<n for m,n in mats.items()):raise ValueError('insufficient resources')
        for m,n in mats.items():self.eco.materials[m]-=n;self.spent_materials[m]=self.spent_materials.get(m,0)+n
        self.eco.dust-=dust;self.spent_dust+=dust
    def enhance(self,uid,op):
        sig=sha(['enhance',uid])
        if op in self.applied:
            if self.applied[op]!=sig:raise ValueError('op collision')
            return
        new,cost=g.enhance_item(self.items[uid],self.gate())
        self.pay({},cost);self.items[uid]=new;self.applied[op]=sig
    def craft(self,template,uid,op,seed='craft-fixed'):
        sig=sha(['craft',template,uid,seed])
        if op in self.applied:
            if self.applied[op]!=sig:raise ValueError('op collision')
            return self.items[uid]
        if uid in self.items:raise ValueError('item exists')
        recipe=g.RECIPES[template]
        if g.GEAR[template]['parent_template_id']:raise ValueError('not a craft-new recipe')
        if g.GEAR[template]['unlock_gate'] not in self.gates:raise ValueError('recipe locked')
        if not set(g.GEAR[template]['actor_ids'])&set(self.eco.roster_xp):raise ValueError('no eligible member')
        if recipe['station']=='forge' and 'C_SMITH' not in self.joined_events:raise ValueError('smith join pending')
        it=g.create_item(uid,template,'Q2',seed=seed,crafted=True)
        self.pay({x['material_id']:x['quantity'] for x in recipe['ingredients']},0)
        self.items[uid]=it;self.applied[op]=sig;return it
    def collect_cost(self,operations):
        mats,dust=e.aggregate_cost(operations)
        for oid,n in operations:
            if e.COSTS[oid]['gate'] not in self.gates:raise ValueError('future operation')
        start=self.eco.credited_ms
        for j,job in enumerate(e.goal_units(mats,self.eco.materials,self.eco.source_progress)):
            # R3 snapshot validation forbids future sources and uncleared routes.
            self.advance(job['units']*e.WORK_MS,job['source_id'])
        if self.eco.dust<dust:
            rate=e.RATES['R01']['dust_per_work'];units=(dust-self.eco.dust+rate-1)//rate;self.advance(units*e.WORK_MS)
        return self.eco.credited_ms-start
    def battle(self,boss_id,seed,record=False,disabled=frozenset(),boss_override=None):
        en=ENEMIES[boss_id]
        if en['encounter_gate'] not in self.gates:raise ValueError('future boss')
        if boss_id=='B_R01_B' and set(self.eco.roster_xp)!=set(ORDER):raise ValueError('four-member join not complete')
        boss=copy.deepcopy(boss_override or LOCAL['bosses'][boss_id])
        before=self.inventory_hash();result=Battle(self.loadout(),boss,seed,record,disabled).run()
        rid=sha([before,boss_id,seed,result['input_fingerprint'],result['outcome']])
        receipt={'battle_id':rid,'boss_id':boss_id,'outcome':result['outcome'],'snapshot_hash':before,'result_hash':sha(result),'elapsed_ms':result['elapsed_ms']}
        self.verified_battles[rid]=copy.deepcopy(receipt)
        return result,copy.deepcopy(receipt)
    def commit_victory(self,receipt,fail_before_commit=False):
        bid=receipt['battle_id']
        if self.verified_battles.get(bid)!=receipt:raise ValueError('unverified or tampered receipt')
        if bid in self.completed_battles:return
        if receipt['outcome']!='VICTORY':raise ValueError('no victory')
        if receipt['snapshot_hash']!=self.inventory_hash():raise ValueError('stale battle snapshot')
        # The complete progression state is changed as one in-memory candidate.
        nxt=copy.deepcopy(self);boss=receipt['boss_id'];world_enemy=ENEMIES[boss]
        nxt.eco=e.first_boss_reward(nxt.eco,boss,boss in nxt.eco.first_rewards,victory_confirmed=True,gates=nxt.gates)
        nxt.gates.add(world_enemy['victory_gate']);nxt.clears.add(world_enemy['area_id']);nxt.completed_battles.add(bid)
        nxt.history.append({'event':'boss_first_or_replay_commit','boss_id':boss,'battle_id':bid,'outcome':'VICTORY','time_ms':nxt.eco.last_wall_ms})
        if fail_before_commit:raise RuntimeError('injected-before-commit')
        self.__dict__.update(nxt.__dict__)
    def join(self,actor_id):
        if actor_id in self.joined_events:return
        if actor_id not in ('C_APPRENTICE','C_SMITH') or 'G_R01_A' not in self.gates:raise ValueError('join gate')
        self.eco=e.join_actor(self.eco,actor_id,self.gates);uid='grant:'+actor_id
        self.insert(g.create_item(uid,WEAPONS[actor_id],starter=True,seed='fixed-starter'));self.joined_events.add(actor_id)
        self.equip(uid,actor_id);self.history.append({'event':'join','actor':actor_id,'xp':self.eco.roster_xp[actor_id]})
    def survey_deep_fixture(self):
        if 'G_R01_A' not in self.gates:raise ValueError('gate')
        self.clears.add('A_R01_03');self.history.append({'event':'EXPLICIT_UNSIMULATED_ROUTE_CLEARANCE_FIXTURE','area':'A_R01_03'})
    def evolve(self,uid,target,op):
        sig=sha(['evolve',uid,target])
        if op in self.applied:
            if self.applied[op]!=sig:raise ValueError('op collision')
            return
        new,cost=g.evolve_preview(self.items[uid],target,self.gate(),frozenset(self.joined_events))
        self.pay(cost,0);self.items[uid]=new;self.known_evolved.add(target);self.applied[op]=sha(['evolve',uid,target])


def intro_state(seed='economy-20261009'):
    st=Campaign(e.State(seed=seed))
    for aid in ORDER[:2]:
        uid='grant:'+aid;st.insert(g.create_item(uid,WEAPONS[aid],starter=True,seed='fixed-starter'));st.equip(uid,aid);st.joined_events.add(aid)
    # R3 defines total, not eventwise distribution or affix TYPES. Explicit fixed fixture only.
    intro=e.CFG['onboarding'];st.eco.roster_xp={a:intro['xp_total'] for a in st.eco.roster_xp}
    st.eco.dust=intro['dust_total'];st.eco.materials=dict(intro['materials'])
    af=LOCAL['intro_fixed_affixes'];ids=af['visible']+[af['latent_third']]
    it=g.Item('intro:relic',intro['guaranteed_relic']['template_id'],'Q2',latent_affixes=tuple(g.Affix(a,af['roll_q']) for a in ids))
    st.insert(it);st.equip(it.uid,'C_WITCH');st.applied['R3_INTRO_FIXTURE']='already_completed_four_authored_tasks'
    st.history.append({'event':'R3_INTRO_TOTALS_FIXTURE','not_played':True,'normal_intro_fights_not_simulated':True,'xp':intro['xp_total'],'dust':intro['dust_total']})
    return st


def post_miniboss(seed=1001):
    st=intro_state();res,receipt=st.battle('B_R01_A',seed)
    if res['outcome']!='VICTORY':raise RuntimeError('intro fixture did not win; do not grant gate')
    st.commit_victory(receipt);st.join('C_APPRENTICE');st.survey_deep_fixture();st.join('C_SMITH')
    return st,res


def prepared(kind='protect',seed=1001):
    st,_=post_miniboss(seed)
    templates=['EQ_BODY_01','EQ_BODY_01','EQ_AMU_01','EQ_AMU_01'] if kind=='protect' else ['EQ_HAND_01','EQ_HAND_01','EQ_AMU_01','EQ_AMU_01']
    ops=list(Counter('RC_'+t for t in templates).items());ms=st.collect_cost(ops)
    for i,t in enumerate(templates):st.craft(t,'craft:'+str(i),'craft-op:'+str(i))
    owners=['C_SMITH','C_APPRENTICE','C_WITCH','C_APPRENTICE'] if kind=='protect' else ['C_WITCH','C_SMITH','C_WITCH','C_APPRENTICE']
    for i,a in enumerate(owners):st.equip('craft:'+str(i),a)
    st.history.append({'event':'four_items_crafted','policy':kind,'collected_ms':ms,'operations':ops,'natural_gear_not_equipped':True})
    return st
