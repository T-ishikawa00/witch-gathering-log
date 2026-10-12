"""G2-C R2: 数式・装備操作の独立参照モデル（完成戦闘エンジンではない）。
外部ライブラリ不要。入力JSONはこのパッケージ内の設計用スナップショットを読む。
本番ファイル・Macのプロジェクト・ネットワークには書き込まない。
"""
from __future__ import annotations
from dataclasses import dataclass, field, replace
from fractions import Fraction
from pathlib import Path
from typing import Any
import copy
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
DATA = json.loads((ROOT/'data/growth_gear_skills_R2.json').read_text())
WORLD = json.loads((ROOT/'reference/world_catalog_R1_UNCHANGED.json').read_text())
ACTORS = {a['actor_id']: a for a in DATA['actors']}
GEAR = {g['template_id']: g for g in DATA['gear_templates']}
AFFIXES = {a['affix_id']: a for a in DATA['affixes']}
QUALITIES = {q['id']: q for q in DATA['rarities']}
RANKS = {r['rank']: r for r in DATA['attunement_ranks']}
GATES = {g['id']: g['rank'] for g in WORLD['gates']}
RECIPES = {r['output_gear_id']: r for r in DATA['recipe_cost_overlay']+DATA['new_cat_recipes']}


def ceil_fraction(x: Fraction) -> int:
    return -(-x.numerator // x.denominator)


def xp_to_next(level: int) -> int:
    if not 1 <= level < 60:
        raise ValueError('次レベルは1..59のみ')
    return 100 + 30*(level-1) + 4*(level-1)**2


def xp_threshold(level: int) -> int:
    if not 1 <= level <= 60:
        raise ValueError('level must be 1..60')
    return sum(xp_to_next(x) for x in range(1,level))


def level_from_xp(xp: int) -> int:
    if xp < 0:
        raise ValueError('negative xp')
    return max(l for l in range(1,61) if xp >= xp_threshold(l))


def allocate_sortie_xp(roster_xp: dict[str,int], xp: int) -> dict[str,int]:
    if xp < 0 or any(k not in ACTORS for k in roster_xp):
        raise ValueError('invalid roster or xp')
    cap=xp_threshold(60)
    return {a:min(cap,v+xp) for a,v in roster_xp.items()}


def join_actor(roster_xp: dict[str,int], actor_id: str) -> dict[str,int]:
    if actor_id not in ACTORS:
        raise ValueError('unknown actor')
    out=dict(roster_xp)
    if actor_id not in out:
        out[actor_id]=max(out.values(),default=0)
    return out


def gate_allows(current: str, required: str) -> bool:
    if current not in GATES or required not in GATES:
        raise ValueError('unknown gate')
    return GATES[current] >= GATES[required]


def deterministic_int(seed: str, label: str, upper: int) -> int:
    if upper<=0:
        raise ValueError('upper must be positive')
    # 拒否法で範囲へ変換。保存seedとlabelを変えない限り同じ出力。
    limit=(1<<256)-((1<<256)%upper)
    for c in range(1000):
        v=int.from_bytes(hashlib.sha256(f'{seed}|{label}|{c}'.encode()).digest(),'big')
        if v < limit:
            return v%upper
    raise RuntimeError('RNG rejection bound')


def eligible_affixes(template_id: str) -> list[str]:
    g=GEAR[template_id]
    members=set(g['actor_ids'])
    pool=[]
    for aid,a in AFFIXES.items():
        capability=a['actor_capability']
        if capability!='all' and not (members & set(capability)):
            continue
        # 基礎杖は護りへの進化も行うため、創出時点のlatent枠へ呪毒専用値を入れない。
        if template_id in {'EQ_W_01','EQ_W_G1','EQ_W_G2'} and aid=='AF_DOT':
            continue
        pool.append(aid)
    return sorted(pool)


@dataclass(frozen=True)
class Affix:
    affix_id: str
    roll_q: int


@dataclass(frozen=True)
class Item:
    uid: str
    template_id: str
    quality: str='Q0'
    rank: int=1
    enhancement: int=0
    latent_affixes: tuple[Affix,...]=()
    origin_roll_floor: int=0
    invested_dust: int=0
    locked: bool=False
    equipped_by: str|None=None
    referenced_by_loadout: bool=False
    starter_grant: bool=False
    revision: int=1


def validate_item(item: Item) -> None:
    if not item.uid or item.template_id not in GEAR or item.quality not in QUALITIES:
        raise ValueError('unknown or empty item identity')
    if item.rank not in RANKS or not 0<=item.enhancement<=RANKS[item.rank]['max_enhance']:
        raise ValueError('invalid rank/enhancement')
    if len(item.latent_affixes)!=3:
        raise ValueError('3 immutable latent affix entries required')
    if len({a.affix_id for a in item.latent_affixes})!=3:
        raise ValueError('duplicate affix group')
    for a in item.latent_affixes:
        if a.affix_id not in AFFIXES or a.affix_id not in eligible_affixes(item.template_id) or not 0<=a.roll_q<=1000:
            raise ValueError('invalid affix')
    if not 0<=item.origin_roll_floor<=1000 or item.invested_dust<0:
        raise ValueError('invalid floor/investment')
    if item.equipped_by and item.equipped_by not in GEAR[item.template_id]['actor_ids']:
        raise ValueError('ineligible owner')


def create_item(uid: str, template_id: str, quality: str='Q0', seed: str='fixture',
                crafted: bool=False, starter: bool=False) -> Item:
    if template_id not in GEAR or quality not in QUALITIES:
        raise ValueError('unknown template/quality')
    pool=eligible_affixes(template_id)
    picked=[]
    for i in range(3):
        at=deterministic_int(seed,f'{uid}:affix:{i}',len(pool))
        aid=pool.pop(at)
        picked.append(Affix(aid,deterministic_int(seed,f'{uid}:roll:{i}',1001)))
    item=Item(uid,template_id,quality=quality,latent_affixes=tuple(picked),
              origin_roll_floor=250 if crafted else 0,starter_grant=starter)
    validate_item(item)
    return item


def visible_affixes(item: Item) -> tuple[Affix,...]:
    validate_item(item)
    return item.latent_affixes[:QUALITIES[item.quality]['affix_count']]


def affix_value_bp(item: Item, affix: Affix) -> int:
    a=AFFIXES[affix.affix_id]
    q=max(affix.roll_q,item.origin_roll_floor,QUALITIES[item.quality]['roll_floor_q'])
    return a['min_bp']+(a['max_bp']-a['min_bp'])*q//1000


def item_primary(item: Item) -> dict[str,int]:
    validate_item(item)
    r=RANKS[item.rank]['multiplier_bp']
    enh=10000+300*item.enhancement
    return {stat:value*r*enh//100_000_000 for stat,value in GEAR[item.template_id]['item_stat_budget'].items()}


def actor_stats(actor_id: str, level: int, items: list[Item], awakening: int=0) -> dict[str,int]:
    if actor_id not in ACTORS or not 1<=level<=60 or not 0<=awakening<=3:
        raise ValueError('actor/level/awakening invalid')
    a=ACTORS[actor_id]
    slots=set();uids=set()
    flat={s:a['base'][s]+a['per_level'][s]*(level-1) for s in a['base']}
    mods:dict[str,int]={}
    for it in items:
        validate_item(it)
        g=GEAR[it.template_id]
        if actor_id not in g['actor_ids'] or g['slot'] in slots or it.uid in uids:
            raise ValueError('ineligible/duplicate equipment')
        if it.equipped_by and it.equipped_by != actor_id:
            raise ValueError('equipped by other member')
        slots.add(g['slot']);uids.add(it.uid)
        for s,v in item_primary(it).items():flat[s]+=v
        for s,v in g['core_modifiers'].items():mods[s]=mods.get(s,0)+v
        for af in visible_affixes(it):
            s=AFFIXES[af.affix_id]['stat'];mods[s]=mods.get(s,0)+affix_value_bp(it,af)
    if awakening>=1:
        if actor_id=='C_SMITH':mods['guard_chance_bp']=mods.get('guard_chance_bp',0)+500
        if actor_id=='C_WITCH':mods['barrier_bonus_bp']=mods.get('barrier_bonus_bp',0)+1000
    out=dict(mods)
    for s in ['hp','power','defense']:
        b=min(DATA['caps'][s+'_pct'],max(0,mods.get(s+'_pct',0)))
        out[s]=flat[s]*(10000+b)//10000
    out['crit_chance_bp']=min(DATA['caps']['crit_chance_bp'],a['base_crit_bp']+mods.get('crit_chance_bp',0))
    out['crit_multiplier_bp']=min(DATA['caps']['crit_multiplier_bp'],15000+mods.get('crit_damage_extra_bp',0))
    out['guard_chance_bp']=min(DATA['caps']['guard_chance_bp'],a['base_guard_bp']+mods.get('guard_chance_bp',0))
    for key,cap in DATA['caps'].items():
        if key in out and key not in {'hp','power','defense'}:out[key]=max(0,min(cap,out[key]))
    return out


def validate_party_loadout(loadout:dict[str,list[Item]]) -> None:
    uids=[]
    for aid,items in loadout.items():
        actor_stats(aid,1,items)
        uids.extend(i.uid for i in items)
    if len(set(uids))!=len(uids):raise ValueError('same item cannot be equipped by two actors')


def scaled_basic_interval(base_ms: int, haste_bp: int) -> int:
    if base_ms<=0:raise ValueError('invalid time')
    h=max(0,min(5000,haste_bp))
    return max(500,ceil_fraction(Fraction(base_ms*10000,10000+h)))


def scaled_skill_cd(base_ms:int,cdr_bp:int) -> int:
    if base_ms<=0:raise ValueError('invalid time')
    c=max(0,min(2500,cdr_bp))
    return max(1000,ceil_fraction(Fraction(base_ms*(10000-c),10000)))


def defense_fraction(defense:int, attacker_level:int) -> Fraction:
    if defense<0 or not 1<=attacker_level<=60:raise ValueError('invalid defense inputs')
    k=100+8*(attacker_level-1)
    return min(Fraction(7,10),Fraction(defense,defense+k))


def direct_incoming(raw_damage:int,defense:int,attacker_level:int,guarded:bool=False,
                    special_reduction_bp:int=0) -> int:
    if raw_damage<0:raise ValueError('negative damage')
    value=Fraction(raw_damage)*(1-defense_fraction(defense,attacker_level))
    if guarded:value*=Fraction(65,100)
    value*=Fraction(10000-max(0,min(3000,special_reduction_bp)),10000)
    return value.numerator//value.denominator


def shield_and_hp(incoming:int,shield:int,hp:int,periodic:bool=False) -> dict[str,int]:
    if min(incoming,shield,hp)<0:raise ValueError('negative resource')
    absorbed=0 if periodic else min(incoming,shield)
    hp_damage=min(hp,incoming-absorbed)
    return {'absorbed':absorbed,'hp_damage':hp_damage,'shield_after':shield-absorbed,'hp_after':hp-hp_damage}


def apply_heal(hp:int,max_hp:int,nominal:int) -> dict[str,int]:
    if not 0<=hp<=max_hp or max_hp<=0 or nominal<0:raise ValueError('invalid healing')
    effective=0 if hp==0 else min(nominal,max_hp-hp)
    return {'effective':effective,'waste':nominal-effective,'hp_after':hp+effective}


def barrier_add(current:int,max_hp:int,nominal:int) -> int:
    if min(current,nominal)<0 or max_hp<=0:raise ValueError('invalid barrier')
    return min(nominal,max(0,max_hp*3500//10000-current))


def poison_tick(power:int,stacks:int,mastery_rank:int=1,bonus_bp:int=0,resist_bp:int=0) -> int:
    if power<0 or not 0<=stacks<=8 or not 1<=mastery_rank<=5:raise ValueError('invalid poison')
    v=Fraction(power*600*stacks,10000)*Fraction(10000+800*(mastery_rank-1),10000)
    v*=Fraction(10000+max(0,min(10000,bonus_bp)),10000)
    v*=Fraction(10000-max(0,min(5000,resist_bp)),10000)
    return v.numerator//v.denominator


def can_react(origin:str,depth:int,effective:int,alive:bool,now_ms:int,next_ready_ms:int,
              root_id:str,seen_roots:set[str]) -> bool:
    return origin in {'root_active','root_enemy'} and depth==0 and effective>0 and alive and now_ms>=next_ready_ms and root_id not in seen_roots


def enhance_item(item:Item,gate:str) -> tuple[Item,int]:
    validate_item(item)
    n=item.enhancement+1
    if n>RANKS[item.rank]['max_enhance'] or not gate_allows(gate,RANKS[item.rank]['gate']):
        raise ValueError('enhancement not available')
    cost=5*n
    out=replace(item,enhancement=n,invested_dust=item.invested_dust+cost,revision=item.revision+1)
    validate_item(out)
    return out,cost


def promote_quality(item:Item,gate:str) -> tuple[Item,int]:
    validate_item(item)
    rule=next((x for x in DATA['equipment_rules']['quality_upgrades'] if x['from']==item.quality),None)
    if rule is None or not gate_allows(gate,rule['gate']):raise ValueError('quality upgrade unavailable')
    # 抽選値とaffix種類は変更しない。品質がeffective floorと可視枠数を決める。
    out=replace(item,quality=rule['to'],invested_dust=item.invested_dust+rule['dust'],revision=item.revision+1)
    validate_item(out)
    return out,rule['dust']


def tune_item(item:Item,gate:str) -> tuple[Item,dict[str,int]]:
    validate_item(item)
    rule=next((x for x in DATA['attunement_costs'] if x['from_rank']==item.rank),None)
    if rule is None or not gate_allows(gate,rule['gate']):raise ValueError('attunement unavailable')
    out=replace(item,rank=rule['to_rank'],invested_dust=item.invested_dust+rule['dust'],revision=item.revision+1)
    validate_item(out)
    return out, {'RES_REFINING_DUST':rule['dust'],**{x['material_id']:x['quantity'] for x in rule['materials']}}


def evolve_preview(item:Item,target_template:str,gate:str,joined_actor_ids:frozenset[str]=frozenset()) -> tuple[Item,dict[str,int]]:
    validate_item(item)
    if target_template not in GEAR:raise ValueError('unknown template')
    dest=GEAR[target_template]
    if dest['parent_template_id']!=item.template_id:raise ValueError('not a direct evolution edge')
    if not gate_allows(gate,dest['unlock_gate']):raise ValueError('future recipe')
    pool=set(eligible_affixes(target_template))
    # latent枠も対象。将来品質を上げて無効な副効果が出ることを防ぐ。
    if any(x.affix_id not in pool for x in item.latent_affixes):raise ValueError('incompatible affix; no automatic reroll')
    r=RECIPES[target_template]
    if r['station']=='forge' and 'C_SMITH' not in joined_actor_ids:
        raise ValueError('blacksmith has not joined')
    out=replace(item,template_id=target_template,revision=item.revision+1)
    validate_item(out)
    return out,{x['material_id']:x['quantity'] for x in r['ingredients']}


def salvage_return(item:Item) -> int:
    validate_item(item)
    if item.locked or item.equipped_by or item.referenced_by_loadout:
        raise ValueError('protected item')
    base=0 if item.starter_grant else QUALITIES[item.quality]['salvage_base']
    return base+item.invested_dust*8000//10000


@dataclass
class Ledger:
    """原子的に検証してから差し替えるメモリ上の操作モデル。実DB耐障害性の試験ではない。"""
    items:dict[str,Item]
    resources:dict[str,int]
    receipts:dict[str,tuple[str,Any]]=field(default_factory=dict)
    joined_actor_ids:frozenset[str]=field(default_factory=frozenset)

    def evolve(self,op_id:str,uid:str,target:str,gate:str,expected_revision:int) -> Item:
        signature=json.dumps([uid,target,gate,expected_revision])
        if op_id in self.receipts:
            if self.receipts[op_id][0]!=signature:raise ValueError('op_id reused for another request')
            return self.receipts[op_id][1]
        old=self.items[uid]
        if old.revision!=expected_revision:raise ValueError('revision conflict')
        new,cost=evolve_preview(old,target,gate,self.joined_actor_ids)
        if any(self.resources.get(k,0)<v for k,v in cost.items()):raise ValueError('insufficient materials')
        nextres=dict(self.resources)
        for k,v in cost.items():nextres[k]-=v
        self.items={**self.items,uid:new};self.resources=nextres
        self.receipts[op_id]=(signature,new)
        return new

    def salvage(self,op_id:str,uid:str) -> int:
        signature='salvage:'+uid
        if op_id in self.receipts:
            if self.receipts[op_id][0]!=signature:raise ValueError('op_id mismatch')
            return self.receipts[op_id][1]
        item=self.items[uid]
        amount=salvage_return(item)
        nextitems=dict(self.items);del nextitems[uid]
        self.items=nextitems
        self.resources={**self.resources,'RES_REFINING_DUST':self.resources.get('RES_REFINING_DUST',0)+amount}
        self.receipts[op_id]=(signature,amount)
        return amount


def validate_progression(actor_id:str,level:int,awakening:int,gate:str,items:list[Item]) -> None:
    actor_stats(actor_id,level,items,awakening)
    if not gate_allows(gate,ACTORS[actor_id]['join_gate']):
        raise ValueError('actor not available by gate')
    for it in items:
        if not gate_allows(gate,GEAR[it.template_id]['unlock_gate']):
            raise ValueError('future equipment template')
        if not gate_allows(gate,RANKS[it.rank]['gate']):
            raise ValueError('future attunement rank')
    for aw in DATA['awakenings']:
        if aw['actor_id']==actor_id and aw['stage']<=awakening:
            if level<aw['min_level'] or not gate_allows(gate,aw['unlock_gate']):
                raise ValueError('awakening requirements not met')


@dataclass
class PoisonSchedule:
    """単一付与者の毒タイマー。終端tickを含め、刷新でtick予定を遅らせない。"""
    stacks:int=0
    expires_ms:int=0
    next_tick_ms:int|None=None
    clock_ms:int=0

    def advance(self,to_ms:int) -> list[tuple[int,int]]:
        if to_ms<self.clock_ms:raise ValueError('clock reversal')
        result=[]
        while self.next_tick_ms is not None and self.next_tick_ms<=to_ms and self.next_tick_ms<=self.expires_ms:
            result.append((self.next_tick_ms,self.stacks));self.next_tick_ms+=1000
        if self.stacks and to_ms>=self.expires_ms:
            self.stacks=0;self.next_tick_ms=None
        self.clock_ms=to_ms
        return result

    def add_after_advance(self,now_ms:int,add:int=2,cap:int=5) -> None:
        if now_ms!=self.clock_ms or not 1<=cap<=8 or add<=0:
            raise ValueError('advance through current timestamp before adding poison')
        if self.stacks==0:self.next_tick_ms=now_ms+1000
        self.stacks=min(cap,self.stacks+add)
        self.expires_ms=now_ms+9000
