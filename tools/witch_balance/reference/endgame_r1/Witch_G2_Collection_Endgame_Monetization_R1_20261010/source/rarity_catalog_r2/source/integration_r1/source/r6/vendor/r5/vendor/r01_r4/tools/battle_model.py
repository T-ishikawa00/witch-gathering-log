"""R01 two-boss reference slice. Not production engine, not a player test.
R2 constants/stat helpers are imported unchanged; missing boss numbers and timing
choices live in LOCAL_CANDIDATES.json. Only R01 pre-clear gear is supported.
No network, rendering, account access, database or Mac writes.
"""
from __future__ import annotations
from dataclasses import dataclass, field, asdict
from pathlib import Path
from collections import Counter
from fractions import Fraction
import sys, json, hashlib, heapq, copy
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'source/growth_r2/validation'))
import reference_model as g
SKILLS={s['skill_id']:s for s in g.DATA['skills']}
ORDER=('C_WITCH','C_FAMILIAR','C_APPRENTICE','C_SMITH')

def canonical(x):
    return json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':'))
def sha(x): return hashlib.sha256(canonical(x).encode()).hexdigest()
def floor(x): return x.numerator//x.denominator if isinstance(x,Fraction) else int(x)
def randint(seed,domain,index,n):
    return g.deterministic_int(str(seed),canonical([domain,index]),n)

@dataclass
class Shield:
    source:str
    amount:int
    expiry:int
    uid:int

@dataclass
class Actor:
    id:str
    level:int
    stats:dict
    hp:int
    basic_at:int
    busy_until:int=0
    casting:dict|None=None
    ready:dict=field(default_factory=dict)
    counts:dict=field(default_factory=dict)
    shields:list=field(default_factory=list)
    counter_at:int=0
    chase_at:int=0
    echo_at:int=0
    echo_expiry:int=0
    echo_charges:int=0
    cover_expiry:int=0
    cover_charges:int=0
    seen_counter:set=field(default_factory=set)
    seen_chase:set=field(default_factory=set)

@dataclass(frozen=True)
class PartyInput:
    actor_id:str
    level:int
    items:tuple
    awakening:int=0

