#!/usr/bin/env python3
"""Integrate the individually measured R006 BODY03 points into the runtime table."""
from pathlib import Path
import json,hashlib,os
ROOT=Path(__file__).resolve().parents[2]; ART=ROOT/'native/Art'; CAND=ART/'GeneratedCandidates/EquipmentDetails'
source=CAND/'aira_body03_frame_registration_r006.json'
r008=ART/('runtime_overlay_'+'z'*72+'_zz_aira_body03_fit_r008.json')
# Keep history, remove stale points from the effective overlay stream.
d=json.loads(r008.read_text()); d['status']='REJECTED_SUPERSEDED_R009_R006_POINT_INTEGRATION'; d['superseded_by']='AIRA BODY03 exact measured rows R009'; d['superseded_reason']='R008 copied R004 anchor/mask points; R018 held capture execute:1 resolved to x168,y145 instead of R006 source-grid measurement x145,y141. R009 uses all 27 rows from aira_body03_frame_registration_r006.json.'
tmp=r008.with_name(r008.name+'.tmp');tmp.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n');os.replace(tmp,r008)
base=json.loads(source.read_text()); assert len(base['rows'])==27
for row in base['rows']:
 row['detail_scale']=0.09
 row['measurement_status']='UNAPPROVED_R006_INDIVIDUAL_SOURCE_GRID_POINT_AND_R009_SIZE_CANDIDATE'
 row['fit_verified_in_runtime']=False
 row['fit_note']='Anchor and foreground masks are inherited from individually measured R006 source-grid candidate; detail_scale=.09. Runtime held capture shows R008 older anchor was wrong, so R009 must be freshly tested.'
entry={'frameRegistrationCandidate':{
 'schema':'aira_body03_frame_registration_r009',
 'status':'UNAPPROVED_R006_MEASURED_ROWS_R009_RUNTIME_CANDIDATE',
 'humanApproval':False,
 'key':['actorID','bodyAssetID','frameIndex','canvas_px'],
 'coordinate_origin':'top_left_canvas_pixels',
 'mask_method':'Candidate body-frame foreground ellipses are source-grid measured in the corresponding current authored frame; runtime fit still unverified.',
 'sourceEvidence':str(source.relative_to(ROOT)),
 'sourceEvidenceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),
 'rows':base['rows']}}
overlay={'status':'CANDIDATE_PREVIEW_ONLY','scope':'AIRA DETAIL_EQ_BODY_03 only: integrate exact 27 individually measured R006 anchors/masks, preserving source art; set small collar detail scale=.09. UNAPPROVED pending fresh held-frame review.','humanApproval':False,'entries':{'DETAIL_EQ_BODY_03':entry}}
out=ART/('runtime_overlay_'+'z'*72+'_zzz_aira_body03_measured_r009.json');tmp=out.with_name(out.name+'.tmp');tmp.write_text(json.dumps(overlay,ensure_ascii=False,indent=2)+'\n');os.replace(tmp,out)
report={'schema':'aira_body03_exact_rows_r009','status':'CANDIDATE_CREATED_SUPERSEDES_R008_STALE_ANCHORS','humanApproval':False,'sourcePath':str(source.relative_to(ROOT)),'sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'sourceRows':len(base['rows']),'runtimeOverlay':str(out.relative_to(ROOT)),'runtimeOverlaySHA256':hashlib.sha256(out.read_bytes()).hexdigest(),'detailScale':0.09,'sourceSHAValidation':[],'runtimeVisualFit':'PENDING_FRESH_BUNDLE_CAPTURE'}
for r in base['rows']:
 p=ROOT/r['source_path']; h=hashlib.sha256(p.read_bytes()).hexdigest(); report['sourceSHAValidation'].append({'bodyAssetID':r['bodyAssetID'],'frameIndex':r['frameIndex'],'expectedSHA256':r['sourceSHA256'],'actualSHA256':h,'pass':h==r['sourceSHA256']}); assert h==r['sourceSHA256']
rep=CAND/'aira_body03_exact_rows_r009.json';tmp=rep.with_name(rep.name+'.tmp');tmp.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');os.replace(tmp,rep)
print(json.dumps({'overlay':str(out),'overlaySHA256':hashlib.sha256(out.read_bytes()).hexdigest(),'rows':len(base['rows']),'execute1':next({'anchor':r['anchor_px_top_left'],'scale':r['detail_scale'],'masks':r['foreground_occlusion_px']} for r in base['rows'] if r['sourceRowState']=='execute' and r['sourceFrameIndex']==4)},ensure_ascii=False,indent=2))
