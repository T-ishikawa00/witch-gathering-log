#!/usr/bin/env python3
"""Rebuild AIRA frame landmarks and BODY03 masks from individual 16px grid contacts."""
import hashlib,json
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]; ART=ROOT/'native/Art'; DEST=ART/'GeneratedCandidates/EquipmentDetails'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
# Each row: face, neck, chest, waist, working hand/grip, visible screen-right ankle, hammer surface.
# Values were reread per individual 3x 16px grid image; uncertainty remains +/-4-6 px.
measure={
'rest':[
 ([153,112],[158,136],[159,145],[147,173],[137,174],[171,215],[212,199]),
 ([150,113],[156,136],[158,145],[147,174],[132,175],[161,216],[211,200]),
 ([157,113],[160,136],[160,145],[147,174],[135,175],[160,215],[209,197]),
 ([167,130],[156,149],[160,156],[163,179],[141,156],[172,215],[218,190]),
 ([174,132],[160,150],[158,156],[165,180],[145,170],[166,215],[224,195]),
 ([147,126],[154,145],[157,154],[162,180],[151,171],[170,217],[224,195]),
 ([181,111],[174,134],[170,148],[166,173],[152,170],[200,216],[98,207]),
 ([167,111],[166,133],[169,145],[165,173],[139,171],[196,214],[85,207]),
 ([171,111],[170,134],[169,145],[166,173],[135,171],[197,214],[86,207]),
],
'attack':[
 ([171,112],[164,134],[161,143],[151,169],[167,175],[168,215],[212,199]),
 ([190,114],[178,141],[185,148],[159,177],[164,117],[203,214],[80,86]),
 ([174,115],[174,138],[175,146],[152,173],[179,79],[205,214],[78,80]),
 ([195,125],[180,149],[181,155],[167,180],[155,117],[225,214],[119,70]),
 # Attack04: cross-check values from root's enlarged source-grid measurement.
 ([145,116],[145,141],[122,151],[159,177],[173,174],[163,216],[227,207]),
 ([147,127],[146,143],[123,151],[164,180],[173,176],[163,216],[227,207]),
 ([131,124],[145,145],[144,152],[148,174],[151,163],[224,215],[211,196]),
 ([175,112],[171,137],[169,145],[166,171],[185,174],[164,215],[206,200]),
 ([172,112],[173,139],[169,145],[166,171],[185,174],[164,215],[205,200]),
],
'walk':[
 ([126,112],[126,136],[127,145],[128,171],[88,173],[128,220],[193,208]),
 ([130,116],[129,137],[128,145],[128,171],[89,174],[132,220],[193,208]),
 ([134,117],[133,138],[128,145],[128,171],[84,174],[153,213],[190,208]),
 ([138,114],[136,137],[128,145],[128,171],[87,177],[139,219],[193,207]),
 ([139,115],[137,138],[128,145],[128,171],[95,177],[140,216],[193,208]),
 ([147,114],[144,137],[128,145],[128,171],[102,172],[155,214],[202,203]),
 ([135,114],[133,137],[128,145],[128,171],[87,177],[147,212],[193,208]),
 ([137,112],[136,136],[128,145],[128,171],[90,170],[145,213],[193,208]),
 ([141,113],[139,137],[128,145],[128,171],[94,168],[149,215],[193,208]),
]}
stateIndex={'rest':[(i,'idle' if i<3 else 'hit' if i<6 else 'resolve',i%3) for i in range(9)],'attack':[(i,'anticipate' if i<3 else 'execute' if i<6 else 'recover',i%3) for i in range(9)],'walk':[(i,'walk',i) for i in range(9)]}
rows=[]; body03=[]
for group,values in measure.items():
 folder={'rest':'party_rest_r001','attack':'party_attack_r001','walk':'party_walk_r001'}[group]
 prefix=group
 for i,(face,neck,chest,waist,hand,ankle,hammer) in enumerate(values):
  fn=f'AIRA__{prefix}_{i:02d}.png' if group!='walk' else f'AIRA__walk_{i}.png'
  src=ROOT/'native/GeneratedArt'/folder/fn
  w,h=Image.open(src).size
  state,fi=next((s,ix) for ix,s,fi in stateIndex[group] if ix==i)
  face_r=[22,24] if group!='walk' else [17,19]
  # A small per-pose arm mask only where the forearm crosses the neck/chest zone.
  arm=None
  if group=='rest' and i>=6: arm={'shape':'ellipse','center_px':[196,111],'radius_px':[18,22],'reason':'raised gauntlet crosses temple/neck edge'}
  elif group=='rest' and 3<=i<=5: arm={'shape':'ellipse','center_px':[152,153],'radius_px':[19,11],'reason':'folded forearm overlaps chest/neck edge'}
  elif group=='attack' and i==1: arm={'shape':'ellipse','center_px':[156,132],'radius_px':[25,12],'reason':'raised gauntlet crosses neck/upper chest'}
  elif group=='attack' and i==2: arm={'shape':'ellipse','center_px':[181,109],'radius_px':[17,28],'reason':'vertical gauntlet crosses face/neck'}
  elif group=='attack' and i==3: arm={'shape':'ellipse','center_px':[157,123],'radius_px':[24,24],'reason':'crossed arms overlap face/neck edge'}
  elif group=='attack' and i in (4,5): arm={'shape':'ellipse','center_px':[151,150] if i==4 else [151,151],'radius_px':[25,12],'reason':'forward forearm occludes upper chest'}
  elif group=='attack' and i==6: arm={'shape':'ellipse','center_px':[149,145],'radius_px':[21,14],'reason':'lowered glove passes in front of collar'}
  elif group=='attack' and i in (7,8): arm={'shape':'ellipse','center_px':[148,145],'radius_px':[17,11],'reason':'forearms meet across upper chest'}
  landmarks={'face':face,'neck':neck,'chest':chest,'waist':waist,'workingHand':hand,'visibleRightAnkle':ankle,'hammerHead':hammer}
  masks=[{'shape':'ellipse','center_px':face,'radius_px':face_r,'name':'face_foreground_candidate'}]
  if arm:masks.append({'shape':'ellipse','center_px':arm['center_px'],'radius_px':arm['radius_px'],'name':'arm_foreground_candidate','reason':arm['reason']})
  row={'actorID':'AIRA','bodyAssetID':{'rest':f'GeneratedArt/PartyRest/{fn}','attack':f'GeneratedArt/PartyAttack/{fn}','walk':f'GeneratedArt/PartyWalk/{fn}'}[group],'frameIndex':fi,'canvas_px':[w,h],'landmarks_px_top_left':landmarks,'foreground_candidate':masks,'source_path':str(src.relative_to(ROOT)),'sourceSHA256':sha(src),'measurementStatus':'INDIVIDUAL_SOURCE_GRID_MEASURED_CANDIDATE','estimatedUncertaintyPx':6 if group!='walk' else 5,'fitVerifiedInRuntime':False,'sourceRowState':state,'sourceFrameIndex':i,'measurementNotes':'Read against individual 3x nearest-neighbor source image with 16px grid. Candidate point is visible physical contact/center, not proof of runtime fit; original pixels unchanged.'}
  rows.append(row)
  body03.append({'actorID':'AIRA','bodyAssetID':row['bodyAssetID'],'frameIndex':fi,'canvas_px':[w,h],'anchor_px_top_left':neck,'detail_scale':0.15,'angle_degrees':0,'foreground_occlusion_px':masks,'source_path':row['source_path'],'sourceSHA256':row['sourceSHA256'],'measurementStatus':'INDIVIDUAL_SOURCE_GRID_MEASURED_CANDIDATE','estimatedUncertaintyPx':6 if group!='walk' else 5,'fitVerifiedInRuntime':False,'sourceRowState':state,'sourceFrameIndex':i,'notes':'Neckline anchor and face/forearm foreground regions measured from individual grid; runtime fit still requires held-frame review.'})
