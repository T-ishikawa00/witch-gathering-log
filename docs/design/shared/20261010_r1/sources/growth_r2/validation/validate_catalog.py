"""原本保持・参照・解放順・数式範囲を実検査する。結果はvalidation/へ保存。"""
from __future__ import annotations
import copy, csv, hashlib, json, sys
from dataclasses import replace
from pathlib import Path
from reference_model import *


def structural_checks(d:dict,w:dict) -> list[dict]:
    out=[]
    def ck(name,ok,details=''):out.append({'check':name,'pass':bool(ok),'details':details})
    gs={g['id']:g['rank'] for g in w['gates']}; mat={m['id']:m for m in w['materials']}
    gt={g['template_id']:g for g in d['gear_templates']}; rt={r['recipe_id']:r for r in d['recipe_cost_overlay']}
    ck('source_ids_and_names_29',all(g['id'] in gt and gt[g['id']]['name']==g['name'] for g in w['gear']))
    ck('source_slots_and_actor_eligibility',all(gt[g['id']]['actor_ids']==g['actor_ids'] and gt[g['id']]['slot']==g['slot'] for g in w['gear']))
    ck('source_parent_and_gate',all(gt[g['id']]['parent_template_id']==g['parent_template_id'] and gt[g['id']]['unlock_gate']==g['unlock_gate'] for g in w['gear']))
    ck('source_ingredient_edges_preserved',all(r['id'] in rt and [x['material_id'] for x in rt[r['id']]['ingredients']]==[x['material_id'] for x in r['ingredients']] for r in w['recipes']))
    ck('original_quantity_null_retained',all(x['quantity'] is None for r in w['recipes'] for x in r['ingredients']))
    ck('new_ids_do_not_collide',len(gt)==len(d['gear_templates']) and all(g['template_id'] not in {x['id'] for x in w['gear']} for g in d['gear_templates'] if g['origin']=='G2C_R2_ADDITION_PROPOSED'))
    ck('exact_four_actor_ids',{a['actor_id'] for a in d['actors']}=={a['id'] for a in w['actors']})
    ck('no_tactics_or_manual_skills',all(d['confirmed_constraints'][x] is False for x in ['manual_skill_cast','tactics_presets','ai_rule_editor','external_generation_ai_at_runtime']))
    ck('four_skills_each',all(len([s for s in d['skills'] if s['actor_id']==a['actor_id']])==4 for a in d['actors']))
    ck('skill_ids_unique',len({s['skill_id'] for s in d['skills']})==len(d['skills']))
    ck('no_growth_reset',all(not a['level_reset'] and not a['gear_reset'] and not a['duplicate_character_required'] for a in d['awakenings']))
    ck('three_awakenings_each',all([x['stage'] for x in d['awakenings'] if x['actor_id']==a['actor_id']]==[1,2,3] for a in d['actors']))
    rows=[]
    for r in d['recipe_cost_overlay']+d['new_cat_recipes']:
        rows.append((r['recipe_id'],r['unlock_gate'],r['ingredients']))
    for r in d['research']:rows.append((r['research_id'],r['gate'],r['ingredients']))
    for a in d['awakenings']:rows.append((a['awakening_id'],a['unlock_gate'],a['materials']))
    for r in d['attunement_costs']:rows.append((str(r['to_rank']),r['gate'],r['materials']))
    refsok=all(g in gs and all(x['material_id'] in mat for x in ins) for _,g,ins in rows)
    ck('all_consumable_references_exist',refsok)
    ck('positive_integer_costs',all(type(x['quantity']) is int and x['quantity']>0 for _,_,ins in rows for x in ins))
    ck('materials_available_by_unlock',refsok and all(gs[mat[x['material_id']]['first_available_gate']]<=gs[g] for _,g,ins in rows for x in ins))
    ck('recipe_parent_available',all(r['parent_template_id'] is None or r['parent_template_id'] in gt and gs[gt[r['parent_template_id']]['unlock_gate']]<=gs[r['unlock_gate']] for r in d['recipe_cost_overlay']+d['new_cat_recipes']))
    # Full DFS instead of relying on template order.
    active=set();visited=set();cycle=False
    def visit(t):
        nonlocal cycle
        if t in active:cycle=True;return
        if t in visited:return
        active.add(t)
        p=gt[t]['parent_template_id']
        if p in gt:visit(p)
        active.remove(t);visited.add(t)
    for t in gt:visit(t)
    ck('evolution_graph_acyclic',not cycle)
    ck('six_valid_slots_for_each_actor',all({g['slot'] for g in d['gear_templates'] if a['actor_id'] in g['actor_ids']}==set(a['slot_keys']) for a in d['actors']))
    ck('cat_not_allowed_human_boots','C_FAMILIAR' not in gt['EQ_FEET_01']['actor_ids'])
    ck('conditional_drop_weights_sum',sum(q['drop_weight'] for q in d['rarities'])==10000)
    ck('rarity_not_primary_multiplier',d['equipment_rules']['rarity_primary_multiplier'] is False)
    ck('stat_growth_positive',all(all(v>0 for v in a['per_level'].values()) for a in d['actors']))
    ck('speed_and_reduction_finite',d['caps']['cdr_bp']<10000 and d['caps']['crit_chance_bp']<10000 and d['caps']['defense_reduction_bp']<10000)
    ck('no_reaction_recursion',d['combat']['reaction_depth_max']==1)
    ck('last_awakening_after_final_boss',all(a['unlock_gate']=='G_R05_B' for a in d['awakenings'] if a['stage']==3))
    ck('world_no_new_material_id',len(w['materials'])==50 and all(x['material_id'] in mat for _,_,ins in rows for x in ins))
    ck('all_numeric_overlays_marked',all(r['status']=='TUNING_PROPOSAL_NOT_WRITTEN_TO_WORLD_R1' for r in d['recipe_cost_overlay']))
    ck('not_battle_engine_or_winrate_proof','4人自動戦闘エンジンではない' in d['validation_boundary'])
    return out


