#!/usr/bin/env python3
"""Verify effective R009 BODY03 anchors and masks equal all measured R006 rows."""
from pathlib import Path
import json,glob,copy,hashlib,os
ROOT=Path(__file__).resolve().parents[2];ART=ROOT/'native/Art';base_path=ART/'runtime_index.json';idx=json.loads(base_path.read_text())
files=[ART/'generated_runtime_overlay.json',ART/'generated_motion_metadata_overlay_r001.json',*map(Path,sorted(glob.glob(str(ART/'runtime_overlay_*.json'))))]
baseidx=copy.deepcopy(idx); idx_without_aira=copy.deepcopy(idx)
applied=[];rejected=[]
for p in files:
 if not p.exists():continue
 raw=p.read_bytes();ov=json.loads(raw); rec={'path':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(raw).hexdigest(),'status':ov.get('status','UNSPECIFIED')}
 if str(rec['status']).startswith('REJECTED'):rejected.append(rec);continue
 applied.append(rec)
 for key,value in ov.get('entries',{}).items():
  target=idx['entries'].setdefault(key,{})
  for field,item in value.items():
   if field in ('clips','sequenceFrames') and isinstance(item,dict):
    if not isinstance(target.get(field),dict):target[field]={}
    target[field].update(item)
   else:target[field]=item
source_path=ROOT/'native/Art/GeneratedCandidates/EquipmentDetails/aira_body03_frame_registration_r006.json';src=json.loads(source_path.read_text())['rows']
eff=idx['entries']['DETAIL_EQ_BODY_03']['frameRegistrationCandidate']['rows']
assert len(src)==len(eff)==27
key=lambda r:(r['actorID'],r['bodyAssetID'],r['frameIndex'],tuple(r['canvas_px']))
srcmap={key(r):r for r in src}; effmap={key(r):r for r in eff}; assert len(srcmap)==len(effmap)==27
rows=[]
for k,s in srcmap.items():
 e=effmap[k]
 match=e['anchor_px_top_left']==s['anchor_px_top_left'] and e['foreground_occlusion_px']==s['foreground_occlusion_px'] and abs(e['detail_scale']-.09)<1e-9 and e.get('sourceSHA256')==s.get('sourceSHA256')
 rows.append({'actorID':k[0],'bodyAssetID':k[1],'frameIndex':k[2],'sourceFrameIndex':s.get('sourceFrameIndex'),'sourceRowState':s.get('sourceRowState'),'expectedAnchor':s['anchor_px_top_left'],'effectiveAnchor':e['anchor_px_top_left'],'expectedForegroundMask':s['foreground_occlusion_px'],'effectiveForegroundMask':e['foreground_occlusion_px'],'expectedScale':0.09,'effectiveScale':e['detail_scale'],'expectedSourceSHA256':s['sourceSHA256'],'effectiveSourceSHA256':e.get('sourceSHA256'),'pass':match})
 assert match,(k,rows[-1])
# Exclude only the AIRA R008 semantic and BODY03 R009 overlays; all other candidate overlays affect both baselines.
idx_without_aira=copy.deepcopy(baseidx)
for p in files:
 if not p.exists():continue
 ov=json.loads(p.read_bytes())
 if str(ov.get('status','')).startswith('REJECTED'):continue
 if p.name.endswith('_equipment_landmarks_aira_r008.json') or p.name.endswith('_zz_aira_body03_measured_r009.json'):continue
 for key,value in ov.get('entries',{}).items():
  target=idx_without_aira['entries'].setdefault(key,{})
  for field,item in value.items():
   if field in ('clips','sequenceFrames') and isinstance(item,dict):
    if not isinstance(target.get(field),dict):target[field]={}
    target[field].update(item)
   else:target[field]=item
for actor in ('ERNA','LUNA','NOIR'):
 assert idx_without_aira['entries'].get(actor,{})==idx['entries'].get(actor,{}),(actor,'AIRA R008/R009 changed another actor entry')
report={'schema':'aira_body03_r009_effective_landmark_audit_r001','status':'PASS_ALL_27_MEASURED_TUPLES_MATCH','humanApproval':False,'method':'Replay exact prepare_resources overlay merge order, then compare effective runtime BODY03 row point, full foreground mask, canvas/body key, scale, and source SHA against all individually measured R006 rows.','runtimeIndexSHA256':hashlib.sha256(base_path.read_bytes()).hexdigest(),'sourceRowsPath':str(source_path.relative_to(ROOT)),'sourceRowsSHA256':hashlib.sha256(source_path.read_bytes()).hexdigest(),'effectiveR009OverlayOrder':[x for x in applied if 'aira_body03_measured_r009' in x['path']],'rejectedSuperseded':[x for x in rejected if 'fit_candidate_r005' in x['path'] or 'body03_fit_r008' in x['path']],'checks':{'sourceRows':len(src),'effectiveRows':len(eff),'uniqueExactKeys':len(effmap),'allAnchorAndMaskAndScaleSHAValuesMatch':True,'otherActorsChangedByR009':[]},'rowComparisons':rows,'nativeBuild':'PENDING_R009_BUNDLE','visualFit':'PENDING_R009_HELD_FRAME_REVIEW'}
out=ROOT/'docs/production/current/art/aira_body03_r009_effective_landmark_audit_r001.json';out.parent.mkdir(parents=True,exist_ok=True);tmp=out.with_suffix('.json.tmp');tmp.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');os.replace(tmp,out)
print(json.dumps({'status':report['status'],'path':str(out),'rows':len(rows),'allMatch':all(r['pass'] for r in rows),'execute1':next(r for r in rows if r['sourceRowState']=='execute' and r['sourceFrameIndex']==4)},ensure_ascii=False,indent=2))
