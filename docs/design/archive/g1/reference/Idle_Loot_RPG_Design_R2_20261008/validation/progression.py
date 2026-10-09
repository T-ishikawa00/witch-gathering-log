"""Pure offline settlement/inventory reference. Not an iOS persistence adapter.
No wall-clock trust, encryption, or cross-device anti-cheat guarantee is made.
"""
from __future__ import annotations
from copy import deepcopy
from typing import Any
from core import DATA,Rng,SLOTS

CFG=DATA['offline']

def initial_state(now_ms: int=0, seed:int=12345)->dict[str,Any]:
    if not isinstance(now_ms,int): raise ValueError('integer UTC milliseconds required')
    return {'schema_version':1,'generation':0,'last_ms':now_ms,'seed':seed,'route':'ash',
     'remainders_ms':{r:0 for r in CFG['route_families']},'draws':{r:0 for r in CFG['route_families']},
     'inventory':{},'essence':0,'overflow':{},'auto_duplicates':True,'equipped':[],
     'presets':{},'processed':[],'last_receipt':None}

def _loot(state:dict[str,Any],route:str,index:int)->dict[str,Any]:
    route_index=list(CFG['route_families']).index(route)
    seed=(state['seed']^(((index+1)*0x9E3779B9)&0xffffffff)^((route_index+1)*0x85EBCA6B))&0xffffffff
    rng=Rng(seed);slot=SLOTS[rng.next()%len(SLOTS)]
    return {'id':f'{route}:{index}','template_id':f'{slot}_{CFG["route_families"][route]}','locked':False}

def settle(state:dict[str,Any], now_ms:int, request_id:str)->tuple[dict[str,Any],dict[str,Any]]:
    if not isinstance(now_ms,int) or not request_id: raise ValueError('bad settlement request')
    if request_id in state['processed']: return deepcopy(state),{'status':'ALREADY_APPLIED','request_id':request_id}
    if now_ms<state['last_ms']: return deepcopy(state),{'status':'TIME_ANOMALY','request_id':request_id,'awarded_steps':0}
    s=deepcopy(state); raw=now_ms-s['last_ms'];accepted=min(raw,CFG['cap_ms']);route=s['route']
    steps,remainder=divmod(s['remainders_ms'][route]+accepted,CFG['step_ms'])
    receipt={'status':'APPLIED','request_id':request_id,'raw_ms':raw,'credited_ms':accepted,'capped_ms':raw-accepted,'awarded_steps':steps,'new_ids':[],'converted':0,'overflowed':0,'essence_delta':steps*CFG['essence_per_step']}
    family=s['draws'][route]
    for i in range(family,family+steps):
        item=_loot(s,route,i);tpl=item['template_id']
        owned=any(it['template_id']==tpl for it in s['inventory'].values()) or s['overflow'].get(tpl,0)>0
        if s['auto_duplicates'] and owned:
            receipt['converted']+=1;receipt['essence_delta']+=2
        elif len(s['inventory'])<CFG['inventory_capacity']:
            s['inventory'][item['id']]=item;receipt['new_ids'].append(item['id'])
        else:
            s['overflow'][tpl]=s['overflow'].get(tpl,0)+1;receipt['overflowed']+=1
    s['essence']+=receipt['essence_delta'];s['draws'][route]+=steps;s['remainders_ms'][route]=remainder
    s['last_ms']=now_ms;s['generation']+=1;s['last_receipt']=receipt
    s['processed']=(s['processed']+[request_id])[-32:]
    return s,receipt

def switch_route(state:dict[str,Any], now_ms:int, route:str, request_id:str)->tuple[dict[str,Any],dict[str,Any]]:
    if route not in CFG['route_families']: raise ValueError('unknown route')
    s,r=settle(state,now_ms,request_id)
    if r['status']!='APPLIED': return s,r
    s['route']=route
    return s,r

def rebase_clock(state:dict[str,Any], now_ms:int, *, explicit_user_confirmation:bool)->dict[str,Any]:
    if not explicit_user_confirmation: raise PermissionError('clock rebase requires explicit confirmation')
    if not isinstance(now_ms,int): raise ValueError('integer UTC milliseconds required')
    s=deepcopy(state);s['last_ms']=now_ms;s['generation']+=1
    s['last_receipt']={'status':'CLOCK_REBASED','awarded_steps':0}
    return s

def dismantle(state:dict[str,Any], ids:list[str])->dict[str,Any]:
    if len(ids)!=len(set(ids)) or any(i not in state['inventory'] for i in ids): raise ValueError('invalid item ids')
    protected=set(state['equipped'])|{i for p in state['presets'].values() for i in p}
    for i in ids:
        if i in protected or state['inventory'][i]['locked']: raise PermissionError('protected item')
    remaining={i:it for i,it in state['inventory'].items() if i not in ids}
    owned={it['template_id'] for it in remaining.values()}|{k for k,v in state['overflow'].items() if v}
    for i in ids:
        if state['inventory'][i]['template_id'] not in owned: raise PermissionError('cannot destroy final copy of a template in G1')
    s=deepcopy(state);s['inventory']=remaining;s['essence']+=2*len(ids);s['generation']+=1
    return s

def craft(state:dict[str,Any], template_id:str)->dict[str,Any]:
    if template_id not in DATA['items']: raise ValueError('unknown template')
    if state['essence']<CFG['craft_cost']: raise ValueError('insufficient essence')
    if len(state['inventory'])>=CFG['inventory_capacity']: raise ValueError('inventory full; nothing charged')
    s=deepcopy(state);s['generation']+=1;i=f'craft:{s["generation"]}'
    while i in s['inventory']: i+='x'
    s['inventory'][i]={'id':i,'template_id':template_id,'locked':False}
    s['essence']-=CFG['craft_cost'];return s
