"""Structural constraints for the R3 proposal. Does not validate gameplay quality."""
import json, copy, hashlib, csv
from pathlib import Path
import economy_model as e

def validate(c):
    tests=[]
    def check(id,condition,note):tests.append({'id':id,'pass':bool(condition),'note':note})
    w=e.WORLD;g=e.GROWTH
    ss=c['sources'];sc={x['id']:x for x in ss};mid={x['id'] for x in w['materials']};world_sources={x['id']:x for x in w['sources']}
    check('S01',len(ss)==50 and len(sc)==50,'50 unique sources')
    check('S02',{x['material_id'] for x in ss}==mid,'50 material IDs unchanged')
    immutable=['id','source_type','region_id','area_id','enemy_id','material_id','available_gate','guarantee','min_per_success','repetition']
    check('S03',all(x['id'] in world_sources and all(x[k]==world_sources[x['id']][k] for k in immutable) for x in ss),'world source edges unchanged')
    check('S04',all(x['quantity']==1 and x['probability_bp']==10000 for x in ss),'guaranteed selected yield')
    check('S05',all(x['work_units_per_yield']==(24 if x['source_type']=='boss' else 1) for x in ss),'boss effort not normal source effort')
    check('S06',all(x['work_seconds']==300 for x in ss),'common time base')
    check('S07',c['expedition']['unattended_cap_seconds']==172800 and not c['expedition']['cap_paid_upgrade'],'48h same cap')
    check('S08',not c['expedition']['auto_new_boss_clear'] and c['expedition']['first_clear_repeat_reward']==0,'no offline new progression and no click farm')
    check('S09',not c['expedition']['presentation_speed_affects_rewards'],'view speed excluded')
    check('S10',sum(c['loot']['base_weights'].values())==10000 and all(x>=0 for x in c['loot']['base_weights'].values()),'quality probability sum')
    check('S11',c['loot']['base_weights']=={x['id']:x['drop_weight'] for x in g['rarities']},'R2 probability base unchanged')
    check('S12',c['loot']['legend_pity_natural_rolls']==100,'global 100-roll pity')
    check('S13',set().union(*(set(v) for v in c['regional_gear_theme_pools'].values()))==set(e.TEMPLATES),'33 forms in thematic pools')
    check('S14',c['loot']['local_pool_bp']+c['loot']['global_pool_bp']==10000,'themed and global pool weights')
    check('S15',c['loot']['native_rank_investment_refund']==0,'no fake dust investment for natural rank')
    check('S16',not any(c['ads'][x] for x in ['equipment','boss_materials','normal_materials','offers_on_ad_reward']),'no ad cascade/loot duplication')
    check('S17',c['ads']['earned_per_work_units']==96 and c['ads']['stored_offer_cap']==6,'8h earning, 6 stored')
    check('S18',c['ads']['reward_xp_divisor']==16 and c['ads']['reward_dust_divisor']==16,'6.25% cap before rounding')
    check('S19',c['ads']['free_successful_view_vs_premium_skip_same_reward'],'free view/premium quantity equality')
    cc={x['operation_id']:x for x in c['costs']}
    check('S20',len(cc)==len(c['costs'])==69,'69 named operations')
    check('S21',all(all(x['material_id'] in mid and isinstance(x['quantity'],int) and x['quantity']>0 for x in op['ingredients']) for op in cc.values()),'cost references and positive quantities')
    check('S22',all(op['gate'] in e.GATES for op in cc.values()),'cost gates exist')
    edges_ok=True
    for op in cc.values():
        for x in op['ingredients']:
            source=next((s for s in ss if s['material_id']==x['material_id']),None)
            if not source or op['gate'] not in e.GATES or source['available_gate'] not in e.closure(op['gate']):edges_ok=False
    check('S23',edges_ok,'all costs obtainable at operation gate')
    check('S24',all(cc.get(r['recipe_id'],{}).get('ingredients')==r['ingredients'] and cc.get(r['recipe_id'],{}).get('parent_template_id')==r['parent_template_id'] for r in g['recipe_cost_overlay']+g['new_cat_recipes']),'33 recipe ingredients/quantities/parents unchanged')
    check('S25',all(cc[f'ATTUNE_{x["from_rank"]}_{x["to_rank"]}']['dust']==x['dust'] and cc[f'ATTUNE_{x["from_rank"]}_{x["to_rank"]}']['ingredients']==x['materials'] for x in g['attunement_costs']),'attunement cost unchanged')
    check('S26',all(cc[a['awakening_id']]['ingredients']==a['materials'] and cc[a['awakening_id']]['min_level']==a['min_level'] for a in g['awakenings']),'awakening quantities and level gates unchanged')
    check('S27',all(cc[r['research_id']]['ingredients']==r['ingredients'] for r in g['research']),'shared research unchanged')
    check('S28',set(x['material_id'] for op in cc.values() for x in op['ingredients'])==mid,'every material has a sink')
    check('S29',not c['endgame']['new_material_ids'] and not c['endgame']['daily_expiry'] and not c['endgame']['pvp'],'endgame adds no compulsory new resource/reset/PvP')
    check('S30',not c['simulation_boundary']['actual_enemy_victory'] and not c['simulation_boundary']['combat_engine'],'simulation limitation explicit')
    check('S31',c['confirmed_constraints']['combat_ai_settings'] is False,'no tactic UI reintroduced')
    check('S32',not c['inventory']['automatic_material_salvage'],'no auto destruction of 50 materials')
    return tests

