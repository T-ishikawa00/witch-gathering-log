#!/usr/bin/env python3
"""Package four additive, unapproved movement candidates from 3x3 atlases."""
from pathlib import Path
import hashlib, json, shutil
from PIL import Image, ImageDraw
import numpy as np
from scipy import ndimage

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'native/Art'
GEN=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65')
ITEMS=[
 {'id':'ACT_B_R01_B','name':'ancient_tree_rooted_sway','atlas':GEN/'exec-0fff660f-6b3d-407e-baef-4411fdf1fa11.png','source':'ActorStills/ACT_B_R01_B/ACT_B_R01_B__still__B_R01_B_ANCIENT_TREE_base_v1.png','base':'runtime_overlay_act_b_r01_b_pose_candidate_r002.json','rev':'rooted_sway_cycle_r001','overlay':'runtime_overlay_act_b_r01_b_pose_candidate_r003_rooted_sway_cycle.json','canvas':[512,512],'anchor':[256,490],'align':'floor','semantic':'rooted_plant_canopy_and_branch_sway_not_foot_walk','fps':8,'motion_limit':'Subtle changes; candidate only. Not a traveling walk or natural-motion completion.'},
 {'id':'ACT_E_R02_02','name':'swamp_lizard_ground_gait','atlas':GEN/'exec-808879a8-c827-4314-8054-89af6087abe4.png','source':'ActorStills/ACT_E_R02_02/ACT_E_R02_02__still__r001.png','base':'runtime_overlay_act_e_r02_02_pose_candidate_r001.json','rev':'ground_walk_cycle_r001','overlay':'runtime_overlay_act_e_r02_02_pose_candidate_r002_walk_cycle.json','canvas':[512,512],'anchor':[256,490],'align':'floor','semantic':'low_quadruped_alternating_contact_compression_passing_and_push_off','fps':10,'motion_limit':'Pose-only generated gait candidate; foot contact quality and natural cadence require native screen review.'},
 {'id':'ACT_E_R02_04','name':'moon_moth_hover_wingbeat','atlas':GEN/'exec-aabd6713-a6f8-475a-991d-8073e4d10e2e.png','source':'ActorStills/ACT_E_R02_04/ACT_E_R02_04__still__r001.png','base':'runtime_overlay_act_e_r02_04_pose_candidate_r002.json','rev':'hover_wingbeat_cycle_r001','overlay':'runtime_overlay_act_e_r02_04_pose_candidate_r003_hover_cycle.json','canvas':[512,512],'anchor':[256,300],'align':'center','semantic':'in_place_hover_with_repeated_wingbeat_not_ground_walk','fps':10,'motion_limit':'Wing shapes repeat several phases; not nine fully unique phases, candidate only.'},
 {'id':'ACT_B_R02_A','name':'mushroom_boss_heavy_shuffle','atlas':GEN/'exec-4c1cf96d-20f9-4ef5-af13-3408110e11d5.png','source':'ActorStills/ACT_B_R02_A/ACT_B_R02_A__still__r001.png','base':'runtime_overlay_act_b_r02_a_pose_candidate_r001.json','rev':'heavy_shuffle_cycle_r001','overlay':'runtime_overlay_act_b_r02_a_pose_candidate_r002_walk_cycle.json','canvas':[512,512],'anchor':[256,490],'align':'floor','semantic':'heavy_root_leg_shuffle_with_body_weight_shift_not_hop','fps':8,'motion_limit':'Only some leg phases are distinct; foot contact continuity and natural cadence require native screen review.'},
]
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1<<20),b''):h.update(b)
 return h.hexdigest()
