"""Test-only bridge: untouched R6-B + R2 item math + R3 acquisition + gacha C.
All integration decisions are explicit, local, and not production approvals.
No networking, live purchases, game saves, or Git operations.
"""
from __future__ import annotations
from pathlib import Path
from dataclasses import asdict, replace
from collections import defaultdict, Counter
from fractions import Fraction
import sys, json, copy, hashlib
ROOT=Path(__file__).resolve().parents[1]
sys.dont_write_bytecode=True
sys.path.insert(0,str(ROOT/'source/r6/tools'))
from bootstrap import g, ORDER, PartyInput, Profile, boss_variant, sha, canonical
from selected_final import FinalBattleR6
from precision_rules import PrecisionRules
from progression_bridge import Campaign, intro_state, e
sys.path.insert(0,str(ROOT/'source/after_draw_r4/source/research_r3/tools'))
from compare_gacha import candidates, step, Counters
CANDIDATES={x.id:x for x in candidates()}
A=CANDIDATES['A_PREVIOUS_R2']; C=CANDIDATES['C_COMMON_PLAYTEST_CANDIDATE']
COMMERCE=json.loads((ROOT/'source/after_draw_r4/source/commerce_r2/data/GEAR_METADATA_AND_NEW_AFFIX_PROPOSAL.json').read_text())
OLD_META={x['id']:x for x in COMMERCE['items']}
ALIASES={'AF_BARRIER':'AF_WARD'}
CAT_ANALOGUES={'EQ_F_BODY_01':'EQ_BODY_01','EQ_F_HAND_01':'EQ_HAND_01','EQ_F_FEET_01':'EQ_FEET_01','EQ_F_RING_01':'EQ_RING_01'}
P=PrecisionRules(g,10000)
SLOTS=('body','amulet','weapon','feet','hands','ring')
ACTOR_PRIORITY=('C_SMITH','C_APPRENTICE','C_WITCH','C_FAMILIAR')

def mapped(aid):
    value=ALIASES.get(aid,aid)
    if value not in g.AFFIXES:raise ValueError('unmapped affix: '+aid)
    return value

def catalog(mode='33', affix_mode='commerce'):
    if mode not in ('29','33') or affix_mode not in ('commerce','growth'):raise ValueError('unsupported test catalog')
    out={}
    for tid in list(OLD_META)+(list(CAT_ANALOGUES) if mode=='33' else []):
        src=OLD_META[CAT_ANALOGUES.get(tid,tid)]; core=mapped(src['core_affix'])
        pool=list(g.eligible_affixes(tid)) if affix_mode=='growth' else [mapped(a) for a in src['affix_pool']]
        if core not in pool or not set(pool)<=set(g.eligible_affixes(tid)) or len(set(pool))!=len(pool):raise ValueError('invalid affix mapping: '+tid)
        out[tid]={'id':tid,'core':core,'pool':pool,'addition_proposed':tid in CAT_ANALOGUES}
    return out

def eligible(s:Campaign,mode='33'):
    return sorted(t for t in catalog(mode) if g.GEAR[t]['unlock_gate'] in s.gates and set(g.GEAR[t]['actor_ids'])&set(s.eco.roster_xp) and (not g.GEAR[t]['parent_template_id'] or t in s.known_evolved))