assert len(rows)==27 and len(body03)==27
semantic={'schema':'equipment_semantic_frame_landmarks_r005','status':'UNAPPROVED_INDIVIDUAL_GRID_MEASURED_CANDIDATE','humanApproval':False,'key':['actorID','bodyAssetID','frameIndex','canvas_px'],'coordinate_origin':'top_left_canvas_pixels','measurementMethod':'All 27 original AIRA frames inspected individually at 3x nearest-neighbor with 16px source grid; screenshot-assisted error review R016. Values are candidates and require runtime fit recheck. Root cross-check supplied attack04 neck/chest/hand/ankle/hammer points.','sourceEvidence':['docs/production/current/art/aira_landmark_contacts_r002/individual/','docs/production/current/native/attachment_audit_r016_aira_semantic_pinned/'],'rows':rows}
body={'schema':'aira_body03_frame_registration_r005','status':'UNAPPROVED_INDIVIDUAL_GRID_MEASURED_CANDIDATE','humanApproval':False,'key':['actorID','bodyAssetID','frameIndex','canvas_px'],'coordinate_origin':'top_left_canvas_pixels','mask_method':'Full body texture copy above fur insert clipped to face/arm ellipses; ellipses are candidate source-pixel regions, not acceptance.','rows':body03}
for r in rows: assert sha(ROOT/r['source_path'])==r['sourceSHA256']
(DEST/'aira_equipment_landmarks_r005.json').write_text(json.dumps(semantic,ensure_ascii=False,indent=2)+'\n')
(DEST/'aira_body03_frame_registration_r005.json').write_text(json.dumps(body,ensure_ascii=False,indent=2)+'\n')
overlay={'status':'CANDIDATE_PREVIEW_ONLY','scope':'AIRA 27 individually grid-measured semantic attachment landmarks and BODY03 face/arm foreground masks; replaces R004 candidate tables only. No source art changed; all rows await synchronized native fit review.','humanApproval':False,'entries':{'AIRA':{'semanticFrameLandmarksCandidate':semantic},'DETAIL_EQ_BODY_03':{'frameRegistrationCandidate':body}}}
(ART/'runtime_overlay_zzzzzzzzzzzzzzzzzzzzzz_equipment_landmarks_aira_r005.json').write_text(json.dumps(overlay,ensure_ascii=False,indent=2)+'\n')
print('semantic/body03 rows',len(rows),len(body03),'files written')
