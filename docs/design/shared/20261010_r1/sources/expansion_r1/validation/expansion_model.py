"""Limited specification model, not a StoreKit/server/game implementation.

Uses fixed mock products/odds/entitlements to test interface invariants. No payment,
network, image generation, R6 combat or production saves. RNG is deterministic test
input and MUST NOT be used for real-money random draws.
"""
from __future__ import annotations
from copy import deepcopy
from dataclasses import dataclass, field, asdict
from fractions import Fraction
from hashlib import sha256
import json

BP=10000
TOP='Q4'
LOW='Q2'
STATES=('idle','anticipate','execute','recover','hit','resolve')

class Rejected(ValueError):
    pass


def fingerprint(value):
    return sha256(json.dumps(value,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()


@dataclass(frozen=True)
class Template:
    id: str
    gate: int
    actors: tuple[str,...]
    first_craft_required: bool=False


CATALOG=(Template('MOCK_WAND_BASE',1,('witch',)),Template('MOCK_BOOK_BASE',1,('apprentice',)),
         Template('MOCK_HAMMER_BASE',1,('smith',)),Template('MOCK_CAT_FOCUS',1,('cat',)),
         Template('MOCK_AMULET',1,('witch','apprentice','smith','cat')),
         Template('MOCK_EVOLVED_WAND',2,('witch',),True),Template('MOCK_END_WAND',5,('witch',),True))


@dataclass
class Account:
    revision: int=0
    gate: int=1
    roster: tuple[str,...]=('witch','apprentice','smith','cat')
    crafted: set[str]=field(default_factory=set)
    free_tickets: int=0
    paid_tickets: int=0
    natural_pity: int=0
    high_miss: int=0
    target_miss: int=0
    draw_seq: int=0
    receipts: dict=field(default_factory=dict)
    results: dict=field(default_factory=dict)
    inventory: dict=field(default_factory=dict)
    grants: dict=field(default_factory=dict)
    outfit: str='BASE'
    furniture: dict=field(default_factory=dict)
    materials: int=100
    pending_mutations: bool=False

    def eligible(self):
        return tuple(t.id for t in CATALOG if t.gate<=self.gate and set(t.actors)&set(self.roster)
                     and (not t.first_craft_required or t.id in self.crafted))

    def digest(self):
        d=asdict(self);d['crafted']=sorted(self.crafted)
        return fingerprint(d)

    def grant_purchase(self,tx,sku,*,tickets=0,content=(),verified=True):
        """verified is a mock precondition, NOT cryptographic verification."""
        if not verified:raise Rejected('unverified mock receipt')
        if tickets<0:raise Rejected('negative grant')
        sig=fingerprint([sku,tickets,sorted(content)])
        if tx in self.receipts:
            if self.receipts[tx]!=sig:raise Rejected('transaction payload conflict')
            return
        nxt=deepcopy(self);nxt.receipts[tx]=sig;nxt.paid_tickets+=tickets
        nxt.grants[tx]={'content':tuple(content),'revoked':False}
        nxt.revision+=1;self.__dict__.update(nxt.__dict__)

    def active_content(self):
        # Overlapping standalone/bundle grants unlock once, not once per receipt.
        return set().union(*(set(v['content']) for v in self.grants.values() if not v['revoked']))

    def revoke_cosmetic(self,tx,*,verified=True):
        """Cosmetic mock only. Spent-ticket/item refunds are deliberately NOT solved."""
        if not verified:raise Rejected('unverified mock reversal')
        if tx not in self.grants:raise Rejected('unknown transaction')
        if self.grants[tx]['revoked']:return
        self.grants[tx]['revoked']=True
        if self.outfit not in self.active_content():self.outfit='BASE'
        self.furniture={k:v for k,v in self.furniture.items() if v in self.active_content()}
        self.revision+=1

    def equip_outfit(self,item):
        if item!='BASE' and item not in self.active_content():raise Rejected('not owned')
        self.outfit=item

    def quote(self,target,version='MOCK_POOL_V1'):
        if self.pending_mutations:raise Rejected('sync inventory changes before quote')
        eligible=self.eligible()
        if target not in eligible:raise Rejected('target unavailable')
        return {'account_revision':self.revision,'target':target,'pool_version':version,'eligible':eligible}

    def draw(self,request_id,quote,*,n=1,seed='fixture',online=True,
             high_pity_limit=5,target_pity_limit=9,base_high_bp=300,fail_before_commit=False):
        """Illustrative tiny pity limits for tests, not proposed commercial values.
        Result replay precedes stale-quote checks; same operation cannot reroll.
        The entire batch is committed together in memory.
        """
        sig=fingerprint([quote,n,high_pity_limit,target_pity_limit,base_high_bp])
        if request_id in self.results:
            stored=self.results[request_id]
            if stored['signature']!=sig:raise Rejected('request payload conflict')
            return deepcopy(stored['outcome'])
        if not online:raise Rejected('paid-compatible draws require online')
        if self.pending_mutations:raise Rejected('pending inventory journal')
        if quote['account_revision']!=self.revision:raise Rejected('stale quote')
        if quote['pool_version']!='MOCK_POOL_V1':raise Rejected('unknown pool version')
        if tuple(quote['eligible'])!=self.eligible():raise Rejected('pool changed')
        if quote['target'] not in self.eligible():raise Rejected('locked target')
        if n<=0 or n>10:raise Rejected('unsupported batch')
        if min(high_pity_limit,target_pity_limit)<=0 or not 0<=base_high_bp<=BP:raise Rejected('bad probability config')
        if self.free_tickets+self.paid_tickets<n:raise Rejected('insufficient balance')
        s=deepcopy(self);out=[]
        before=(s.high_miss,s.target_miss);natural=s.natural_pity
        free_used=min(n,s.free_tickets);paid_used=n-free_used
        s.free_tickets-=free_used;s.paid_tickets-=paid_used
        for _ in range(n):
            seq=s.draw_seq;s.draw_seq+=1
            roll=int(fingerprint([seed,'quality',seq]),16)%BP
            target_forced=s.target_miss>=target_pity_limit-1
            ishigh=target_forced or s.high_miss>=high_pity_limit-1 or roll<base_high_bp
            chosen=quote['target'] if target_forced else s.eligible()[int(fingerprint([seed,'type',seq]),16)%len(s.eligible())]
            quality=TOP if ishigh else LOW
            is_target=ishigh and chosen==quote['target']
            s.high_miss=0 if ishigh else s.high_miss+1
            s.target_miss=0 if is_target else s.target_miss+1
            uid=f'MOCK_DRAW_ITEM_{seq}'
            if uid in s.inventory:raise Rejected('uid collision')
            item={'id':uid,'template':chosen,'quality':quality,'rank':s.gate,'enhancement':0,
                  'origin':'MOCK_GACHA','actual_investment':0,'usable_profile_guaranteed':True}
            s.inventory[uid]=item;out.append(deepcopy(item))
        outcome={'items':out,'free_used':free_used,'paid_used':paid_used,
                 'pity_before':before,'pity_after':(s.high_miss,s.target_miss),'pool_version':quote['pool_version']}
        s.results[request_id]={'signature':sig,'outcome':deepcopy(outcome)};s.revision+=1
        assert natural==s.natural_pity
        if fail_before_commit:raise RuntimeError('injected failure before in-memory commit')
        self.__dict__.update(s.__dict__)
        return outcome


def effective_living_bonus(earned_bp,owned_effects,*,cap_bp=300):
    """One tested stat only; cap=3% is a sensitivity parameter, not approval."""
    if earned_bp<0 or cap_bp<0 or any(v<0 for v in owned_effects.values()):raise Rejected('negative bonus')
    return min(cap_bp,earned_bp+sum(owned_effects.values()))


def mock_stat(base,flat,existing_percent_bp,earned_bp,owned_effects,*,cap_bp=300):
    # Same percentage group: do not secretly multiply furniture and outfit bonuses.
    living=effective_living_bonus(earned_bp,owned_effects,cap_bp=cap_bp)
    return Fraction(base+flat)*(BP+existing_percent_bp+living)/BP


def appearance_stat(account,bonus_catalog):
    effects={k:bonus_catalog[k] for k in account.active_content() if k in bonus_catalog}
    return mock_stat(100,20,1500,0,effects)


def outfit_deliverable(manifest):
    """Checks references/coverage labels only. Not visual, animation or device QA."""
    if not {'home','portrait','battle'}<=set(manifest.get('contexts',())):return False
    if set(manifest.get('battle_states',()))!=set(STATES):return False
    return bool(manifest.get('actor_id') and manifest.get('revision') and manifest.get('editable_source') and manifest.get('grip_contract'))


def safe_mount(socket,asset):
    """Abstract home-socket contract, not real scene geometry."""
    if socket['category']!=asset['category']:return False
    if not set(socket['needed_interactions'])<=set(asset['supported_interactions']):return False
    if asset['max_width']>socket['max_width']:return False
    return asset['has_back_underpaint'] and asset['seat_anchor_valid']


def high_pity_distribution(p:Fraction,n:int):
    if not 0<p<=1 or n<1:raise ValueError('parameters')
    return [p*(1-p)**(k-1) for k in range(1,n)]+[(1-p)**(n-1)]


def high_pity_mean(p:Fraction,n:int):
    d=high_pity_distribution(p,n)
    return sum(Fraction(i+1)*v for i,v in enumerate(d))