def build_state(kind='protect',hours=6,seed='fixture'):
    """R3 actual ledger for material/time, with R4 authored intro/survey fixtures.
    The four-person tree fight is R6-B; no invented later-region combat.
    """
    s=intro_state(str(seed))
    r,rec=s.battle('B_R01_A',1001)
    if r['outcome']!='VICTORY':raise ValueError('miniboss preparation failed')
    s.commit_victory(rec);s.join('C_APPRENTICE');s.survey_deep_fixture();s.join('C_SMITH')
    if kind=='fresh':return s
    if kind not in ('protect','offense'):raise ValueError(kind)
    ts=['EQ_BODY_01','EQ_BODY_01','EQ_AMU_01','EQ_AMU_01'] if kind=='protect' else ['EQ_HAND_01','EQ_HAND_01','EQ_AMU_01','EQ_AMU_01']
    spent_ms=s.collect_cost(list(Counter('RC_'+x for x in ts).items()))
    owners=['C_SMITH','C_APPRENTICE','C_WITCH','C_APPRENTICE'] if kind=='protect' else ['C_WITCH','C_SMITH','C_WITCH','C_APPRENTICE']
    for i,(t,a) in enumerate(zip(ts,owners)):
        uid='craft:'+str(i);s.craft(t,uid,'craft-op:'+str(i),seed='craft:'+str(seed));s.equip(uid,a)
    if hours*3600000<s.eco.credited_ms:raise ValueError('insufficient declared preparation time')
    if hours*3600000>s.eco.last_wall_ms:s.advance(hours*3600000-s.eco.last_wall_ms)
    if s.eco.credited_ms!=hours*3600000:raise AssertionError('unexplained time')
    s.history.append({'event':'INTEGRATION_FIXTURE','seed':str(seed),'collected_ms':spent_ms,'actual_R3_natural_items':len(s.eco.gear),'no_future_gears':True})
    return s

class DrawBridge:
    """Immutable latent affixes generated once. R2 raw coordinate, 0..1000.
    Upper half is relative to current quality's legal quantile interval.
    The guaranteed core remains FIRST, not alphabetically sorted.
    """
    def __init__(self,candidate,seed,state,mode='33',affix_mode='commerce',target='EQ_W_01'):
        self.candidate=candidate;self.seed=str(seed);self.meta=catalog(mode,affix_mode)
        self.pool=eligible(state,mode)
        if target not in self.pool or len(self.pool)<2:raise ValueError('locked target or tiny pool')
        self.target=target;self.rank=e.unlocked_rank(state.gates)
        self.counters=Counters();self.index=0
        self.known={i.template_id for i in state.items.values()}|state.known_evolved
    def change_target(self,tid):
        if tid not in self.pool:raise ValueError('locked target')
        self.target=tid
    def ri(self,domain,n):return g.deterministic_int(self.seed,f'integration:{domain}:{self.index}',n)
    def draw(self,n):
        if type(n)!=int or n<0:raise ValueError('bad count')
        result=[]
        for _ in range(n):
            q,chosen,ns=step(self.candidate,self.counters,self.ri('quality',10000),self.ri('target',10000))
            other=[t for t in self.pool if t!=self.target]
            tid=self.target if chosen else other[self.ri('other',len(other))]
            m=self.meta[tid];pool=[x for x in m['pool'] if x!=m['core']];selected=[m['core']]
            for j in range(2):selected.append(pool.pop(self.ri('affix:'+str(j),len(pool))))
            # Q4 R2 legal raw floor=600. Upper half -> 800..1000; others -> 500..1000.
            floor=g.QUALITIES['Q'+str(q)]['roll_floor_q'];lower=(floor+1000+1)//2
            latent=tuple(g.Affix(a,lower+self.ri('quantile:'+str(j),1001-lower)) for j,a in enumerate(selected))
            uid='gacha:'+sha([self.seed,self.candidate.id,self.index,tid])[:24]
            item=g.Item(uid,tid,'Q'+str(q),self.rank,0,latent,origin_roll_floor=lower,locked=q==4)
            g.validate_item(item)
            result.append({'item':item,'first_discovery':tid not in self.known,'sequence':self.index,'target':self.target,'target_hit':chosen,'counters_before':asdict(self.counters),'counters_after':asdict(ns),'raw_roll_lower':lower})
            self.known.add(tid);self.counters=ns;self.index+=1
        return result

