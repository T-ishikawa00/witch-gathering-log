from bridge import *
PIN='497549e9339431b5680eaa398fef16ff1b81f117'
REMOTE=[
('growth_r2/data/growth_gear_skills_R2.json','source/r6/vendor/r5/vendor/r01_r4/source/growth_r2/data/growth_gear_skills_R2.json','d248a006df75d206ce5b3e21356f7b5117ba3a0e'),
('growth_r2/validation/reference_model.py','source/r6/vendor/r5/vendor/r01_r4/source/growth_r2/validation/reference_model.py','9f29688ef7b07b2f48bdf12d1ea1a25e489750af'),
('economy_r3/data/economy_R3.json','source/r6/vendor/r5/vendor/r01_r4/source/economy_r3/data/economy_R3.json','fc28f5fe38cf8c897429a704d813fac55b976d9c'),
('support_ai_r6/tools/selected_final.py','source/r6/tools/selected_final.py','c6e33e5e1271ec96ac54f5330051c666c55a27f5'),
('support_ai_r6/tools/support_ai.py','source/r6/tools/support_ai.py','9a1cd161499848eb5b256ac2d3bef16a047707da'),
('support_ai_r6/tools/support_ai_b.py','source/r6/tools/support_ai_b.py','2081e1653a4ff602b0d133178420b92fdbe140b9'),
('balance_r5/tools/battle_r5.py','source/r6/vendor/r5/tools/battle_r5.py','a4072a1b789c75ba42a3615da2535b6ad4221c27'),
('commerce_r2/data/GEAR_METADATA_AND_NEW_AFFIX_PROPOSAL.json','source/after_draw_r4/source/commerce_r2/data/GEAR_METADATA_AND_NEW_AFFIX_PROPOSAL.json','338926c3ad6f68d3a4d48ba412d845278d119d75'),
('gacha_research_r3/data/CANDIDATES_R3.json','source/after_draw_r4/source/research_r3/data/CANDIDATES_R3.json','6dc86cac4e301559fa89a87db42076b7629382df')]
def main():
    refs=[]
    for path,local,expected in REMOTE:
        data=(ROOT/local).read_bytes();got=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
        if got!=expected:raise AssertionError((path,expected,got))
        refs.append({'remote_path':'docs/design/shared/20261010_r1/sources/'+path,'local':local,'git_blob_sha1':got,'sha256':hashlib.sha256(data).hexdigest(),'match':True})
    originals=json.loads((ROOT/'data/SOURCE_FILES.json').read_text())
    for f in originals:assert hashlib.sha256((ROOT/f['path']).read_bytes()).hexdigest()==f['sha256']
    worldids={x['id'] for x in g.WORLD['gear']};commerceids=set(OLD_META);growthids=set(g.GEAR)
    relations=[]
    world={x['id']:x for x in g.WORLD['gear']}
    for tid in sorted(worldids):
        v=g.GEAR[tid];c=OLD_META[tid];w=world[tid]
        row={'id':tid,'world_growth_commerce_name_match':v['name']==c['name']==w['name'],'actor_match':v['actor_ids']==c['actors']==w['actor_ids'],'slot_match':v['slot']==c['slot']==w['slot'],'gate_match':v['unlock_gate']==c['gate']==w['unlock_gate'],'parent_match':v['parent_template_id']==c['parent']==w['parent_template_id']}
        assert all(value for key,value in row.items() if key!='id');relations.append(row)
    m=catalog();aff=[]
    for tid,row in m.items():
        legal=set(g.eligible_affixes(tid));src=OLD_META.get(tid,OLD_META.get(CAT_ANALOGUES.get(tid)))
        aff.append({'id':tid,'origin':'CAT_ANALOGUE_PROPOSAL' if tid in CAT_ANALOGUES else 'COMMERCE_R2','core_in_source':src['core_affix'],'core_runtime_candidate':row['core'],'core_stat':g.AFFIXES[row['core']]['stat'],'min_bp':g.AFFIXES[row['core']]['min_bp'],'max_bp':g.AFFIXES[row['core']]['max_bp'],'commerce_pool_mapped':row['pool'],'natural_legal_pool':sorted(legal),'not_in_gacha':sorted(legal-set(row['pool']))})
    report={'pinned_commit':PIN,'remote_blob_checks':refs,'local_source_files_preserved':len(originals),'world_count':len(worldids),'growth_count':len(growthids),'commerce_count':len(commerceids),'growth_extra':sorted(growthids-worldids),'lost_world_ids':sorted(worldids-growthids),'relations':relations,'affix_mapping':aff,'alias_proposal':{'AF_BARRIER':{'candidate_target':'AF_WARD','runtime_stat':'barrier_bonus_bp','range_bp':[500,1000],'proof_boundary':'Commerce has no numeric implementation; use R2 numeric authority as explicit adapter proposal. This is not a previously approved synonym or in-place migration.'}},'remaining_scope':['All advanced equipment/core_rule/awakening combat is rejected by original R6 slice. Static catalog validity does not mean all33 tested in combat.','AfterDraw visible-affix representation has no immutable hidden slots; new integration creates all3 once, without treating old mock items as saved real items.','The source gacha pool omits haste/CDR/crit/direct damage groups; comparison kept that difference unless explicitly labelled growth-pool sensitivity.']}
    (ROOT/'data/SOURCE_AND_MAPPING_AUDIT.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print('REMOTE',len(refs),'MATCH; LOCAL',len(originals),'PRESERVED; WORLD',len(worldids),'GROWTH',len(growthids))
if __name__=='__main__':main()
