"""New proposed memory-only contracts for permanent challenges and gear goals.
No trusted server, receipt verifier, database durability or anti-cheat proof.
"""
from dataclasses import dataclass,field,replace
from copy import deepcopy
from lab import g,e,digest,ORDER,SLOTS

@dataclass
class Progress:
    gates:set=field(default_factory=set)
    powder:int=0
    cleared:set=field(default_factory=set)
    operations:dict=field(default_factory=dict)
    records:dict=field(default_factory=dict)

def record_challenge(state,challenge_id,battle_id,result,op_id,specs,fail=False):
    if challenge_id not in specs or not battle_id or not op_id:raise ValueError('unknown/empty identity')
    spec=specs[challenge_id]
    if spec['unlock_gate'] not in state.gates:raise ValueError('locked challenge')
    if result.get('outcome') not in ('VICTORY','DEFEAT','TIMEOUT'):raise ValueError('unresolved result')
    if type(result.get('elapsed_ms')) is not int or result['elapsed_ms']<=0:raise ValueError('invalid duration')
    sig=digest([challenge_id,battle_id,result])
    if op_id in state.operations:
        if state.operations[op_id]!=sig:raise ValueError('operation collision')
        return deepcopy(state)
    # A battle result cannot be re-tagged for another challenge with a new op.
    bk='battle:'+battle_id
    if bk in state.operations:
        if state.operations[bk]!=sig:raise ValueError('battle result collision')
        return deepcopy(state)
    nxt=deepcopy(state);nxt.operations[op_id]=sig;nxt.operations[bk]=sig
    if result['outcome']=='VICTORY':
        if challenge_id not in nxt.cleared:nxt.powder+=spec['first_clear_powder'];nxt.cleared.add(challenge_id)
        previous=nxt.records.get(challenge_id)
        if previous is None or result['elapsed_ms']<previous['elapsed_ms']:nxt.records[challenge_id]=deepcopy(result)
    if fail:raise RuntimeError('simulated precommit failure')
    return nxt

def validate_preset(inventory,slots):
    if set(slots)!=set(ORDER):raise ValueError('all four actors required')
    seen=[];party={}
    for actor,ids in slots.items():
        if len(ids)!=len(set(ids)) or any(u not in inventory for u in ids):raise ValueError('missing or repeated item')
        party[actor]=[inventory[u] for u in ids];seen.extend(ids)
    if len(seen)!=len(set(seen)):raise ValueError('one item, two owners')
    g.validate_party_loadout(party)
    return True

def save_preset(presets,name,inventory,slots):
    if not name:raise ValueError('empty name')
    validate_preset(inventory,slots)
    out=deepcopy(presets);out[name]=deepcopy(slots);return out

def battle_snapshot(inventory,slots):
    validate_preset(inventory,slots)
    return {actor:tuple(deepcopy(inventory[u]) for u in ids) for actor,ids in slots.items()}

def protected_ids(inventory,active,presets):
    refs={u for ids in active.values() for u in ids}
    for slots in presets.values():refs.update(u for ids in slots.values() for u in ids)
    refs.update(u for u,it in inventory.items() if it.locked or it.invested_dust or it.enhancement or it.starter_grant)
    return refs

def bulk_dispose(inventory,ids,active,presets,confirmed=False):
    if not confirmed or len(ids)!=len(set(ids)):raise ValueError('confirmation/duplicate')
    if any(u not in inventory for u in ids):raise ValueError('missing')
    if set(ids)&protected_ids(inventory,active,presets):raise ValueError('protected')
    out=inventory.copy();powder=0
    for u in ids:powder+=g.salvage_return(out.pop(u))
    return out,powder

STARTER_POOL=tuple(sorted(t for t,v in g.GEAR.items() if v['unlock_gate'] in ('G_START','G_R01_A') and not v['parent_template_id']))
def starter_choice(tid,grant_id):
    """New optional product candidate, one explicitly chosen baseline SR.
    This does not grant the entitlement or verify a purchase.
    Fixed visible core + useful common second affix; no random result claim.
    """
    if tid not in STARTER_POOL or not grant_id:raise ValueError('not eligible')
    core={'EQ_W_01':'AF_POWER','EQ_A_01':'AF_HEAL','EQ_S_01':'AF_GUARD','EQ_F_01':'AF_CHASE'}.get(tid,'AF_HP')
    ids=[core]+[x for x in ('AF_POWER','AF_DEF','AF_HP') if x!=core][:2]
    it=g.Item('starter-choice:'+grant_id,tid,'Q2',1,0,tuple(g.Affix(x,500) for x in ids),origin_roll_floor=500,locked=True)
    g.validate_item(it);return it

def use_choice_grant(entitlements,grant_id,tid,inventory):
    if grant_id not in entitlements:raise ValueError('no entitlement')
    row=entitlements[grant_id]
    if row['used']:
        if row['selected']!=tid:raise ValueError('already selected')
        return deepcopy(entitlements),inventory.copy()
    it=starter_choice(tid,grant_id)
    if it.uid in inventory:raise ValueError('item identity collision')
    ent=deepcopy(entitlements);inv=inventory.copy();ent[grant_id].update(used=True,selected=tid);inv[it.uid]=it
    return ent,inv