# Deterministic, information-limited selection policy for experiments, not player AI.
# It never reads latent slots, battle results, future RNG, or candidate labels.
COMMON_KEYS=('hp','power','defense','crit_chance_bp','crit_multiplier_bp','haste_bp','cdr_bp','direct_bonus_bp','guard_chance_bp','debuff_duration_resist_bp','periodic_resist_bp','heavy_reduction_bp')
EXTRA_KEYS={'C_WITCH':('dot_bonus_bp','barrier_bonus_bp'),'C_APPRENTICE':('heal_bonus_bp','barrier_bonus_bp'),'C_SMITH':('counter_bonus_bp',),'C_FAMILIAR':('chase_bonus_bp',)}
def stats(s,aid,ids=None):return P.actor_stats(aid,g.level_from_xp(s.eco.roster_xp[aid]),[s.items[u] for u in (s.equipped[aid] if ids is None else ids)])
def visible_vector(s,aid,ids=None):
    st=stats(s,aid,ids);return {k:st.get(k,0) for k in COMMON_KEYS+EXTRA_KEYS[aid]}
def recommend_equipment(s):
    changes=[]
    for _ in range(3):
        changed=False
        for aid in ACTOR_PRIORITY:
            for slot in SLOTS:
                current=s.equipped[aid];old_uid=next((u for u in current if g.GEAR[s.items[u].template_id]['slot']==slot),None)
                old=visible_vector(s,aid);taken={u for a,us in s.equipped.items() if a!=aid for u in us};best=None
                for uid,it in s.items.items():
                    gt=g.GEAR[it.template_id]
                    if uid==old_uid or uid in taken or gt['slot']!=slot or aid not in gt['actor_ids'] or gt['unlock_gate'] not in s.gates:continue
                    # Do not replace different action semantics or future gear in this slice.
                    if old_uid and it.template_id!=s.items[old_uid].template_id:continue
                    if gt['core_rules']:continue
                    ids=[u for u in current if u!=old_uid]+[uid];new=visible_vector(s,aid,ids)
                    if not all(new[k]>=old[k] for k in old) or not any(new[k]>old[k] for k in old):continue
                    gain=sum(Fraction(new[k]-old[k],max(1,old[k])) for k in old)
                    key=(gain,uid)
                    if best is None or key>best[0]:best=(key,uid,new)
                if best:
                    _,uid,new=best;s.equip(uid,aid);changes.append({'actor':aid,'slot':slot,'old':old_uid,'new':uid,'before':old,'after':new});changed=True
        if not changed:break
    return changes

UPGRADE_PRIORITY=[('C_WITCH','weapon'),('C_APPRENTICE','weapon'),('C_SMITH','body'),('C_SMITH','weapon'),('C_FAMILIAR','weapon')]+[(a,sl) for sl in ('body','amulet','feet','hands','ring') for a in ACTOR_PRIORITY]
def spend_for_enhancement(s,label):
    before=s.eco.dust;records=[];seen=set()
    for a,sl in UPGRADE_PRIORITY:
        uid=next((u for u in s.equipped[a] if g.GEAR[s.items[u].template_id]['slot']==sl),None)
        if uid is None or uid in seen:continue
        seen.add(uid)
        while s.items[uid].enhancement<g.RANKS[s.items[uid].rank]['max_enhance']:
            old=s.items[uid];n=old.enhancement+1;cost=5*n
            if s.eco.dust<cost:break
            s.enhance(uid,f'{label}:{uid}:{n}');records.append({'uid':uid,'level':n,'cost':cost})
    return {'spent':before-s.eco.dust,'steps':len(records),'operations':records,'left':s.eco.dust}

def actual_owned(s):return {u for ids in s.equipped.values() for u in ids}
def signature(it,latent=False):
    aff=it.latent_affixes if latent else g.visible_affixes(it)
    return tuple(sorted((a.affix_id,g.affix_value_bp(it,a)) for a in aff))
def noninferior_visible(a,b):
    if (a.template_id,a.quality,a.rank,a.enhancement)!=(b.template_id,b.quality,b.rank,b.enhancement):return False
    x,y=dict(signature(a)),dict(signature(b));return x.keys()==y.keys() and all(x[k]>=y[k] for k in x)

