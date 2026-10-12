#!/usr/bin/env python3
"""Build additive, unapproved semantic landmark candidates for AIRA and NOIR.
No source artwork is modified; all locations are source-canvas measurements/candidates.
"""
import copy, hashlib, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'native/Art'

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
# Pixel points are visually estimated from the matching source coordinate contacts (see evidence refs).
# AIRA order: chest, waist, working glove/hammer grip, screen-right ankle, hammer head.
points={
 'rest': [
  (0,(145,145),(145,176),(174,184),(160,229),(214,207)),
  (1,(145,145),(145,176),(173,184),(160,229),(214,207)),
  (2,(145,145),(145,176),(174,184),(162,229),(214,207)),
  (3,(145,157),(145,189),(164,167),(166,237),(220,199)),
  (4,(146,158),(146,190),(163,169),(165,237),(220,199)),
  (5,(145,157),(145,189),(164,168),(166,237),(220,199)),
  (6,(158,150),(158,179),(173,124),(163,230),(105,211)),
  (7,(158,150),(158,179),(174,124),(163,230),(105,211)),
  (8,(158,150),(158,179),(174,124),(163,230),(105,211)),
 ],
 'attack': [
  (0,(145,145),(145,176),(174,184),(161,229),(214,207)),
  (1,(148,147),(148,179),(143,111),(164,231),(112,95)),
  (2,(151,149),(150,180),(170,119),(165,231),(137,70)),
  (3,(157,151),(157,181),(139,111),(164,232),(125,72)),
  (4,(167,153),(158,183),(192,165),(165,235),(225,184)),
  (5,(166,154),(158,183),(193,169),(167,235),(224,190)),
  (6,(147,149),(147,183),(166,171),(166,236),(206,219)),
  (7,(149,146),(148,178),(168,179),(162,228),(211,207)),
  (8,(149,146),(148,178),(168,179),(162,228),(211,207)),
 ],
 'walk': [
  (0,(127,145),(128,177),(158,181),(145,220),(201,211)),
  (1,(128,145),(128,177),(158,181),(146,220),(202,211)),
  (2,(128,145),(128,177),(158,181),(145,221),(202,211)),
  (3,(128,145),(128,177),(158,181),(145,221),(202,211)),
  (4,(128,145),(128,177),(158,181),(145,221),(202,211)),
  (5,(128,145),(128,177),(158,181),(145,221),(202,211)),
  (6,(128,145),(128,177),(158,181),(145,221),(202,211)),
  (7,(128,145),(128,177),(158,181),(145,221),(202,211)),
  (8,(128,145),(128,177),(158,181),(145,221),(202,211)),
 ]
}
state_map={'rest':[(i,'idle' if i<3 else 'hit' if i<6 else 'resolve',i%3) for i in range(9)],
           'attack':[(i,'anticipate' if i<3 else 'execute' if i<6 else 'recover',i%3) for i in range(9)],
           'walk':[(i,'walk',i) for i in range(9)]}
rows=[]
for st, dataset in points.items():
 directory={'rest':'party_rest_r001','attack':'party_attack_r001','walk':'party_walk_r001'}[st]
 prefix={'rest':'rest','attack':'attack','walk':'walk'}[st]
 for source_index,chest,waist,hand,ankle,hammer in dataset:
  filename=f'AIRA__{prefix}_{source_index:02d}.png' if st!='walk' else f'AIRA__walk_{source_index}.png'
  src=ROOT/'native/GeneratedArt'/directory/filename
  from PIL import Image
  im=Image.open(src); w,h=im.size
  runtime_state,frame_idx=next((s,fi) for idx,s,fi in state_map[st] if idx==source_index)
  rows.append({'actorID':'AIRA','bodyAssetID':{'rest':f'GeneratedArt/PartyRest/{filename}','attack':f'GeneratedArt/PartyAttack/{filename}','walk':f'GeneratedArt/PartyWalk/{filename}'}[st],
    'frameIndex':frame_idx,'canvas_px':[w,h],
    'landmarks_px_top_left':{'chest':list(chest),'waist':list(waist),'workingHand':list(hand),'visibleRightAnkle':list(ankle),'hammerHead':list(hammer)},
    'source_path':str(src.relative_to(ROOT)),'sourceSHA256':sha(src),'measurementStatus':'VISUALLY_MEASURED_CANDIDATE','estimatedUncertaintyPx':8 if st=='walk' else 6,'fitVerifiedInRuntime':False,
    'sourceRowState':runtime_state,'sourceFrameIndex':source_index,'measurementNotes':'Manual source-grid estimate from AIRA source contact sheets; functional landmark only, not proof of runtime fit. Hammer detail follows hammer-head center; hand detail follows visible working glove/grip. Recheck against held-frame geometry before any adoption.'})

