"""G1 balance reference. Python standard library only; not the shipping game.
All content/values are design hypotheses; xorshift32 and integer arithmetic allow ports.
"""
from __future__ import annotations
from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any

ROOT=Path(__file__).resolve().parents[1]
DATA=json.loads((ROOT/'data/content.json').read_text(encoding='utf-8'))
SLOTS=DATA['slots']

class Rng:
    def __init__(self, seed: int): self.state=(int(seed)&0xffffffff) or 0x6D2B79F5
    def next(self) -> int:
        x=self.state; x^=(x<<13)&0xffffffff; x^=x>>17; x^=(x<<5)&0xffffffff
        self.state=x&0xffffffff
        return self.state
    def bp(self, threshold: int) -> bool: return self.next()%10000 < threshold

def make_stats(loadout: tuple[str,...]|list[str]) -> dict[str,int]:
    if len(loadout)!=len(SLOTS): raise ValueError('exactly six item ids required')
    s=DATA['base_stats'].copy()
    for slot,item_id in zip(SLOTS,loadout):
        item=DATA['items'].get(item_id)
        if item is None or item['slot']!=slot: raise ValueError(f'invalid item for {slot}: {item_id}')
        for k,v in item['stats'].items(): s[k]=s.get(k,0)+v
    s['crit_bp']=min(s['crit_bp'],7500)
    s['block_bp']=min(s['block_bp'],7500)
    s['attack_interval_ms']=max(400,10000000//(10000+s['haste_bp']))
    return s

def fight(loadout: tuple[str,...]|list[str], boss_id: str, seed: int=1, *, trace:bool=False, scale_bp:int=10000) -> dict[str,Any]:
    s=make_stats(loadout); b=DATA['bosses'][boss_id]; rng=Rng(seed)
    hp=s['hp']; bhp=b['hp']*scale_bp//10000; time=0
    next_p=s['attack_interval_ms']; next_dot=1000; boss_cycle=0; boss_hit=0
    next_b=b['hit_offsets_ms'][0]; poison_stacks=0; poison_until=-1
    totals={'normal':0,'poison':0,'counter':0,'incoming':0,'attacks':0,'crits':0,'blocks':0,'boss_hits':0,'poison_ticks':0}
    logs=[]
    def log(kind:str, damage:int, **extra:Any)->None:
        if trace: logs.append({'t':time,'kind':kind,'damage':damage,'player_hp':max(0,hp),'boss_hp':max(0,bhp),**extra})
    limit=DATA['combat']['time_limit_ms']
    while hp>0 and bhp>0:
        time=min(next_dot,next_p,next_b)
        if time>limit: time=limit; break
        # Equal-time ordering: poison tick -> player hit -> boss hit. Expiry excludes boundary.
        if time==next_dot:
            next_dot+=1000
            if poison_stacks and time<poison_until:
                dmg=poison_stacks*s['poison_damage']; actual=min(dmg,bhp)
                bhp-=dmg; totals['poison']+=actual; totals['poison_ticks']+=1
                log('poison',actual,stacks=poison_stacks)
                if bhp<=0: break
            elif time>=poison_until: poison_stacks=0
        if time==next_p:
            next_p+=s['attack_interval_ms']; totals['attacks']+=1
            crit=rng.bp(s['crit_bp']); totals['crits']+=int(crit)
            raw=s['attack']* (s['crit_multiplier_bp'] if crit else 10000)//10000
            dmg=max(1,raw*100//(100+b['armor'])); actual=min(bhp,dmg)
            bhp-=dmg; totals['normal']+=actual
            if s['poison_damage']>0:
                if time>=poison_until: poison_stacks=0
                poison_stacks=min(DATA['combat']['poison_stack_cap'],poison_stacks+1)
                poison_until=time+s['poison_duration_ms']
            log('normal',actual,critical=crit)
            if bhp<=0: break
        if time==next_b:
            totals['boss_hits']+=1
            rage_elapsed=max(0,time-b['enrage_start_ms'])
            mult=10000+rage_elapsed*b['enrage_bp_per_second']//1000
            raw=b['hit_damage']*scale_bp//10000 * mult//10000
            damage=max(1,raw*100//(100+s['armor']))
            blocked=rng.bp(s['block_bp']); totals['blocks']+=int(blocked)
            if blocked: damage=max(1,damage*(10000-DATA['combat']['block_reduction_bp'])//10000)
            actual=min(damage,hp); hp-=damage; totals['incoming']+=actual
            log('boss_hit',actual,blocked=blocked)
            if hp<=0: break # No post-death counter.
            if blocked and s['counter_bp']>0:
                raw_counter=s['armor']*s['counter_bp']//10000
                dmg=max(1,raw_counter*100//(100+b['armor'])); actual=min(dmg,bhp)
                bhp-=dmg; totals['counter']+=actual
                log('counter',actual)
                if bhp<=0: break
            boss_hit+=1
            if boss_hit>=len(b['hit_offsets_ms']): boss_cycle+=1; boss_hit=0
            next_b=boss_cycle*b['cycle_ms']+b['hit_offsets_ms'][boss_hit]
    return {'win':bhp<=0 and hp>0,'time_ms':time,'hp_remaining':max(0,hp),'boss_hp_remaining':max(0,bhp),'stats':s,'totals':totals,**({'trace':logs} if trace else {})}

if __name__=='__main__':
    for name,loadout in DATA['presets'].items():
        for boss in DATA['bosses']:
            r=fight(loadout,boss,1)
            print(name,boss,r['win'],r['time_ms'],r['hp_remaining'],r['totals'])