def cleanup_quote(s,draws):
    """Confirmed voluntary low-rarity disposal, never claims all future potentials equal.
    The comparison uses VISIBLE effects; hidden latent losses are logged separately.
    """
    new={r['item'].uid:r for r in draws};equipped=actual_owned(s);protected={};groups=defaultdict(list)
    for uid,it in s.items.items():
        reasons=[]
        if uid not in new:reasons.append('existing')
        if it.locked:reasons.append('locked')
        if uid in equipped or it.equipped_by:reasons.append('equipped')
        if it.referenced_by_loadout:reasons.append('loadout')
        if it.invested_dust or it.enhancement:reasons.append('invested')
        if new.get(uid,{}).get('first_discovery'):reasons.append('first_type')
        if it.quality not in ('Q0','Q1'):reasons.append('higher_quality')
        if reasons:protected[uid]=reasons
        key=(it.template_id,it.quality,it.rank,it.enhancement,tuple(k for k,v in signature(it)))
        groups[key].append(it)
    offered=[];witness={};hidden_risks=[]
    for key,items in groups.items():
        survivors=[x for x in items if x.uid in protected]
        cap=len(set(g.GEAR[key[0]]['actor_ids'])&set(s.eco.roster_xp))
        for it in sorted((x for x in items if x.uid not in protected),key=lambda v:(-sum(x for k,x in signature(v)),v.uid)):
            good=[x for x in survivors if noninferior_visible(x,it)]
            if len(good)>=cap:
                offered.append(it.uid);witness[it.uid]=[x.uid for x in good[:cap]]
                # Diagnostic only. The selector did not inspect these hidden values.
                if not all(signature(x,True)==signature(it,True) for x in good[:cap]):hidden_risks.append(it.uid)
            else:survivors.append(it)
    return {'state_hash':s.inventory_hash(),'ids':sorted(offered),'dust':sum(g.salvage_return(s.items[u]) for u in offered),'protected':protected,'witnesses':witness,'hidden_future_difference_ids':hidden_risks,'scope':'optional confirmed Q0/Q1 disposal; current-visible comparison only, not future-quality/evolution optimality'}

def commit_cleanup(s,quote,draws,op,confirmed=False,fail=False):
    if not confirmed:raise ValueError('explicit disposal confirmation required')
    sig=sha(quote)
    if op in s.applied:
        if s.applied[op]!=sig:raise ValueError('id collision')
        return
    if cleanup_quote(s,draws)!=quote:raise ValueError('stale or tampered quote')
    nxt=copy.deepcopy(s)
    for uid in quote['ids']:
        if uid in actual_owned(nxt):raise AssertionError('equipped disposal')
        del nxt.items[uid]
    nxt.eco.dust+=quote['dust'];nxt.applied[op]=sig
    if fail:raise RuntimeError('injected transaction failure')
    s.__dict__.update(nxt.__dict__)

def accept_draws(s,draws,op):
    payload=sha([asdict(r['item']) for r in draws])
    if op in s.applied:
        if s.applied[op]!=payload:raise ValueError('receipt collision')
        return
    if len({r['item'].uid for r in draws})!=len(draws) or any(r['item'].uid in s.items for r in draws):raise ValueError('duplicate inventory')
    nxt=copy.deepcopy(s)
    for r in draws:nxt.insert(r['item'])
    nxt.applied[op]=payload;s.__dict__.update(nxt.__dict__)

def battle(s,seed,boss=None,record=False):
    return FinalBattleR6(s.loadout(),boss or boss_variant('redistribute_pause'),seed,record=record).run()

def state_record(s):
    return {'hash':s.inventory_hash(),'gates':sorted(s.gates),'level':{a:g.level_from_xp(v) for a,v in s.eco.roster_xp.items()},'xp':dict(s.eco.roster_xp),'dust':s.eco.dust,'spent_dust':s.spent_dust,'materials':dict(s.eco.materials),'credited_ms':s.eco.credited_ms,'natural_items':len(s.eco.gear),'loadout':[asdict(p) for p in s.loadout()],'stats':{a:stats(s,a) for a in s.eco.roster_xp},'item_count':len(s.items)}
