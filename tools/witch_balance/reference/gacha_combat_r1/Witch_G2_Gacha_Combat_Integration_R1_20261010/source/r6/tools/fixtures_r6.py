"""Paired inputs: same resource spend, same item identity/affixes in each pair."""
from bootstrap import *
from dataclasses import asdict
import copy

def make_state(kind='protect',hours=6,craft_seed=None):
    state=prepared_at(kind,hours)
    if craft_seed is not None:
        for uid,item in list(state.items.items()):
            if uid.startswith('craft:'):
                state.items[uid]=g.create_item(uid,item.template_id,'Q2',seed=craft_seed,crafted=True)
    return state

def upgrade(state,mode='paid90'):
    nxt=copy.deepcopy(state)
    modes={'paid90':[('intro:relic',3),('grant:C_APPRENTICE',3),('craft:0',3)],
           'witch5':[('intro:relic',1)],'healer5':[('grant:C_APPRENTICE',1)],'armor5':[('craft:0',1)]}
    if mode not in modes:raise ValueError(mode)
    before=nxt.eco.dust
    for uid,steps in modes[mode]:
        for i in range(steps):nxt.enhance(uid,f'r6:{mode}:{uid}:{i}')
    expected=90 if mode=='paid90' else 5
    if before-nxt.eco.dust!=expected:raise AssertionError('cost changed')
    for uid,it in state.items.items():
        assert it.uid==nxt.items[uid].uid and it.latent_affixes==nxt.items[uid].latent_affixes
    return nxt

def input_record(state):
    return {'party':[asdict(p) for p in state.loadout()], 'dust':state.eco.dust,
            'spent_dust':state.spent_dust,'gates':sorted(state.gates),
            'materials':state.eco.materials,'xp':state.eco.roster_xp,
            'economy_hash':state.inventory_hash()}
