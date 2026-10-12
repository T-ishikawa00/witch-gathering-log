#!/usr/bin/env python3
"""R008: additive AIRA fit candidates with corrected runtime overlay precedence."""
from pathlib import Path
import json, hashlib, os
ROOT=Path(__file__).resolve().parents[2]; ART=ROOT/'native/Art'; CAND=ART/'GeneratedCandidates/EquipmentDetails'
BASE=ART/'runtime_overlay_zzzzzzzzzzzzzzzzzzzzzz_equipment_landmarks_aira_r006.json'
BODYBASE=ART/'runtime_overlay_zzzzzzzzzzzzz_aira_body03_frame_registration_candidate_r004.json'
def atomic(path,data):
 path.parent.mkdir(parents=True,exist_ok=True); tmp=path.with_name(path.name+'.tmp'); tmp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n'); os.replace(tmp,path)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
# Retire R007 due merge precedence, preserving its evidence and outputs.
for p in [ART/('runtime_overlay_'+'z'*64+'_equipment_landmarks_aira_r007.json'),ART/('runtime_overlay_'+'z'*64+'_aira_body03_fit_candidate_r005.json')]:
 if p.exists():
  d=json.loads(p.read_text()); d['status']='REJECTED_SUPERSEDED_R008_MERGE_ORDER_FIX'; d['superseded_by']='AIRA attachment fit R008'; d['superseded_reason']='R007 semantic overlay copied DETAIL_EQ_BODY_03 from R006 after the size-only body overlay, resetting effective detail_scale to 0.15. R008 separates actor landmarks from the DETAIL entry and sorts the BODY03 override last.'; atomic(p,d)
# Semantic row overrides; source points are inherited from R006, source art unchanged.
sem=json.loads(BASE.read_text()); sem['status']='CANDIDATE_PREVIEW_ONLY'; sem['scope']='AIRA R008 fit candidates: exact R006 semantic points plus family scale/angle overrides; excludes unrelated DETAIL_EQ_BODY_03 entry to prevent merge-order reset. Human fit remains unapproved.'
sem['entries'].pop('DETAIL_EQ_BODY_03',None)
entry=sem['entries']['AIRA']['semanticFrameLandmarksCandidate']; entry['schema']='equipment_semantic_frame_landmarks_r008'; entry['status']='UNAPPROVED_FIT_SIZE_CANDIDATE_INHERITED_R006_MEASUREMENTS'; entry['measurementMethod']+=' R008 adds metadata-only detail size/angle candidates; not a fit approval.'
angle={0:22,1:-18,2:-25,3:18,4:0,5:0,6:12,7:8,8:8}
for row in entry['rows']:
 ov=row.setdefault('gear_overrides_candidate',{})
 for i in ('01','02','03'):
  ov[f'EQ_FEET_{i}']={'height':0.08,'fitStatus':'UNAPPROVED_SIZE_CANDIDATE','reason':'Small boot-cuff ornament; reduced from renderer default 0.13 pending visual fit.'}
  ov[f'EQ_RING_{i}']={'height':0.03,'fitStatus':'UNAPPROVED_SIZE_CANDIDATE','reason':'Small finger ornament distinct from larger hand detail; anchor remains measured workingHand pending point fit.'}
 si=int(row['sourceFrameIndex']); ov['EQ_S_03']={'height':0.09,'angle_degrees':angle[si],'fitStatus':'UNAPPROVED_HAMMER_FACE_ORIENTATION_CANDIDATE','sourceFrameIndex':si,'reason':'Small inlay candidate; angle estimate follows authored hammer-face plane and requires held-frame QA.'}
sem['entries']['AIRA']['semanticFrameLandmarksCandidate']=entry
semp=ART/('runtime_overlay_'+'z'*72+'_equipment_landmarks_aira_r008.json'); atomic(semp,sem)
# The exact frameRegistration table wins BODY03 lookup, so tune its actual consumed field.
body=json.loads(BODYBASE.read_text()); body['status']='CANDIDATE_PREVIEW_ONLY'; body['scope']='AIRA/EQ_BODY_03 R008 fit-size candidate; inherits R004 rows/masks, detail_scale 0.09. No source pixels changed.'
fr=body['entries']['DETAIL_EQ_BODY_03']['frameRegistrationCandidate']; fr['status']='UNAPPROVED_FRAME_KEYED_ATTACHMENT_SIZE_CANDIDATE_R008'; fr['scope']='AIRA/EQ_BODY_03 only; exact 27-frame registration with small fur insert detail_scale=0.09.'
for row in fr['rows']:
 row['detail_scale']=0.09; row['measurement_status']='UNAPPROVED_SOURCE_FRAME_MEASURED_SIZE_CANDIDATE_R008'; row['fit_verified_in_runtime']=False; row['fit_note']='Reduced fur insert candidate. Placement and face/arm mask still need synchronized native visual QA.'
# Sort after semantic R008 so no later overlay resets this exact consumed table.
body['entries']['DETAIL_EQ_BODY_03']['frameRegistrationCandidate']=fr
bodyp=ART/('runtime_overlay_'+'z'*72+'_zz_aira_body03_fit_r008.json'); atomic(bodyp,body)
report={'schema':'aira_attachment_fit_r008','status':'CANDIDATE_METADATA_CREATED_RUNTIME_BUILD_PASS_VISUAL_FIT_PENDING','humanApproval':False,'buildBundle':'native/build/app_20261010T215112/WitchGathering.app','buildStatus':'SIMULATOR_BUILD_PASS','buildExecutableSHA256':'ab4a23a9ee406ea4d8e87c50a00e07ee47d415f729727a718b4e02097f58c932','buildRendererSHA256':'420b1e7d2cef74f352e3428ee438ab7b5494ef35f39b2d33607e1e2303c3eeac','warning':'R008 files were added after that frozen bundle; bundle contains R007 and effective BODY03 remained 0.15 due overlay merge order. Do not use for R008 visual fit.','sourceOverlayR006SHA256':sha(BASE),'outputs':[{'path':str(semp.relative_to(ROOT)),'sha256':sha(semp),'rows':len(entry['rows'])},{'path':str(bodyp.relative_to(ROOT)),'sha256':sha(bodyp),'rows':len(fr['rows'])}],'effectiveCandidateValues':{'BODY_03.detail_scale':0.09,'FEET_01..03.height':0.08,'RING_01..03.height':0.03,'S_03.height':0.09,'S_03.angle_degrees_source_suffix':angle},'sourceArtMutated':False,'visualFit':'PENDING_FRESH_R008_BUNDLE_AND_ALL_27_FRAMES_X_3_APPLICABLE_TIERS'}
atomic(CAND/'aira_attachment_fit_r008.json',report)
print(json.dumps({'semantic':str(semp),'semantic_sha256':sha(semp),'body':str(bodyp),'body_sha256':sha(bodyp),'report':str(CAND/'aira_attachment_fit_r008.json')},indent=2))