def mutation_checks():
    tests=[]
    def run(name,change):
        d=copy.deepcopy(DATA);change(d);bad=[x['check'] for x in structural_checks(d,WORLD) if not x['pass']]
        tests.append({'mutation':name,'detected':bool(bad),'failed_checks':bad})
    run('旧世界の素材を勝手に差替え',lambda d:d['recipe_cost_overlay'][0]['ingredients'][0].update(material_id='M_R05_BB'))
    run('未来素材を覚醒1へ要求',lambda d:d['awakenings'][0]['materials'][0].update(material_id='M_R05_BB'))
    run('作戦プリセットの再導入',lambda d:d['confirmed_constraints'].update(tactics_presets=True))
    run('猫に人用ブーツの適格権',lambda d:next(g for g in d['gear_templates'] if g['template_id']=='EQ_FEET_01')['actor_ids'].append('C_FAMILIAR'))
    run('0個の素材コスト',lambda d:d['recipe_cost_overlay'][0]['ingredients'][0].update(quantity=0))
    run('進化循環',lambda d:d['gear_templates'][0].update(parent_template_id='EQ_W_P1'))
    run('クールダウン100%短縮',lambda d:d['caps'].update(cdr_bp=10000))
    run('未定義素材ID',lambda d:d['new_cat_recipes'][0]['ingredients'][0].update(material_id='M_MISSING'))
    return tests