def splits(n):return [round(i*n/3) for i in range(4)]
allrec={'schema':'r01b_r02_enemy_motion_candidates_r001','approval':'UNAPPROVED_CANDIDATES','natural_motion_complete':False,'items':[]}
for it in ITEMS:
 aid=it['id']; out=ART/'GeneratedCandidates'/aid/it['rev']; fd=out/'frames';fd.mkdir(parents=True,exist_ok=True)
 atlas=Image.open(it['atlas']).convert('RGBA'); src=ART/it['source']; original_sha=sha(src)
 if atlas.width%3 or atlas.height%3: raise ValueError(f'non-divisible 3x3 atlas {aid}: {atlas.size}')
 xs=splits(atlas.width); ys=splits(atlas.height)
 shutil.copy2(it['atlas'],out/'imagegen_atlas_source.png'); shutil.copy2(src,out/'identity_reference_still.png')
 recs=[]; paths=[]; frames=[]
 for n in range(9):
  row,col=divmod(n,3); box=(xs[col],ys[row],xs[col+1],ys[row+1]); cell=atlas.crop(box)
  ar=np.asarray(cell.getchannel('A')); labels,num=ndimage.label(ar>16,structure=np.ones((3,3),dtype=np.uint8))
  counts=np.bincount(labels.ravel()); counts[0]=0; main=int(counts.argmax()); keep=ndimage.binary_dilation(labels==main,iterations=2)
  removed=int(((ar>0)&~keep).sum()); aa=ar.copy();aa[~keep]=0;cell.putalpha(Image.fromarray(aa.astype('uint8')))
  ar=np.asarray(cell.getchannel('A')); yy,xx=np.where(ar>16)
  if not len(xx):raise ValueError(f'empty generated frame {aid}/{n}')
  cw,ch=it['canvas'];dx=round(cw/2-(xx.min()+xx.max())/2)
  dy=(it['anchor'][1]-int(yy.max())) if it['align']=='floor' else round(ch/2-(yy.min()+yy.max())/2)
  packed=Image.new('RGBA',(cw,ch),(0,0,0,0));packed.alpha_composite(cell,(dx,dy))
  a=np.asarray(packed.getchannel('A'));py,px=np.where(a>16);bounds=[int(px.min()),int(py.min()),int(px.max()),int(py.max())]
  if bounds[0]<0 or bounds[1]<0 or bounds[2]>=cw or bounds[3]>=ch:raise ValueError(f'frame overflow {aid}/{n}: {bounds}')
  name=f'walk_{n:03}.png'; dest=fd/name;packed.save(dest);frames.append(packed)
  rel=f'GeneratedCandidates/{aid}/{it["rev"]}/frames/{name}';paths.append(rel)
  recs.append({'frame':name,'source_cell_px':[box[0],box[1],box[2]-box[0],box[3]-box[1]],'translation_px':[dx,dy],'alpha16_bounds_px':bounds,'alpha16_pixels':int((a>16).sum()),'disconnected_alpha_pixels_zeroed':removed,'source_alpha16_component_count':int(num),'sha256':sha(dest)})
 qa=Image.new('RGB',(1536,1632),(27,34,43));draw=ImageDraw.Draw(qa)
 for n,im in enumerate(frames):
  r,c=divmod(n,3);bg=Image.new('RGBA',(512,512),(27,34,43,255));bg.alpha_composite(im)
  qa.paste(bg.convert('RGB'),(c*512,r*544+32));draw.text((c*512+8,r*544+8),f'{aid} / {n:03}',fill=(235,235,235))
 qa_path=out/'qa_contact_sheet.jpg';qa.save(qa_path,quality=94)
 base=json.loads((ART/it['base']).read_text())['entries'][aid];entry=json.loads(json.dumps(base))
 entry.setdefault('sequenceFrames',{})['walk']=paths
 entry.setdefault('clips',{})['walk']={'frames':paths,'frame_count':9,'fps':it['fps'],'duration_seconds':9/it['fps'],'loop':True,'status':'UNAPPROVED_NINE_FRAME_MOTION_CANDIDATE_NOT_NATURAL_MOTION_COMPLETE','canvas_px':it['canvas'],'anchor':it['anchor'],'anchor_status':'VISUAL_ESTIMATE_UNAPPROVED','movement_semantics':it['semantic'],'quality_limit':it['motion_limit']}
 entry['canvas_px']=it['canvas'];entry['anchor']=it['anchor'];entry['anchor_status']='VISUAL_ESTIMATE_UNAPPROVED';entry['states_present']=sorted(set(entry.get('states_present',[])+['walk']));entry['status']='UNAPPROVED_PARTIAL_MOTION_CANDIDATE';entry['complete_animation']=False
 ov={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY','complete_animation':False,'candidate_manifest':f'GeneratedCandidates/{aid}/{it["rev"]}/manifest.json','entries':{aid:entry}}
 (ART/it['overlay']).write_text(json.dumps(ov,ensure_ascii=False,indent=2)+'\n')
 m={'asset_id':aid,'revision':it['rev'],'movement_semantics':it['semantic'],'quality_limit':it['motion_limit'],'source_still_path':it['source'],'source_still_sha256':original_sha,'atlas_path':f'GeneratedCandidates/{aid}/{it["rev"]}/imagegen_atlas_source.png','atlas_sha256':sha(out/'imagegen_atlas_source.png'),'atlas_px':list(atlas.size),'grid_x':xs,'grid_y':ys,'frame_canvas_px':it['canvas'],'anchor_candidate_px':it['anchor'],'registration':'alpha16 centroid centered on x; grounded poses align alpha16 bottom to visual-estimate anchor; hover frames center to canvas. Translation only, no resize/recolor. Disconnected generated alpha outside a 2px fringe of the largest alpha16 component is zeroed.','fps_candidate':it['fps'],'frames':recs,'qa_contact_sheet':f'GeneratedCandidates/{aid}/{it["rev"]}/qa_contact_sheet.jpg','runtime_overlay':it['overlay'],'visual_status':'UNAPPROVED_CANDIDATE_PENDING_ROOT_NATIVE_SCREEN_REVIEW','approval_status':'HUMAN_ADOPTION_PENDING','natural_motion_complete':False}
 (out/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n');allrec['items'].append(m)
 if sha(src)!=original_sha:raise RuntimeError('source still changed: '+aid)
allrec['status']='UNAPPROVED_PARTIAL_MOTION_CANDIDATES_PENDING_NATIVE_SCREEN_REVIEW'
(ROOT/'docs/production/current/art/R01B_R02_enemy_motion_candidates_r001.json').write_text(json.dumps(allrec,ensure_ascii=False,indent=2)+'\n')
print(json.dumps([{'id':m['asset_id'],'qa':m['qa_contact_sheet'],'overlay':m['runtime_overlay'],'bounds':[f['alpha16_bounds_px'] for f in m['frames']]} for m in allrec['items']],ensure_ascii=False,indent=2))
