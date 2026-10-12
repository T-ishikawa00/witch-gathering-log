"""R6 candidate-only support decisions over immutable R5 combat mechanics.
No AI presets/UI, future-seed lookup, shadow battle, stats or cooldown changes.
Every policy here is a DEVELOPMENT comparator, not a player option.
"""
from __future__ import annotations
from dataclasses import dataclass, asdict
from fractions import Fraction
from bootstrap import BattleR5, Profile, SKILLS, ORDER, sha

@dataclass(frozen=True)
class SupportPolicy:
    name: str
    packet_guard: bool = False
    predictive_ward: bool = False
    deficit_heal: bool = False
    whole_packet: bool = False
    urgent_choice: bool = False
    heal_min_use_bp: int = 5000
    ward_min_use_bp: int = 5000
    heal_rank: str = "effective_amount"
    packet_danger: bool = False
    timed_ward_value: bool = False

POLICIES = {
    'guard_only': SupportPolicy('guard_only', packet_guard=True),
    'guard_ward': SupportPolicy('guard_ward', True, True),
    'utility': SupportPolicy('utility', True, True, True),
    'packet_utility': SupportPolicy('packet_utility', True, True, True, True),
    'packet_urgent': SupportPolicy('packet_urgent', True, True, True, True, True),
    'ratio_heal': SupportPolicy('ratio_heal',True,True,True,True,heal_rank='lowest_ratio'),
    'ratio_heal25': SupportPolicy('ratio_heal25',True,True,True,True,heal_min_use_bp=2500,heal_rank='lowest_ratio'),
    'ratio_heal75': SupportPolicy('ratio_heal75',True,True,True,True,heal_min_use_bp=7500,heal_rank='lowest_ratio'),
    'packet_risk': SupportPolicy('packet_risk',False,True,True,True,heal_rank='lowest_ratio',packet_danger=True),
    'packet_risk_old_heal': SupportPolicy('packet_risk_old_heal',False,True,False,True,packet_danger=True),
    'timed_support': SupportPolicy('timed_support',True,True,True,True,heal_rank='lowest_ratio',timed_ward_value=True),
}