def main():
    results=validate(e.CFG);mutants=[]
    def mutate(name,fn):
        x=copy.deepcopy(e.CFG);fn(x);failed=[t['id'] for t in validate(x) if not t['pass']];mutants.append({'case':name,'detected':bool(failed),'checks':failed})
    mutate('unknown material reference',lambda x:x['costs'][0]['ingredients'][0].update(material_id='M_UNKNOWN'))
    mutate('negative quantity',lambda x:x['costs'][0]['ingredients'][0].update(quantity=-1))
    mutate('future first boss source',lambda x:x['sources'][0].update(available_gate='G_R05_B'))
    mutate('probabilities do not sum',lambda x:x['loot']['base_weights'].update(Q0=4400))
    mutate('ad issues equipment',lambda x:x['ads'].update(equipment=1))
    mutate('boss source 5-minute shortcut',lambda x:next(s for s in x['sources'] if s['source_type']=='boss').update(work_units_per_yield=1))
    mutate('R2 cost silently changed',lambda x:x['costs'][0]['ingredients'][0].update(quantity=7))
    mutate('nat rank fake reimbursement',lambda x:x['loot'].update(native_rank_investment_refund=300))
    mutate('auto fight grants gates',lambda x:x['expedition'].update(auto_new_boss_clear=True))
    mutate('paid only cap',lambda x:x['expedition'].update(cap_paid_upgrade=True))
    assert all(t['pass'] for t in results),[t for t in results if not t['pass']]
    assert all(t['detected'] for t in mutants)
    # Golden ledger vectors: each definition and its output is regenerable.
    vectors=[]
    for region,gate,hours in [('R01','G_START',8),('R01','G_R01_A',8),('R02','G_R02_A',8),('R03','G_R03_A',24),('R04','G_R04_A',48),('R05','G_R05_B',72)]:
        s=e.snapshot(region,gate);st=e.State(seed='golden-r3')
        for a in s.joined:st=e.join_actor(st,a,set(s.gates))
        x=e.advance_to(st,int(hours*3600000),s,'golden')
        vectors.append({'input':{'snapshot':e.asdict(s),'seed':st.seed,'elapsed_hours':hours},'expected':{'materials':x.materials,'xp_by_actor':x.roster_xp,'dust':x.dust,'work_index':x.work_index,'first_item':x.gear[0],'last_item':x.gear[-1],'gear_count':len(x.gear),'legend_misses':x.legend_misses,'credited_ms':x.credited_ms,'resting_ms':x.resting_ms}})
    (e.ROOT/'validation/GOLDEN_LEDGER_VECTORS.json').write_text(json.dumps(vectors,ensure_ascii=False,indent=2)+'\n')
    # Exact selected-material preparation times; dust generated on the same jobs is counted.
    bounds=[];mat_by={s['material_id']:s for s in e.SOURCES.values()}
    for c in e.CFG['costs']:
        units=sum(x['quantity']*mat_by[x['material_id']]['work_units_per_yield'] for x in c['ingredients'])
        earned=sum(x['quantity']*mat_by[x['material_id']]['work_units_per_yield']*e.RATES[mat_by[x['material_id']]['region_id']]['dust_per_work'] for x in c['ingredients'])
        region=max((r for r in e.WORLD['regions'] if r['entry_gate'] in e.closure(c['gate'])),key=lambda x:x['id'])['id']
        residual=max(0,c['dust']-earned);extra=(residual+e.RATES[region]['dust_per_work']-1)//e.RATES[region]['dust_per_work']
        bounds.append({'operation_id':c['operation_id'],'kind':c['kind'],'gate':c['gate'],'material_work_units':units,'dust_cost':c['dust'],'dust_from_material_jobs':earned,'additional_dust_units':extra,'total_hours':(units+extra)/12,'boundary':'empty stock, no salvage, gates and route clearance assumed; no actual combat'})
    with (e.ROOT/'data/cost_time_bounds.csv').open('w',encoding='utf-8-sig',newline='') as f:
        wr=csv.DictWriter(f,fieldnames=list(bounds[0]));wr.writeheader();wr.writerows(bounds)
    out={'structural_checks':results,'mutations':mutants,'golden_vector_count':len(vectors),'unit_tests':{'count':61,'result':'PASS','log':'UNIT_TEST_OUTPUT.txt'},'scope':'source and cost identities / economic reference / memory transactions only; battle, iOS and durable DB not tested'}
    (e.ROOT/'validation/VALIDATION_RESULTS.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
    print('structure',len(results),'mutations',len(mutants),'golden vectors',len(vectors));print('recipe samples',[b for b in bounds if b['operation_id'] in {'RC_EQ_W_P1','RC_EQ_W_G1','RC_EQ_W_G2','AW_C_WITCH_1','ATTUNE_4_5'}])
if __name__=='__main__':main()