aira={'schema':'equipment_semantic_frame_landmarks_r004','status':'UNAPPROVED_MEASURED_CANDIDATE','humanApproval':False,'key':['actorID','bodyAssetID','frameIndex','canvas_px'],'coordinate_origin':'top_left_canvas_pixels','measurementMethod':'27 authored AIRA source frames visually measured against 32px labeled source grids; locations are candidate source-canvas points with stated uncertainty. Original art unchanged.','sourceEvidence':['docs/production/current/art/aira_landmark_contacts_r001/REST_SOURCE_GRID.png','docs/production/current/art/aira_landmark_contacts_r001/ATTACK_SOURCE_GRID.png','docs/production/current/art/aira_landmark_contacts_r001/WALK_SOURCE_GRID.png'],'rows':rows}
# Verify unique exact body tuples and PNG provenance.
assert len(rows)==27 and len({(r['bodyAssetID'],r['frameIndex']) for r in rows})==27
for r in rows: assert sha(ROOT/r['source_path'])==r['sourceSHA256']

# Clone NOIR candidate semantic rows with explicit, accessory-only design offset/size and AMU-only paw masks.
r3=json.loads((ART/'runtime_overlay_zzzzzzzzzzzzzzzzzz_equipment_frame_landmarks_candidate_r003.json').read_text())
noir=copy.deepcopy(r3['entries']['NOIR']['semanticFrameLandmarksCandidate'])
for r in noir['rows']:
 r['gear_overrides_candidate']={'EQ_AMU_*':{'offset_px':[12,4],'height':0.10,'interpretation':'Small side charm offset from baked-in blue pendant; preserve the original blue gem and avoid visual blending.'}}
 if r['bodyAssetID'].endswith('NOIR__attack_04.png'):
  r['foreground_candidate_by_gear']={'EQ_AMU_*':[{'shape':'ellipse','center_px':[165,225],'radius_px':[26,12],'interpretation':'AMU-only source-body forepaw occlusion candidate; source canvas 320x256.'}]}
 if r['bodyAssetID'].endswith('NOIR__attack_05.png'):
  r['foreground_candidate_by_gear']={'EQ_AMU_*':[{'shape':'ellipse','center_px':[165,229],'radius_px':[25,11],'interpretation':'AMU-only source-body forepaw occlusion candidate; source canvas 320x256.'}]}
noir['schema']='equipment_semantic_frame_landmarks_noir_r004'
noir['status']='UNAPPROVED_VISUAL_MEASUREMENT_CANDIDATE'
noir['designCandidate']={'amulet':'offset +12,+4 source px from baked blue pendant; height 0.10 normalized scene-height vs current 0.16','occlusion':'AMU-only masks on attack04/05; do not apply to external catalyst effects'}

overlay={'status':'CANDIDATE_PREVIEW_ONLY','scope':'AIRA exact-frame semantic landmarks (27 body frames) and NOIR AMU accessory offset/scale plus two AMU-only paw occlusion candidates. No art pixels changed; fit/adoption not approved.','humanApproval':False,'sourceEvidence':{'AIRA':'native/Art/GeneratedCandidates/EquipmentDetails/aira_equipment_landmarks_r004.json','NOIR':'native/Art/GeneratedCandidates/EquipmentDetails/noir_frame_landmarks_r003.json'},'entries':{'AIRA':{'semanticFrameLandmarksCandidate':aira},'NOIR':{'semanticFrameLandmarksCandidate':noir}}}
(ART/'GeneratedCandidates/EquipmentDetails/aira_equipment_landmarks_r004.json').write_text(json.dumps(aira,ensure_ascii=False,indent=2)+'\n')
(ART/'runtime_overlay_zzzzzzzzzzzzzzzzzzzzz_equipment_frame_landmarks_candidate_r004_aira_noir.json').write_text(json.dumps(overlay,ensure_ascii=False,indent=2)+'\n')
print('AIRA rows',len(rows),'NOIR rows',len(noir['rows']))