class Battle:
    """Integer-ms event queue. Priority: DOT, expiry, commits, reactions, AI.
    Frozen gear; no tactics or user intervention. One R01 boss, 2 or 4 allies.
    Detailed telemetry belongs to the validation tool, not player-facing AI.
    """
    def __init__(self,party:list[PartyInput],boss:dict,seed:int|str,
                 record:bool=False,disabled=frozenset(),timing_mode='first_impact_at_interval'):
        if not party or len({p.actor_id for p in party})!=len(party):raise ValueError('invalid roster')
        g.validate_party_loadout({p.actor_id:list(p.items) for p in party})
        self.boss=copy.deepcopy(boss);self.seed=str(seed);self.record=record
        self.disabled=set(disabled);self.timing_mode=timing_mode
        self.actors={};self.now=0;self.seq=0;self.queue=[];self.pending_wakes=set()
        self.telegraphs={};self.serial=0;self.logs=[];self.metrics=Counter();self.per_actor={};self.forecast_cache={}
        self.poison=g.PoisonSchedule();self.poison_power=0;self.poison_bonus=0
        self.mark_expiry=0;self.weaken_expiry=0;self.boss_hp=boss['hp']
        self.outcome=None;self.iterations=0;self.transitions=0
        self.time_limit=boss.get('time_limit_ms',g.DATA['combat']['time_limit_ms'])
        for p in sorted(party,key=lambda p:ORDER.index(p.actor_id)):
            if p.awakening:raise ValueError('R01 first-clear slice does not support awakening')
            for it in p.items:
                if g.GEAR[it.template_id]['unlock_gate'] not in ('G_START','G_R01_A') or g.GEAR[it.template_id]['core_rules']:
                    raise ValueError('unsupported future/core-rule item in R01 slice')
            st=g.actor_stats(p.actor_id,p.level,list(p.items),p.awakening)
            interval=g.scaled_basic_interval(g.ACTORS[p.actor_id]['basic_interval_ms'],st.get('haste_bp',0))
            first_start=interval-SKILLS[p.actor_id+'_BASIC']['windup_ms'] if timing_mode=='first_impact_at_interval' else interval
            self.actors[p.actor_id]=Actor(p.actor_id,p.level,st,st['hp'],first_start)
            self.per_actor[p.actor_id]=Counter()
        self.input_fingerprint=sha({'party':[{'actor_id':p.actor_id,'level':p.level,'items':[asdict(i) for i in p.items]} for p in party], 'boss':boss,'seed':self.seed,'disabled':sorted(disabled),'timing':timing_mode})
        w=self.actors.get('C_WITCH')
        if w and 'start_barrier' not in self.disabled:
            amount=floor(Fraction(w.stats['power'])*(10000+w.stats.get('barrier_bonus_bp',0))/10000)
            self.add_shield(w.id,w.id,amount,6000)
        for aid in self.actors:self.wake(aid,0)
        self.push(boss['first_telegraph_ms'],2,'telegraph',{'index':0})
        self.push(self.time_limit,6,'timeout',{})

    def log(self,kind,**values):
        if self.record:self.logs.append({'t_ms':self.now,'kind':kind,**values})
    def push(self,t,priority,kind,payload):
        if t<self.now:raise AssertionError('event in past')
        self.seq+=1;heapq.heappush(self.queue,(t,priority,self.seq,kind,payload))
    def wake(self,aid,t):
        a=self.actors[aid]
        if a.hp<=0:return
        t=max(t,self.now)
        k=(aid,t)
        if k not in self.pending_wakes:
            self.pending_wakes.add(k);self.push(t,4,'ai',{'aid':aid})
    def wake_all(self,t=None):
        for aid in self.actors:self.wake(aid,self.now if t is None else t)
    def add_shield(self,source,target,amount,duration):
        a=self.actors[target]
        actual=g.barrier_add(sum(s.amount for s in a.shields),a.stats['hp'],amount)
        if not a.hp or actual<=0:return 0
        self.serial+=1;s=Shield(source,actual,self.now+duration,self.serial)
        a.shields.append(s);self.push(s.expiry,1,'expire_shield',{'target':target,'uid':s.uid})
        self.metrics['barrier_granted']+=actual;self.per_actor[source]['barrier_granted']+=actual
        self.log('barrier',source=source,target=target,amount=actual,expiry=s.expiry)
        return actual
    def shield_total(self,a):return sum(s.amount for s in a.shields)
    def end_check(self):
        if self.boss_hp<=0:self.outcome='VICTORY'
        elif not any(a.hp>0 for a in self.actors.values()):self.outcome='DEFEAT'
        return self.outcome is not None
    def weights(self):
        table=g.DATA['combat']['party_target_weights'] if 'C_SMITH' in self.actors else g.DATA['combat']['pre_smith_weights']
        return [(aid,table.get(aid,10)) for aid,a in self.actors.items() if a.hp>0]
    def target(self,index):
        weights=self.weights();roll=randint(self.seed,'enemy-target',index,sum(v for _,v in weights))
        for aid,weight in weights:
            if roll<weight:return aid
            roll-=weight
        raise AssertionError('target selection')
    def enemy_raw(self,action,ignore_weaken=False):
        v=Fraction(self.boss['power']*action['coefficient_bp'],10000)
        if self.weaken_expiry>self.now and not ignore_weaken:v*=Fraction(8800,10000)
        return floor(v)
    def incoming(self,a,action,guard=False,redirect=False):
        reduction=a.stats.get('heavy_reduction_bp',0) if action.get('heavy') else 0
        if redirect:reduction+=1500
        return g.direct_incoming(self.enemy_raw(action),a.stats['defense'],self.boss['level'],guard,reduction)
    def reserved(self,aid,kind,before):
        result=0
        for a in self.actors.values():
            c=a.casting
            if a.hp and c and c['target']==aid and c['finish']<before:
                sk=c['skill']
                if kind=='heal' and sk=='SK_A_HEAL':result+=self.heal_nominal(a)
                if kind=='barrier' and sk=='SK_A_WARD':result+=self.ward_nominal(a)
        return result
    def public_forecast(self,without_cover=False):
        """Published telegraphs only; simulate existing/pending cover without mutation."""
        if without_cover in self.forecast_cache:return self.forecast_cache[without_cover]
        hits=[];smith=self.actors.get('C_SMITH')
        charges=smith.cover_charges if smith and smith.cover_expiry>self.now else 0
        expiry=smith.cover_expiry if smith else 0
        pending=smith.casting if smith and smith.hp and smith.casting and smith.casting['skill']=='SK_S_GUARD' else None
        for tele in sorted(self.telegraphs.values(),key=lambda x:x['hits'][0]):
            remaining=tele['hits'][tele.get('processed_hits',0):]
            if not remaining or remaining[-1]<self.now:continue
            act=tele['action'];first=remaining[0]
            if act['aoe']:
                for t in remaining:
                    if self.now<=t<=self.now+1500:
                        for aid,a in self.actors.items():
                            if a.hp:hits.append((t,aid,act,False))
                continue
            original=tele['target'];target=tele.get('resolved_target') or original
            if target and not self.actors[target].hp:target=original if self.actors[original].hp else None
            if pending and pending['finish']<first:
                charges=2;expiry=pending['finish']+4000;pending=None
            if not without_cover and not tele.get('resolved_target') and smith and smith.hp and charges and expiry>first:
                estimate=sum(self.incoming(smith,act,redirect=True) for t in remaining)
                if smith.hp*10000>smith.stats['hp']*3500 and max(0,estimate-self.shield_total(smith))<smith.hp:
                    target=smith.id;charges-=1
            if target:
                for t in remaining:
                    if self.now<=t<=self.now+1500:hits.append((t,target,act,target!=original))
        result=sorted(hits,key=lambda x:(x[0],ORDER.index(x[1])))
        self.forecast_cache[without_cover]=result
        return result
    def danger_for(self,aid,without_cover=False):
        a=self.actors[aid];shields=self.shield_total(a);loss=0;single=0
        relevant=[x for x in self.public_forecast(without_cover) if x[1]==aid]
        for time,target,act,redirect in relevant:
            inc=self.incoming(a,act,redirect=redirect)
            effective=max(0,inc-shields);shields=max(0,shields-inc)
            loss+=effective;single=max(single,effective)
        if relevant:
            first=relevant[0][0]
            reserve_s=self.reserved(aid,'barrier',first);reserve_h=self.reserved(aid,'heal',first)
            loss=max(0,loss-reserve_s);single=max(0,single-reserve_s)
            projected=min(a.stats['hp'],a.hp+reserve_h)-loss
        else:projected=a.hp
        danger=bool(relevant) and (single*10000>=a.stats['hp']*2000 or projected*10000<=a.stats['hp']*3500)
        return danger,loss,projected
    def guard_needed(self,a):
        if 'cover' in self.disabled or a.hp*10000<=a.stats['hp']*3500:return False
        if a.cover_expiry>self.now and a.cover_charges:return False
        for tele in self.telegraphs.values():
            act=tele['action'];target=tele.get('resolved_target') or tele['target']
            if act['aoe'] or not target or target not in self.actors or not self.actors[target].hp:continue
            if not any(self.now<=t<=self.now+1500 for t in tele['hits'][tele.get('processed_hits',0):]):continue
            d,_,_=self.danger_for(target,without_cover=True)
            est=sum(self.incoming(a,act,redirect=True) for t in tele['hits'][tele.get('processed_hits',0):] if t>=self.now)
            if d and max(0,est-self.shield_total(a))<a.hp:return True
        return False
    def heal_nominal(self,a):return floor(Fraction(a.stats['power']*22000,10000)*Fraction(10000+a.stats.get('heal_bonus_bp',0),10000))
    def ward_nominal(self,a):return floor(Fraction(a.stats['power']*15000,10000)*Fraction(10000+a.stats.get('barrier_bonus_bp',0),10000))
    def heal_target(self,a):
        arr=[]
        for aid,t in self.actors.items():
            if not t.hp:continue
            hp=min(t.stats['hp'],t.hp+self.reserved(aid,'heal',self.now+300))
            danger,_,proj=self.danger_for(aid)
            if hp<t.stats['hp'] and (hp*10000<=t.stats['hp']*7000 or (danger and proj*10000<=t.stats['hp']*3500)):
                arr.append((Fraction(hp,t.stats['hp']),ORDER.index(aid),aid))
        return min(arr)[2] if arr else None
    def ward_target(self,a):
        arr=[]
        for aid,t in self.actors.items():
            if not t.hp:continue
            d,_,_=self.danger_for(aid)
            barrier=self.shield_total(t)+self.reserved(aid,'barrier',self.now+250)
            if barrier>=t.stats['hp']*3500//10000:continue
            if d or t.hp*10000<=t.stats['hp']*5000:
                arr.append((0 if d else 1,Fraction(t.hp,t.stats['hp']),ORDER.index(aid),aid))
        return min(arr)[3] if arr else None
    def choose(self,a):
        available=lambda sk:a.ready.get(sk,0)<=self.now
        if a.id=='C_SMITH':
            if available('SK_S_GUARD') and self.guard_needed(a):return 'SK_S_GUARD',a.id
            if available('SK_S_HAMMER'):return 'SK_S_HAMMER','boss'
        elif a.id=='C_APPRENTICE':
            heal=self.heal_target(a) if 'heal' not in self.disabled else None
            ward=self.ward_target(a) if 'ward' not in self.disabled else None
            # Survival barrier takes precedence only for lethal telegraphed impact.
            if ward and available('SK_A_WARD') and self.danger_for(ward)[2]<=0:return 'SK_A_WARD',ward
            if heal and available('SK_A_HEAL'):return 'SK_A_HEAL',heal
            if ward and available('SK_A_WARD'):return 'SK_A_WARD',ward
        elif a.id=='C_WITCH':
            if available('SK_W_SEED') and 'poison' not in self.disabled and (self.poison.stacks<5 or self.poison.expires_ms-self.now<=2000):return 'SK_W_SEED','boss'
            if available('SK_W_BURST'):return 'SK_W_BURST','boss'
        elif a.id=='C_FAMILIAR':
            if available('SK_F_MARK') and self.mark_expiry-self.now<=1000:return 'SK_F_MARK','boss'
            if available('SK_F_DASH'):return 'SK_F_DASH','boss'
        if a.basic_at<=self.now:return a.id+'_BASIC','boss'
        return None
    def raw_outgoing(self,a,coefficient,crit_allowed,kind,root):
        bonus=a.stats.get('direct_bonus_bp',0)
        if a.id=='C_WITCH' and self.mark_expiry>self.now:bonus+=800
        if kind=='active' and a.echo_charges and a.echo_expiry>self.now:
            bonus+=1500;a.echo_charges-=1;self.metrics['echo_consumed']+=1
        if kind=='counter':bonus+=a.stats.get('counter_bonus_bp',0)
        if kind=='chase':bonus+=a.stats.get('chase_bonus_bp',0)
        v=Fraction(a.stats['power']*coefficient,10000)*Fraction(10000+bonus,10000)
        crit=crit_allowed and randint(self.seed,'crit.'+a.id,root,10000)<a.stats['crit_chance_bp']
        if crit:v*=Fraction(a.stats['crit_multiplier_bp'],10000)
        if self.mark_expiry>self.now:v*=Fraction(10600,10000)
        return floor(v),bool(crit)
    def outgoing(self,a,coefficient,crit_allowed,kind,root,skill):
        raw,crit=self.raw_outgoing(a,coefficient,crit_allowed,kind,root)
        damage=g.direct_incoming(raw,self.boss['defense'],a.level)
        # Vulnerable recovery is NOT extra damage in this candidate; simply no boss action.
        dealt=min(damage,self.boss_hp);self.boss_hp-=dealt
        self.metrics['damage_'+kind]+=dealt;self.per_actor[a.id]['damage_'+kind]+=dealt
        self.metrics['crit_count']+=crit
        self.log('damage',source=a.id,target=self.boss['id'],skill=skill,kind_damage=kind,raw=raw,hp_loss=dealt,crit=crit,boss_hp=self.boss_hp,root=root)
        if self.end_check():return dealt
        cat=self.actors.get('C_FAMILIAR')
        if kind=='active' and a.id!='C_FAMILIAR' and dealt>0 and (self.mark_expiry>self.now or self.poison.stacks>0) and cat and cat.hp and 'chase' not in self.disabled and self.now>=cat.chase_at and root not in cat.seen_chase:
            cat.seen_chase.add(root);cat.chase_at=self.now+2000
            self.push(self.now,3,'reaction',{'aid':cat.id,'kind':'chase','coefficient':4000,'root':root})
        return dealt
    def execute_actor(self,payload):
        aid=payload['aid'];a=self.actors[aid];c=a.casting
        if not a.hp or not c or c['root']!=payload['root']:
            self.metrics['dead_or_cancelled_commit']+=1;return
        sk=c['skill'];target=c['target'];spec=SKILLS[sk];success=True
        if spec['kind']=='basic':self.outgoing(a,10000,True,'basic',c['root'],sk)
        elif sk in ('SK_W_BURST','SK_S_HAMMER','SK_F_DASH'):
            coefficient=spec['effects'][0]['coefficient_bp']
            if sk=='SK_F_DASH' and (self.mark_expiry>self.now or self.poison.stacks>0):coefficient+=4000
            self.outgoing(a,coefficient,True,'active',c['root'],sk)
            if sk=='SK_S_HAMMER' and not self.outcome:
                self.weaken_expiry=self.now+6000;self.push(self.weaken_expiry,1,'wake_all',{})
        elif sk=='SK_W_SEED':
            self.outgoing(a,2500,False,'active',c['root'],sk)
            if not self.outcome:
                was=self.poison.stacks
                # A due tick is independently processed at priority 0.
                self.poison.clock_ms=self.now;self.poison.add_after_advance(self.now,2,5)
                self.poison_power=a.stats['power'];self.poison_bonus=a.stats.get('dot_bonus_bp',0)
                if not was:self.push(self.poison.next_tick_ms,0,'dot',{})
                self.push(self.poison.expires_ms,1,'expire_poison',{})
                self.log('poison_apply',source=aid,stacks=self.poison.stacks,expiry=self.poison.expires_ms)
        elif sk=='SK_F_MARK':
            self.mark_expiry=self.now+8000;self.push(self.mark_expiry,1,'wake_all',{})
            self.wake(aid,max(self.now,self.mark_expiry-1000));self.log('mark',source=aid,expiry=self.mark_expiry)
        elif sk=='SK_A_HEAL':
            if not self.actors[target].hp:target=self.heal_target(a)
            if target:
                t=self.actors[target];r=g.apply_heal(t.hp,t.stats['hp'],self.heal_nominal(a));t.hp=r['hp_after']
                success=r['effective']>0;self.metrics['effective_heal']+=r['effective'];self.per_actor[aid]['effective_heal']+=r['effective']
                self.log('heal',source=aid,target=target,**r)
                if success and r['effective']*20>=t.stats['hp'] and self.now>=a.echo_at and 'echo' not in self.disabled:
                    targets=[x for x in self.actors.values() if x.hp and x.id!=aid]
                    if targets:
                        receiver=next((x for x in targets if x.id=='C_WITCH'),max(targets,key=lambda x:(x.stats['power'],-ORDER.index(x.id))))
                        receiver.echo_expiry=self.now+8000;receiver.echo_charges=1;a.echo_at=self.now+6000
                        self.metrics['echo_granted']+=1;self.log('echo',source=aid,target=receiver.id)
            else:success=False
        elif sk=='SK_A_WARD':
            if not self.actors[target].hp:target=self.ward_target(a)
            if target:
                nominal=self.ward_nominal(a)*(10000+self.actors[target].stats.get('barrier_received_bp',0))//10000
                success=self.add_shield(aid,target,nominal,6000)>0
            else:success=False
        elif sk=='SK_S_GUARD':
            a.cover_expiry=self.now+4000;a.cover_charges=2
            self.push(a.cover_expiry,1,'wake_all',{});self.log('cover_stance',source=aid,expiry=a.cover_expiry)
        else:raise ValueError('unsupported skill '+sk)
        a.casting=None
        if success:
            self.metrics['cast_'+sk]+=1;self.per_actor[aid]['cast_'+sk]+=1
            if spec['kind']=='basic':
                gap=g.scaled_basic_interval(g.ACTORS[aid]['basic_interval_ms'],a.stats.get('haste_bp',0))
                a.basic_at=self.now+gap-(spec['windup_ms'] if self.timing_mode=='first_impact_at_interval' else 0)
            else:
                a.ready[sk]=self.now+g.scaled_skill_cd(spec['cooldown_ms'],a.stats.get('cdr_bp',0))
                self.wake(aid,a.ready[sk])
            a.busy_until=self.now+spec['recovery_ms']
        else:
            a.ready[sk]=self.now+500;a.busy_until=self.now+100
            self.metrics['whiff']+=1;self.wake(aid,a.ready[sk])
        self.wake(aid,a.busy_until);self.wake_all()
    def hit_enemy(self,payload):
        tele=self.telegraphs.get(payload['root'])
        if not tele or self.outcome:return
        action=tele['action'];i=payload['hit_index'];a_smith=self.actors.get('C_SMITH')
        targets=[aid for aid,a in self.actors.items() if a.hp] if action['aoe'] else [tele.get('resolved_target') or tele['target']]
        redirected=False
        if not action['aoe']:
            original=tele['target']
            if i==0 and a_smith and a_smith.hp and a_smith.cover_expiry>self.now and a_smith.cover_charges>0:
                est=sum(self.incoming(a_smith,action,redirect=True) for _ in tele['hits'])
                if a_smith.hp*10000>a_smith.stats['hp']*3500 and max(0,est-self.shield_total(a_smith))<a_smith.hp:
                    tele['resolved_target']=a_smith.id;a_smith.cover_charges-=1
            target=tele.get('resolved_target') or original
            if not self.actors[target].hp:
                target=original if self.actors[original].hp else None
            targets=[target] if target else []
            redirected=bool(target and target!=original)
        for aid in targets:
            a=self.actors[aid];chance=a.stats['guard_chance_bp']
            if a.cover_expiry>self.now:chance=min(4500,chance+1500)
            guarded=randint(self.seed,'guard.'+aid,canonical([payload['root'],i]),10000)<chance
            incoming=self.incoming(a,action,guarded,redirected)
            rem=incoming;absorbed=0
            for s in sorted(a.shields,key=lambda s:(s.expiry,s.source,s.uid)):
                used=min(rem,s.amount);s.amount-=used;rem-=used;absorbed+=used
                self.per_actor[s.source]['barrier_absorbed']+=used
            a.shields=[s for s in a.shields if s.amount>0]
            loss=min(a.hp,rem);a.hp-=loss
            self.metrics['received_hp']+=loss;self.metrics['barrier_absorbed']+=absorbed
            self.metrics['guarded_hits']+=guarded;self.metrics['cover_hits']+=redirected
            self.per_actor[aid]['received_hp']+=loss
            if redirected:self.per_actor[aid]['covered_hp_loss']+=loss
            self.log('enemy_hit',source=self.boss['id'],target=aid,original_target=tele['target'],root=payload['root'],hit_index=i,action=action['id'],hp_loss=loss,absorbed=absorbed,guard=guarded,redirected=redirected,hp=a.hp)
            if a.hp==0:
                a.casting=None;self.metrics['deaths']+=1;self.log('death',actor=aid)
            if self.end_check():return
            if aid=='C_SMITH' and (guarded or redirected) and loss+absorbed>0 and a.hp and 'counter' not in self.disabled and self.now>=a.counter_at and payload['root'] not in a.seen_counter:
                a.seen_counter.add(payload['root']);a.counter_at=self.now+1500
                self.push(self.now,3,'reaction',{'aid':aid,'kind':'counter','coefficient':7500,'root':payload['root']})
        tele['processed_hits']=i+1
        if i==len(tele['hits'])-1:tele['finished']=True
        self.wake_all()
    def handle(self,kind,p):
        self.forecast_cache={}
        if kind=='ai':
            aid=p['aid'];self.pending_wakes.discard((aid,self.now));a=self.actors[aid]
            if not a.hp:return
            if a.casting:return
            if a.busy_until>self.now:self.wake(aid,a.busy_until);return
            chosen=self.choose(a)
            if chosen:
                sk,target=chosen;sp=SKILLS[sk]
                cnt=a.counts.get(sk,0)+1;a.counts[sk]=cnt;root=f'{aid}:{sk}:{cnt}'
                a.casting={'skill':sk,'target':target,'root':root,'finish':self.now+sp['windup_ms']}
                self.push(a.casting['finish'],2,'actor_commit',{'aid':aid,'root':root})
                self.log('cast_start',source=aid,skill=sk,target=target,commit_ms=a.casting['finish'],root=root)
            else:
                future=[x for x in [a.basic_at,*a.ready.values()] if x>self.now]
                if future:self.wake(aid,min(future))
        elif kind=='actor_commit':self.execute_actor(p)
        elif kind=='telegraph':
            index=p['index'];action=self.boss['actions'][index%len(self.boss['actions'])];root='enemy:'+str(index)
            target=None if action['aoe'] else self.target(index)
            times=[self.now+action['windup_ms']+v for v in action['hit_offsets_ms']]
            self.telegraphs[root]={'target':target,'resolved_target':None,'action':action,'hits':times,'end':times[-1]}
            self.log('telegraph',root=root,action=action['id'],target=target,hits=times,raw=self.enemy_raw(action))
            for i,t in enumerate(times):self.push(t,2,'enemy_hit',{'root':root,'hit_index':i})
            nexttime=times[-1]+action['recovery_ms']+action.get('rest_ms',0)
            self.push(nexttime,2,'telegraph',{'index':index+1});self.wake_all()
            self.push(max(self.now,times[0]-1500),2,'wake_all',{})
        elif kind=='enemy_hit':self.hit_enemy(p)
        elif kind=='reaction':
            a=self.actors[p['aid']]
            if a.hp:
                self.metrics['reaction_'+p['kind']]+=1
                self.outgoing(a,p['coefficient'],False,p['kind'],p['root'],'PS_'+p['kind'])
        elif kind=='dot':
            if self.poison.next_tick_ms!=self.now or not self.poison.stacks or self.now>self.poison.expires_ms:return
            dmg=g.poison_tick(self.poison_power,self.poison.stacks,1,self.poison_bonus,self.boss.get('dot_resist_bp',0))
            dealt=min(self.boss_hp,dmg);self.boss_hp-=dealt;self.metrics['damage_dot']+=dealt
            self.per_actor['C_WITCH']['damage_dot']+=dealt;self.log('dot',source='C_WITCH',hp_loss=dealt,stacks=self.poison.stacks,boss_hp=self.boss_hp)
            self.poison.next_tick_ms=self.now+1000
            self.push(self.poison.next_tick_ms,0,'dot',{})
            self.end_check();self.wake_all()
        elif kind=='expire_poison':
            if self.now>=self.poison.expires_ms:self.poison.stacks=0;self.poison.next_tick_ms=None;self.wake_all()
        elif kind=='expire_shield':
            a=self.actors[p['target']];a.shields=[s for s in a.shields if s.uid!=p['uid']];self.wake_all()
        elif kind=='wake_all':self.wake_all()
        elif kind=='timeout':self.outcome='TIMEOUT'
        else:raise ValueError(kind)
    def run(self):
        while self.queue and not self.outcome:
            t,priority,seq,kind,p=heapq.heappop(self.queue);self.now=t;self.iterations+=1
            if self.iterations>200000:raise RuntimeError('event safety limit')
            self.handle(kind,p)
        result={'outcome':self.outcome,'elapsed_ms':self.now,'boss_remaining_hp':self.boss_hp,
                'party_remaining_hp':{aid:a.hp for aid,a in self.actors.items()},
                'metrics':dict(self.metrics),'per_actor':{aid:dict(v) for aid,v in self.per_actor.items()},
                'event_iterations':self.iterations,'input_fingerprint':self.input_fingerprint,
                'timing_mode':self.timing_mode,'provenance':'R2 formulas + R4 local candidate encounter/timing overlay'}
        if self.record:result['log']=self.logs;result['log_sha256']=sha(self.logs)
        return result