def numeric_sweep():
    count=0;fail=[]; snapshots=[]
    templates={
        'C_WITCH':['EQ_W_01','EQ_BODY_01','EQ_HAND_01','EQ_FEET_01','EQ_AMU_01','EQ_RING_01'],
        'C_APPRENTICE':['EQ_A_01','EQ_BODY_01','EQ_HAND_01','EQ_FEET_01','EQ_AMU_01','EQ_RING_01'],
        'C_SMITH':['EQ_S_01','EQ_BODY_01','EQ_HAND_01','EQ_FEET_01','EQ_AMU_01','EQ_RING_01'],
        'C_FAMILIAR':['EQ_F_01','EQ_F_BODY_01','EQ_F_HAND_01','EQ_F_FEET_01','EQ_AMU_01','EQ_F_RING_01']}
    for a in DATA['actors']:
        aid=a['actor_id']
        for rank in range(1,6):
            for enh in range(RANKS[rank]['max_enhance']+1):
                items=[replace(create_item(aid+'_'+t,t,'Q3','sweep'),rank=rank,enhancement=enh) for t in templates[aid]]
                last=None
                for level in range(1,61):
                    s=actor_stats(aid,level,items)
                    count+=1
                    ok=all(s[x]>0 for x in ['hp','power','defense']) and all(0<=s.get(k,0)<=v for k,v in DATA['caps'].items() if k.endswith('_bp') and k in s)
                    if last:ok=ok and all(s[x]>last[x] for x in ['hp','power','defense'])
                    if not ok:fail.append([aid,level,rank,enh])
                    last=s
        for level in [1,12,30,60]:
            s=actor_stats(aid,level,[])
            snapshots.append({'actor_id':aid,'name':a['display_name'],'level':level,'equipment':'none','hp':s['hp'],'power':s['power'],'defense':s['defense']})
    damage_checks=0
    for lv in [1,12,30,60]:
        prev=10001
        for df in range(0,5001,10):
            d=direct_incoming(10000,df,lv)
            if d>prev or d<=0:fail.append(['defense',lv,df])
            prev=d;damage_checks+=1
    return {'stat_cases':count,'defense_curve_cases':damage_checks,'failed_cases':fail,'label':'数式の有界性・単調性のみ。全組合せが同じ進行段階で装備可能という意味ではない。'},snapshots


def main():
    checks=structural_checks(DATA,WORLD)
    original=hashlib.sha256((ROOT/'reference/world_catalog_R1_UNCHANGED.json').read_bytes()).hexdigest()
    checks.append({'check':'source_file_sha256_matches','pass':original==DATA['meta']['source_world_sha256']})
    muts=mutation_checks();num,snap=numeric_sweep()
    rep={'scope':'設計データ/純粋数式/装備操作の検査。戦闘・実機・売上を保証しない。','structural':checks,'mutation_tests':muts,'numeric_sweep':num,'totals':{'structural_pass':sum(x['pass'] for x in checks),'structural_total':len(checks),'mutations_detected':sum(x['detected'] for x in muts),'mutations_total':len(muts)},'battle_simulation':'NOT_RUN','human_playtest':'NOT_RUN','ios_test':'NOT_RUN'}
    (ROOT/'validation/VALIDATION_RESULTS.json').write_text(json.dumps(rep,ensure_ascii=False,indent=2)+'\n')
    with (ROOT/'data/stat_examples.csv').open('w',encoding='utf-8-sig',newline='') as f:
        wr=csv.DictWriter(f,fieldnames=snap[0].keys());wr.writeheader();wr.writerows(snap)
    with (ROOT/'data/equipment_recipe_costs.csv').open('w',encoding='utf-8-sig',newline='') as f:
        wr=csv.writer(f);wr.writerow(['recipe_id','gear_id','gate','material_id','material_name','quantity','status'])
        mat={m['id']:m['name'] for m in WORLD['materials']}
        for r in DATA['recipe_cost_overlay']+DATA['new_cat_recipes']:
            for ing in r['ingredients']:wr.writerow([r['recipe_id'],r['output_gear_id'],r['unlock_gate'],ing['material_id'],mat[ing['material_id']],ing['quantity'],r['status']])
    print(json.dumps(rep['totals'],ensure_ascii=False));print(num)
    if not all(x['pass'] for x in checks) or not all(x['detected'] for x in muts) or num['failed_cases']:raise SystemExit(1)
if __name__=='__main__':main()
