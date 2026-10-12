#!/usr/bin/env python3
"""Create additive, unapproved AIRA attachment-size/angle candidate overlays.
Source art and prior overlay revisions are never mutated.
"""
from pathlib import Path
import json, hashlib, os
ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'native/Art'
CAND=ART/'GeneratedCandidates/EquipmentDetails'
BASE=ART/'runtime_overlay_zzzzzzzzzzzzzzzzzzzzzz_equipment_landmarks_aira_r006.json'
BODYBASE=ART/'runtime_overlay_zzzzzzzzzzzzz_aira_body03_frame_registration_candidate_r004.json'

def atomic_json(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    tmp=path.with_name(path.name+'.tmp')
    tmp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    os.replace(tmp,path)

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

# Semantics overlay: retain every R006 measured point/source proof and add only
# conservative candidate sizing/angles for AIRA detail families.
sem=json.loads(BASE.read_text())
sem['status']='CANDIDATE_PREVIEW_ONLY'
sem['scope']=('AIRA R007 fit-size candidate overlay: inherits all 27 R006 source-keyed landmarks; '
              'adds small-detail family sizes and measured hammer-face angle candidates. '
              'No source art changed; fit remains unapproved pending fresh held-frame review.')
entry=sem['entries']['AIRA']['semanticFrameLandmarksCandidate']
entry['schema']='equipment_semantic_frame_landmarks_r007'
entry['status']='UNAPPROVED_FIT_SIZE_CANDIDATE_INHERITED_R006_MEASUREMENTS'
entry['measurementMethod'] += ' R007 adds metadata-only detail scale/angle candidates; these are not fit approvals.'
for row in entry['rows']:
    overrides=row.setdefault('gear_overrides_candidate',{})
    for suffix in ('01','02','03'):
        overrides[f'EQ_FEET_{suffix}']={'height':0.08,'fitStatus':'UNAPPROVED_SIZE_CANDIDATE','reason':'Small boot-cuff ornament; reduced from 0.13 to avoid detached-looking oversized overlay.'}
        overrides[f'EQ_RING_{suffix}']={'height':0.03,'fitStatus':'UNAPPROVED_SIZE_CANDIDATE','reason':'Finger ornament should remain distinct from the larger hand attachment.'}
    # Source frame suffix describes pose; adjust to the authored visible hammer
    # face plane. Rotation is around the candidate head point and requires native QA.
    source_i=int(row['sourceFrameIndex'])
    # measured face-axis candidate relative to the source custom detail's initial angle
    # (zero leaves the source-authored angle unchanged where parallel).
    angle_by_source={0:22,1:-18,2:-25,3:18,4:0,5:0,6:12,7:8,8:8}
    overrides['EQ_S_03']={
        'height':0.09,
        'angle_degrees':angle_by_source[source_i],
        'fitStatus':'UNAPPROVED_HAMMER_FACE_ORIENTATION_CANDIDATE',
        'sourceFrameIndex':source_i,
        'reason':'Small fitted inlay candidate; rotation follows individually reviewed hammer-head plane. Runtime fit not verified.'
    }
semout=ART/('runtime_overlay_'+'z'*64+'_equipment_landmarks_aira_r007.json')
atomic_json(semout,sem)

# BODY03 uses an earlier frameRegistrationCandidate path that takes priority over
# semanticFrameLandmarksCandidate. Therefore scale is authored in that exact table.
body=json.loads(BODYBASE.read_text())
body['scope']=('AIRA/EQ_BODY_03 R005 size revision: preserves R004 frame points and masks, '
              'shrinks fur insert from detail_scale 0.15 to 0.09. Candidate only; fresh visual QA required.')
fr=body['entries']['DETAIL_EQ_BODY_03']['frameRegistrationCandidate']
fr['status']='UNAPPROVED_FRAME_KEYED_ATTACHMENT_SIZE_CANDIDATE_R005'
fr['scope']='AIRA/EQ_BODY_03 only; inherits all 27 R004 exact body-frame registrations and masks; detail_scale=.09.'
for row in fr['rows']:
    row['detail_scale']=0.09
    row['measurement_status']='UNAPPROVED_SOURCE_FRAME_MEASURED_SIZE_CANDIDATE_R005'
    row['fit_verified_in_runtime']=False
    row['fit_note']='Fur insert reduced to 0.09 to preserve small collar/lining identity; exact placement/mask still needs held-frame visual QA.'
bodyout=ART/('runtime_overlay_'+'z'*64+'_aira_body03_fit_candidate_r005.json')
atomic_json(bodyout,body)

# Human-readable evidence ledger; separates technical exact-row reachability from visual fit.
report={
 'schema':'aira_attachment_fit_r007',
 'status':'CANDIDATE_METADATA_CREATED_VISUAL_FIT_PENDING',
 'humanApproval':False,
 'sourceOverlayR006':str(BASE.relative_to(ROOT)),
 'sourceOverlaySHA256':sha(BASE),
 'outputs':[
  {'path':str(semout.relative_to(ROOT)),'sha256':sha(semout),'rows':len(entry['rows']),'coverage':'27 AIRA body frames; EQ_FEET_01..03/RING_01..03/S_03 overrides'},
  {'path':str(bodyout.relative_to(ROOT)),'sha256':sha(bodyout),'rows':len(fr['rows']),'coverage':'27 exact AIRA body frames; BODY_03 detail_scale 0.09'}],
 'candidateValues':{'BODY_03.detail_scale':0.09,'FEET_01..03.height':0.08,'RING_01..03.height':0.03,'S_03.height':0.09,'S_03.angle_degrees_by_sourceFrameIndex':{'0':22,'1':-18,'2':-25,'3':18,'4':0,'5':0,'6':12,'7':8,'8':8}},
 'evidenceBasis':['R018 exact-held source proof for all 27 source/body frame keys','16px coordinate grids in docs/production/current/art/aira_landmark_contacts_r005/individual/','R018 runtime crops in docs/production/current/art/aira_landmark_contacts_r006/runtime_crops/'],
 'limitations':['No fresh native bundle or held-frame visual fit test has yet used R007.','FEET ankle points are candidate cuff/ankle centers and remain uncertain during crossed-leg walk phases.','S_03 frame angles are source-plane estimates; check against selected custom inlay geometry in all seven states.','Ring placements remain at measured workingHand center with reduced size; finger-level offsets have not been measured.'],
 'sourceArtMutated':False
}
rep=CAND/'aira_attachment_fit_r007.json'; atomic_json(rep,report)
print(json.dumps({'semanticOverlay':str(semout),'semanticSHA256':sha(semout),'bodyOverlay':str(bodyout),'bodySHA256':sha(bodyout),'report':str(rep)},indent=2))