class BattleR6(BattleR5):
    def __init__(self, *args, support_policy=None, decision_trace=False, **kwargs):
        self.support_policy = support_policy or POLICIES['packet_utility']
        self.decision_trace = decision_trace
        super().__init__(*args, **kwargs)
        self.input_fingerprint = sha({'r5': self.input_fingerprint, 'support_policy': asdict(self.support_policy)})

    def public_forecast(self, without_cover=False):
        if not self.support_policy.whole_packet:
            return super().public_forecast(without_cover)
        if without_cover in self.forecast_cache:
            return self.forecast_cache[without_cover]
        hits=[]
        smith=self.actors.get('C_SMITH')
        charges=smith.cover_charges if smith and smith.cover_expiry>self.now else 0
        expiry=smith.cover_expiry if smith else 0
        pending=smith.casting if smith and smith.hp and smith.casting and smith.casting['skill']=='SK_S_GUARD' else None
        # Only already-disclosed main actions whose next hit is within 1.5 s.
        # Once in the window, include its disclosed remaining hits (up to 3 s),
        # not an undisclosed next action. The 3 s ceiling is a test profile.
        for tele in sorted(self.telegraphs.values(), key=lambda x:x['hits'][0]):
            remaining=[t for t in tele['hits'][tele.get('processed_hits',0):] if self.now<=t]
            if not remaining or remaining[0]>self.now+1500:
                continue
            remaining=[t for t in remaining if t<=self.now+3000]
            act=tele['action']; first=remaining[0]
            if act['aoe']:
                for t in remaining:
                    for aid,a in self.actors.items():
                        if a.hp>0: hits.append((t,aid,act,False))
                continue
            original=tele['target']; target=tele.get('resolved_target') or original
            if target and not self.actors[target].hp:
                target=original if self.actors[original].hp else None
            if pending and pending['finish']<first:
                charges=2;expiry=pending['finish']+4000;pending=None
            if not without_cover and not tele.get('resolved_target') and smith and smith.hp and charges and expiry>first and original!=smith.id:
                estimate=sum(self.forecast_incoming_at(smith,act,t,True) for t in remaining)
                shield_at_first=sum(s.amount for s in smith.shields if s.expiry>first)
                if smith.hp*10000>smith.stats['hp']*3500 and max(0,estimate-shield_at_first)<smith.hp:
                    target=smith.id; charges-=1
            if target:
                hits.extend((t,target,act,target!=original) for t in remaining)
        result=sorted(hits,key=lambda x:(x[0],ORDER.index(x[1])))
        self.forecast_cache[without_cover]=result
        return result

    def danger_for(self,aid,without_cover=False):
        danger,loss,hp=super().danger_for(aid,without_cover)
        if self.support_policy.packet_danger:
            target=self.actors[aid]
            danger=bool(self.public_forecast(without_cover)) and (loss*10000>=target.stats['hp']*2000 or (loss>0 and hp*10000<=target.stats['hp']*3500))
        return danger,loss,hp

    def guard_needed(self,a):
        if not self.support_policy.packet_guard:
            return super().guard_needed(a)
        if 'cover' in self.disabled or a.hp*10000<=a.stats['hp']*3500:
            return False
        if a.cover_expiry>self.now and a.cover_charges:
            return False
        commit=self.now+SKILLS['SK_S_GUARD']['windup_ms']
        for tele in self.telegraphs.values():
            act=tele['action']; target=tele.get('resolved_target') or tele['target']
            remaining=[t for t in tele['hits'][tele.get('processed_hits',0):] if t>=self.now]
            if act['aoe'] or not target or not self.actors[target].hp or not remaining:
                continue
            # Do not attempt to redirect a packet already committed elsewhere.
            if tele.get('processed_hits',0)>0 and target!=a.id:
                continue
            if not commit<remaining[0]<=self.now+1500:
                continue
            # R5's safety mechanics are retained. Selection is no longer
            # disabled because the protected ally crossed 35% by upgrading.
            estimate=sum(self.forecast_incoming_at(a,act,t,redirect=target!=a.id) for t in remaining)
            available_shield=sum(s.amount for s in a.shields if s.expiry>remaining[0])
            target_loss=self.danger_for(target,without_cover=True)[1]
            if target_loss>0 and max(0,estimate-available_shield)<a.hp:
                return True
        return False

    def heal_target(self,a):
        if not self.support_policy.deficit_heal:
            return super().heal_target(a)
        arr=[];nominal=self.heal_nominal(a);finish=self.now+SKILLS['SK_A_HEAL']['windup_ms']
        for aid,t in self.actors.items():
            if t.hp<=0: continue
            hp=min(t.stats['hp'],t.hp+self.reserved(aid,'heal',finish))
            deficit=t.stats['hp']-hp
            if deficit<=0:continue
            _,loss,projected=self.danger_for(aid)
            future=[x[0] for x in self.public_forecast() if x[1]==aid and x[0]>finish]
            lethal=bool(future) and projected<=0
            # Gate by useful healing, rather than target maximum HP. Threshold
            # remains a heuristic; power upgrades may still affect decisions.
            if lethal or deficit*10000>=nominal*self.support_policy.heal_min_use_bp:
                if self.support_policy.heal_rank=='lowest_ratio':
                    arr.append((0 if lethal else 1,Fraction(hp,t.stats['hp']),-min(deficit,nominal),ORDER.index(aid),aid))
                else:
                    arr.append((0 if lethal else 1,-min(deficit,nominal),Fraction(hp,t.stats['hp']),ORDER.index(aid),aid))
        return min(arr)[-1] if arr else None

    def forecast_ward_value(self,aid,caster):
        """Forecast usable shield from one candidate ward, using disclosed hits.
        No guard RNG, no hypothetical future action, no resurrection. Existing
        barriers expire before hits at the same ms; same-ms pending casts are
        NOT credited (conservative ordering). Never mutate the combat state.
        """
        target=self.actors[aid]
        hits=[h for h in self.public_forecast() if h[1]==aid]
        if target.hp<=0 or not hits:return {'absorbed':0,'granted':0,'hp_after':target.hp}
        hp=target.hp
        shields=[{'amount':s.amount,'expiry':s.expiry,'candidate':False} for s in target.shields]
        finish=self.now+SKILLS['SK_A_WARD']['windup_ms']
        pending=[(finish,ORDER.index(caster.id),'SK_A_WARD',caster,True)]
        for actor in self.actors.values():
            c=actor.casting
            if actor.hp>0 and c and c['target']==aid and c['skill'] in ('SK_A_HEAL','SK_A_WARD'):
                pending.append((c['finish'],ORDER.index(actor.id),c['skill'],actor,False))
        pending.sort(key=lambda x:(x[0],x[1],x[4]))
        absorbed=granted=0
        for time,_,action,redirect in hits:
            while pending and pending[0][0]<time and hp>0:
                when,_,skill,source,is_candidate=pending.pop(0)
                shields=[s for s in shields if s['expiry']>when and s['amount']>0]
                if skill=='SK_A_HEAL':hp=min(target.stats['hp'],hp+self.heal_nominal(source))
                else:
                    nominal=self.ward_nominal(source)*(10000+target.stats.get('barrier_received_bp',0))//10000
                    gain=self.rules.barrier_add(sum(s['amount'] for s in shields),target.stats['hp'],nominal)
                    if gain>0:
                        shields.append({'amount':gain,'expiry':when+6000,'candidate':is_candidate})
                        if is_candidate:granted+=gain
            if hp<=0:break
            shields=[s for s in shields if s['expiry']>time and s['amount']>0]
            damage=self.forecast_incoming_at(target,action,time,redirect)
            for shield in sorted(shields,key=lambda x:(x['expiry'],x['candidate'])):
                take=min(shield['amount'],damage);shield['amount']-=take;damage-=take
                if shield['candidate']:absorbed+=take
            hp=max(0,hp-damage)
        return {'absorbed':absorbed,'granted':granted,'hp_after':hp}

    def ward_target(self,a):
        if not self.support_policy.predictive_ward:
            return super().ward_target(a)
        arr=[]; finish=self.now+SKILLS['SK_A_WARD']['windup_ms']
        for aid,t in self.actors.items():
            if t.hp<=0:continue
            hits=[h for h in self.public_forecast() if h[1]==aid and finish<h[0]<finish+6000]
            if not hits:continue
            _,loss,projected=self.danger_for(aid)
            nominal=self.ward_nominal(a)*(10000+t.stats.get('barrier_received_bp',0))//10000
            shields=sum(s.amount for s in t.shields if s.expiry>finish)+self.reserved(aid,'barrier',finish)
            gain=self.rules.barrier_add(shields,t.stats['hp'],nominal)
            effective=min(loss,gain)
            if self.support_policy.timed_ward_value:
                predicted=self.forecast_ward_value(aid,a)
                gain=predicted['granted'];effective=predicted['absorbed']
            if gain<=0 or effective<=0:continue
            if projected<=0 or effective*10000>=nominal*self.support_policy.ward_min_use_bp:
                arr.append((0 if projected<=0 else 1,-effective,min(h[0] for h in hits),Fraction(t.hp,t.stats['hp']),ORDER.index(aid),aid))
        return min(arr)[-1] if arr else None

    def choose(self,a):
        if a.id=='C_APPRENTICE' and self.support_policy.urgent_choice:
            # Evaluate known lethal hits only, with unchanged cast/cooldowns.
            options=[]
            for aid,t in self.actors.items():
                if t.hp<=0:continue
                _,_,proj=self.danger_for(aid)
                if proj>0:continue
                hits=[h[0] for h in self.public_forecast() if h[1]==aid]
                if not hits:continue
                for skill,kind,windup in [('SK_A_HEAL','heal',300),('SK_A_WARD','ward',250)]:
                    if kind in self.disabled or a.ready.get(skill,0)>self.now or self.now+windup>=min(hits):continue
                    if kind=='heal':gain=min(t.stats['hp']-t.hp,self.heal_nominal(a))
                    else:gain=self.rules.barrier_add(self.shield_total(t),t.stats['hp'],self.ward_nominal(a)*(10000+t.stats.get('barrier_received_bp',0))//10000)
                    if gain>0: options.append((0 if proj+gain>0 else 1,min(hits),-gain,windup,ORDER.index(aid),skill,aid))
            if options: chosen=min(options)[-2:]
            else:chosen=super().choose(a)
        else:chosen=super().choose(a)
        if self.decision_trace and a.id in ('C_APPRENTICE','C_SMITH'):
            self.log('support_decision',actor=a.id,selected=chosen,ready=dict(a.ready),hp=a.hp,max_hp=a.stats['hp'],forecasts={aid:{'danger':self.danger_for(aid)[0],'loss':self.danger_for(aid)[1],'hp_after':self.danger_for(aid)[2]} for aid,t in self.actors.items() if t.hp>0})
        return chosen

    def run(self):
        out=super().run()
        out['provenance']='R6 support-decision comparator; no R5 combat/economy numeric changes'
        out['support_policy']=asdict(self.support_policy)
        return out
