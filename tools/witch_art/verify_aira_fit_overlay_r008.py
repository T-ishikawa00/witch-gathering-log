#!/usr/bin/env python3
"""Verify R008 overlay order, effective AIRA candidate values, and actor scope."""
from pathlib import Path
import copy, glob, hashlib, json, os
ROOT=Path(__file__).resolve().parents[2]; ART=ROOT/'native/Art'
base_path=ART/'runtime_index.json'; base=json.loads(base_path.read_text())
idx=copy.deepcopy(base)
files=[ART/'generated_runtime_overlay.json',ART/'generated_motion_metadata_overlay_r001.json',*map(Path,sorted(glob.glob(str(ART/'runtime_overlay_*.json'))))]
applied=[]; rejected=[]
for p in files:
 if not p.exists(): continue
 raw=p.read_bytes(); ov=json.loads(raw); rec={'path':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(raw).hexdigest(),'status':ov.get('status','UNSPECIFIED')}
 if str(rec['status']).startswith('REJECTED'):
  rejected.append(rec); continue
 applied.append(rec)
 for key,entry in ov.get('entries',{}).items():
  target=idx['entries'].setdefault(key,{})
  for field,value in entry.items():
   if field in ('clips','sequenceFrames') and isinstance(value,dict):
    if not isinstance(target.get(field),dict): target[field]={}
    target[field].update(value)
   else: target[field]=value

def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
sem_path=ART/('runtime_overlay_'+'z'*72+'_equipment_landmarks_aira_r008.json')
body_path=ART/('runtime_overlay_'+'z'*72+'_zz_aira_body03_fit_r008.json')
sem=json.loads(sem_path.read_text()); body=json.loads(body_path.read_text())
sem_entries=set(sem['entries']); body_entries=set(body['entries'])
assert sem_entries=={'AIRA'},sem_entries
assert body_entries=={'DETAIL_EQ_BODY_03'},body_entries
assert applied.index(next(x for x in applied if x['path']==str(sem_path.relative_to(ROOT)))) < applied.index(next(x for x in applied if x['path']==str(body_path.relative_to(ROOT))))
A=idx['entries']['AIRA']['semanticFrameLandmarksCandidate']['rows']; assert len(A)==27
assert len({(r['actorID'],r['bodyAssetID'],r['frameIndex'],tuple(r['canvas_px'])) for r in A})==27
source_results=[]
for r in A:
 p=ROOT/r['source_path']; actual=digest(p); source_results.append({'bodyAssetID':r['bodyAssetID'],'runtimeFrameIndex':r['frameIndex'],'sourceSHA256':r['sourceSHA256'],'actualSHA256':actual,'pass':actual==r['sourceSHA256']})
 assert actual==r['sourceSHA256']
 overrides=[r['gear_overrides_candidate'][f'EQ_FEET_{i}']['height'] for i in ('01','02','03')]
 rings=[r['gear_overrides_candidate'][f'EQ_RING_{i}']['height'] for i in ('01','02','03')]
 assert overrides==[0.08]*3 and rings==[0.03]*3
 s=r['gear_overrides_candidate']['EQ_S_03']; assert s['height']==0.09 and s['sourceFrameIndex']==r['sourceFrameIndex'] and isinstance(s['angle_degrees'],(int,float))
bodyrows=idx['entries']['DETAIL_EQ_BODY_03']['frameRegistrationCandidate']['rows']; assert len(bodyrows)==27
assert len({(r['actorID'],r['bodyAssetID'],r['frameIndex'],tuple(r['canvas_px'])) for r in bodyrows})==27
assert {r['detail_scale'] for r in bodyrows}=={0.09}
# Verify R008 introduces no edits to actor semantic tables except AIRA; BODY03 is AIRA only.
for actor in ('ERNA','LUNA','NOIR'):
 assert 'semanticFrameLandmarksCandidate' not in sem['entries'].get(actor,{})
assert all(r['actorID']=='AIRA' for r in bodyrows)
# Rejected history remains excluded so R005/R007 cannot override R008.
assert any('aira_r007' in x['path'] and x['status'].startswith('REJECTED') for x in rejected)
assert any('fit_candidate_r005' in x['path'] and x['status'].startswith('REJECTED') for x in rejected)
report={
 'schema':'aira_fit_overlay_r008_effective_values_audit_r001','status':'PASS_STRUCTURAL_SOURCE_SCOPE','humanApproval':False,
 'method':'Replay exact prepare_resources.py overlay traversal/merge on runtime_index.json; verify applied order, effective values, unique body keys, and original source SHA-256.',
 'runtimeIndexSHA256':digest(base_path),
 'r008SemanticOverlay':{'path':str(sem_path.relative_to(ROOT)),'sha256':digest(sem_path),'entryKeys':sorted(sem_entries),'effectiveAIRAFrameRows':len(A)},
 'r008Body03Overlay':{'path':str(body_path.relative_to(ROOT)),'sha256':digest(body_path),'entryKeys':sorted(body_entries),'effectiveBody03FrameRows':len(bodyrows)},
 'overlayOrderApplied':[x for x in applied if 'aira_r008' in x['path'] or 'fit_r008' in x['path']],
 'effectiveValues':{'DETAIL_EQ_BODY_03.detail_scale':[0.09],'EQ_FEET_01..03.height':[0.08],'EQ_RING_01..03.height':[0.03],'EQ_S_03.height':[0.09],'EQ_S_03.angle_degrees_by_state_and_frame':[{ 'state':r['sourceRowState'],'sourceFrameIndex':r['sourceFrameIndex'],'runtimeFrameIndex':r['frameIndex'],'angle_degrees':r['gear_overrides_candidate']['EQ_S_03']['angle_degrees']} for r in A]},
 'sourceSHA256Checks':source_results,'otherActorSemanticRowsModifiedByR008':[],'rejectedSupersededOverlays':[x for x in rejected if 'aira_r007' in x['path'] or 'fit_candidate_r005' in x['path']],
 'visualFit':'NOT_TESTED','nativeBuild':'PENDING_CORE_R008_SNAPSHOT','humanApproval':False}
out=ROOT/'docs/production/current/art/aira_fit_overlay_r008_effective_values_audit_r001.json';out.parent.mkdir(parents=True,exist_ok=True);tmp=out.with_suffix('.json.tmp');tmp.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');os.replace(tmp,out)
print(json.dumps({'status':report['status'],'report':str(out),'AIRArows':len(A),'BODY03rows':len(bodyrows),'sourceSHA':sum(x['pass'] for x in source_results),'actorsChangedByR008':[]},ensure_ascii=False,indent=2))
