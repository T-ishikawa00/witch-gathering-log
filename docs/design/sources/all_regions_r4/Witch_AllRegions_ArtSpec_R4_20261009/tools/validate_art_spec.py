"""Validate the R4 design graph; no network, no game-project writes.
This validates declarations and source fidelity, NOT art quality or runtime behavior.
"""
from pathlib import Path
from hashlib import sha256
import json
import sys

ROOT = Path(__file__).resolve().parents[1]

def validate(art: dict, world: dict, source_bytes: bytes) -> list[dict]:
    checks = []
    def check(name: str, condition: bool, detail: str = '') -> None:
        checks.append({'check': name, 'pass': bool(condition), 'detail': detail})
    collections = ['regions','scenes','enemies','materials','gear','material_gear_traces','jobs']
    check('COLLECTIONS_PRESENT', all(isinstance(art.get(k),list) for k in collections))
    if not checks[-1]['pass']: return checks
    source_idx={k:{r['id']:r for r in world[k]} for k in ['regions','areas','enemies','materials','gear','recipes','gates','sources']}
    for k, expected in [('regions',5),('scenes',20),('enemies',30),('materials',50),('gear',29),('jobs',159)]:
        check('COUNT_'+k.upper(),len(art[k])==expected, f'{len(art[k])}/{expected}')
    check('SOURCE_BYTES_HASH', art['meta'].get('source_world_sha256')==sha256(source_bytes).hexdigest())
    check('IDS_UNIQUE',all(len({r.get('asset_id' if k=='jobs' else 'id') for r in art[k]})==len(art[k]) for k in collections))
    check('NO_INVENTED_CANONICAL_ENTITIES',all({r['id'] for r in art[k]}==set(source_idx[k]) for k in ['regions','enemies','materials','gear']))
    check('SOURCE_RECORDS_UNCHANGED',all(r.get('source_record')==source_idx[k].get(r['id']) for k in ['regions','enemies','materials','gear'] for r in art[k]))
    check('RECIPE_RECORDS_UNCHANGED',all(g.get('recipe_source')==source_idx['recipes'].get('RC_'+g['id']) for g in art['gear']))
    check('AREA_RECORDS_UNCHANGED',all(s.get('source_record')==source_idx['areas'].get(s.get('area_id')) for s in art['scenes']))
    check('ENEMY_DROP_UNCHANGED',all(e.get('material_id')==source_idx['enemies'][e['id']]['material_id'] for e in art['enemies']))
    check('ENEMY_LOCATION_UNCHANGED',all(e.get('area_id')==source_idx['enemies'][e['id']]['area_id'] and e.get('region_id')==source_idx['enemies'][e['id']]['region_id'] for e in art['enemies']))
    check('SIX_ENEMIES_TEN_MATERIALS_PER_REGION',all(sum(e['region_id']==r['id'] for e in art['enemies'])==6 and sum(m['region_id']==r['id'] for m in art['materials'])==10 for r in art['regions']))
    check('MATERIAL_SOURCES_EXACT',all(set(m['source_ids'])=={s['id'] for s in world['sources'] if s['material_id']==m['id']} for m in art['materials']))
    check('MATERIAL_SHAPE_REFERENCE_VALID',all(m.get('confusable_with') in source_idx['materials'] and m['confusable_with']!=m['id'] and m.get('distinction_proposal') for m in art['materials']))
    check('GATHER_PROPS_MATCH_SOURCE',all(m['gather_node_required']==(source_idx['materials'][m['id']]['discovery']=='採取') for m in art['materials']) and sum(m['gather_node_required'] for m in art['materials'])==20)
    edges={(i['material_id'],r['output_gear_id'],r['id']) for r in world['recipes'] for i in r['ingredients']}
    actual={(t['material_id'],t['gear_id'],t['recipe_id']) for t in art['material_gear_traces']}
    check('MATERIAL_GEAR_EDGES_EXACT',edges==actual, f'{len(actual)} links')
    check('MATERIAL_GEAR_REVERSE_EXACT',all(set(m['gear_ids'])=={g for mm,g,rc in edges if mm==m['id']} for m in art['materials']))
    check('NO_NUMERIC_INVENTION',all(t['quantity'] is None for t in art['material_gear_traces']) and all(i['quantity'] is None for g in art['gear'] for i in g['recipe_source']['ingredients']))
    check('SCENE_ACTORS_EXCLUDED_FROM_BACKGROUND',all(set(['characters','enemy_bodies','drop_rewards','ui','text','attack_telegraphs'])<=set(s['background_must_exclude']) for s in art['scenes']))
    job_idx={j['asset_id']:j for j in art['jobs']}
    check('SCENE_FAMILY_AND_VARIANT_REFERENCES',all(s['base_family_id'] in job_idx and (s['variant_id'] is None or s['variant_id'] in job_idx) for s in art['scenes']))
    check('SCENE_AREA_IDS_COMPLETE',set(s['area_id'] for s in art['scenes'])==set(source_idx['areas']) and all('main_actor_slots' not in s and s.get('party_definition_policy') for s in art['scenes']))
    check('SCENE_GATHER_AND_ENEMIES_MATCH',all(set(s['gatherable_material_ids'])=={z['material_id'] for z in world['sources'] if z['area_id']==s['area_id'] and z['source_type']=='gather'} and set(s['enemy_ids'])=={e['id'] for e in world['enemies'] if e['area_id']==s['area_id']} for s in art['scenes']))
    check('CLIPS_AND_ANCHORS_PRESENT',all(set(['idle','anticipate','execute','recover','hit','resolve'])<=set(e['required_clips']) and set(['ground','body_center','head','action_origin','material_reference','nameplate'])<=set(e['required_anchors']) for e in art['enemies']))
    check('SCALE_PROPOSALS_BOUNDED',all(isinstance(e['body_height_H_proposal'],(float,int)) and 0.2<=e['body_height_H_proposal']<=4 for e in art['enemies']))
    check('NO_UNVERIFIED_RUNTIME_SUCCESS',all(e['approvals']['ios']=='NOT_TESTED' and e['approvals']['engine']=='NOT_TESTED' for e in art['enemies']) and all(j['ios_qa']=='NOT_TESTED' for j in art['jobs']))
    check('JOB_DEPENDENCIES_VALID',all(d in job_idx for j in art['jobs'] for d in j['depends_on']))
    check('NO_FABRICATED_FILES',all(j['source_path'] is None and j['export_paths']==[] and j['sha256'] is None for j in art['jobs']))
    check('NO_NEW_PRODUCTION_AUTHORIZATION',all(j['production_permission']=='NOT_GRANTED_BY_THIS_PACKAGE' for j in art['jobs']))
    check('NO_MAC_SAVE_CLAIM',art['meta'].get('mac_saved_by_chat') is False)
    check('SMITH_ATTACHMENT_STILL_BLOCKED',next(g for g in art['gear'] if g['id']=='EQ_S_01')['presentation_mode_proposal']=='ICON_ONLY_ATTACHMENT_BLOCKED')
    # detect potential cycle in package dependencies; cannot infer gameplay balance
    state={}
    def visit(n):
        if state.get(n)==1:return False
        if state.get(n)==2:return True
        state[n]=1
        for dep in job_idx[n]['depends_on']:
            if dep not in job_idx or not visit(dep): return False
        state[n]=2
        return True
    check('DEPENDENCY_GRAPH_ACYCLIC',all(visit(n) for n in job_idx))
    return checks

def main()->int:
    raw=(ROOT/'source_snapshot/world_catalog_R1.json').read_bytes()
    art=json.loads((ROOT/'data/art_catalog_R4.json').read_text())
    result=validate(art,json.loads(raw),raw)
    report={'scope':'structural design validation only','checks':len(result),'passed':sum(r['pass'] for r in result),'failed':sum(not r['pass'] for r in result),'items':result,'not_verified':['new artwork','animation quality','game balance','iPhone performance','Mac save','revenue']}
    out=ROOT/'qa/STRUCTURAL_VALIDATION_R4.json'
    out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='items'},ensure_ascii=False))
    for r in result:
        if not r['pass']:print('FAIL',r['check'],r['detail'])
    return 0 if report['failed']==0 else 1
if __name__=='__main__':sys.exit(main())
