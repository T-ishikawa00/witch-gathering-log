#!/usr/bin/env python3
"""Package selected R03B/R04 locomotion candidates from generated 3x3 sheets."""
from pathlib import Path
import hashlib,json,shutil
from PIL import Image,ImageDraw
import numpy as np
from scipy import ndimage
ROOT=Path(__file__).resolve().parents[2];ART=ROOT/'native/Art'
GEN=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65')
ITEMS=[
 {'id':'ACT_B_R03_B','atlas':GEN/'exec-d7ebfa81-41e3-4464-ab39-d9944afd1b11.png','source':'ActorStills/ACT_B_R03_B/ACT_B_R03_B__still__r001.png','base':'runtime_overlay_act_b_r03_b_pose_candidate_r003.json','rev':'heavy_stone_gait_cycle_r002','overlay':'runtime_overlay_act_b_r03_b_pose_candidate_r005_walk_cycle.json','canvas':[512,512],'anchor':[256,490],'align':'floor','semantic':'heavy_stone_colossus_grounded_weight_transfer_and_alternating_steps','fps':8,'display_scale':0.9,'limit':'Pose-generated heavyweight walk candidate. Constant 0.75 display scale compensates for alpha16 height occupancy (idle median 279.5 px, walk median 375 px); native visual confirmation required.'},
 {'id':'ACT_E_R04_01','atlas':GEN/'exec-e8853ade-0b3d-4699-831c-a7b543c1a443.png','source':'ActorStills/ACT_E_R04_01/ACT_E_R04_01__still__r001.png','base':'runtime_overlay_act_e_r04_01_pose_candidate_r001.json','rev':'arctic_wolf_trot_cycle_r002','overlay':'runtime_overlay_act_e_r04_01_pose_candidate_r003_trot_cycle.json','canvas':[512,512],'anchor':[256,490],'align':'floor','semantic':'right_facing_arctic_wolf_diagonal_quadruped_trot','fps':10,'display_scale':1.0,'limit':'Candidate trot; exact footfalls, consistent coat anatomy and game-scale read require native screen review.'},
 {'id':'ACT_E_R04_02','atlas':GEN/'exec-4e3edfe8-03fe-4017-a3ac-7f9d039641f9.png','source':'ActorStills/ACT_E_R04_02/ACT_E_R04_02__still__r002.png','base':'runtime_overlay_act_e_r04_02_pose_candidate_r001.json','rev':'arctic_owl_hover_cycle_r002','overlay':'runtime_overlay_act_e_r04_02_pose_candidate_r003_hover_cycle.json','canvas':[512,512],'anchor':[256,300],'align':'center','semantic':'arctic_owl_in_place_hover_with_wingbeat_not_foot_walk','fps':10,'display_scale':1.0,'limit':'Wingbeat candidate; wing attachment/phase cadence and size consistency require native screen review.'},
 {'id':'ACT_E_R04_03','atlas':GEN/'exec-34bc26ae-ff3f-494e-9740-96356510effd.png','source':'ActorStills/ACT_E_R04_03/ACT_E_R04_03__still__r001.png','base':'runtime_overlay_act_e_r04_03_pose_candidate_r001.json','rev':'frost_shell_crawl_cycle_r002','overlay':'runtime_overlay_act_e_r04_03_pose_candidate_r003_crawl_cycle.json','canvas':[512,512],'anchor':[256,490],'align':'floor','semantic':'low_armored_creature_alternating_multi_leg_crawl','fps':8,'display_scale':1.0,'limit':'Leg placements are mostly subtle under shell; contact and loop quality need native screen review.'},
 {'id':'ACT_E_R04_04','atlas':GEN/'exec-5115d590-10c9-4c2b-86f7-371857943299.png','source':'ActorStills/ACT_E_R04_04/ACT_E_R04_04__still__r001.png','base':'runtime_overlay_act_e_r04_04_pose_candidate_r001.json','rev':'ice_sentinel_staff_walk_cycle_r002','overlay':'runtime_overlay_act_e_r04_04_pose_candidate_r003_walk_cycle.json','canvas':[512,512],'anchor':[256,490],'align':'floor','semantic':'upright_ice_sentinel_walk_with_staff_carried_in_hand','fps':8,'display_scale':1.0,'limit':'Staff remains present; biped steps are discrete candidate poses pending runtime contact/silhouette review.'},
 {'id':'ACT_B_R04_A','atlas':GEN/'exec-af8fa980-6882-42be-832f-113e5a7a95cb.png','source':'ActorStills/ACT_B_R04_A/ACT_B_R04_A__still__r001.png','base':'runtime_overlay_act_b_r04_a_pose_candidate_r001.json','rev':'mountain_goat_heavy_gait_cycle_r002','overlay':'runtime_overlay_act_b_r04_a_pose_candidate_r003_walk_cycle.json','canvas':[512,512],'anchor':[256,490],'align':'floor','semantic':'mountain_goat_heavy_quadruped_walk_with_horn_and_fleece_counter_motion','fps':8,'display_scale':1.0,'limit':'Heavy gait candidate; hoof contact and boss-scale read require native screen review.'},
]
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1<<20),b''):h.update(b)
 return h.hexdigest()
def splits(n):return [round(i*n/3) for i in range(4)]
def bbox(path):
 a=np.asarray(Image.open(path).convert('RGBA').getchannel('A'));y,x=np.where(a>16)
 return None if not len(x) else [int(x.min()),int(y.min()),int(x.max()),int(y.max())]
def size(b):return [b[2]-b[0]+1,b[3]-b[1]+1]
allrec={'schema':'r03b_r04_enemy_motion_candidates_r001','approval':'UNAPPROVED_CANDIDATES','natural_motion_complete':False,'items':[]}
for it in ITEMS:
 aid=it['id'];out=ART/'GeneratedCandidates'/aid/it['rev'];fd=out/'frames';fd.mkdir(parents=True,exist_ok=True);src=ART/it['source'];source_sha=sha(src)
 atlas=Image.open(it['atlas']).convert('RGBA')
 if atlas.width < 3 or atlas.height < 3:raise ValueError(f'invalid 3x3 sheet: {aid} {atlas.size}')
 xs=splits(atlas.width);ys=splits(atlas.height);shutil.copy2(it['atlas'],out/'imagegen_atlas_source.png');shutil.copy2(src,out/'identity_reference_still.png')
 frames=[];paths=[];records=[]
 for n in range(9):
  row,col=divmod(n,3);box=(xs[col],ys[row],xs[col+1],ys[row+1]);cell=atlas.crop(box)
  ar=np.asarray(cell.getchannel('A'));labels,num=ndimage.label(ar>16,structure=np.ones((3,3),dtype=np.uint8));counts=np.bincount(labels.ravel());counts[0]=0;component_sizes=sorted((int(x) for x in counts[1:]),reverse=True);removed=0
  yy,xx=np.where(ar>16)
  if not len(xx):raise ValueError(f'empty frame: {aid}/{n}')
  cw,ch=it['canvas'];dx=round(cw/2-(xx.min()+xx.max())/2);dy=it['anchor'][1]-int(yy.max()) if it['align']=='floor' else round(ch/2-(yy.min()+yy.max())/2)
  packed=Image.new('RGBA',(cw,ch),(0,0,0,0));packed.alpha_composite(cell,(dx,dy));a=np.asarray(packed.getchannel('A'));py,px=np.where(a>16);bb=[int(px.min()),int(py.min()),int(px.max()),int(py.max())]
  if bb[0]<0 or bb[1]<0 or bb[2]>=cw or bb[3]>=ch:raise ValueError(f'frame overflow {aid}/{n} {bb}')
  name=f'walk_{n:03}.png';dest=fd/name;packed.save(dest);frames.append(packed);rel=f'GeneratedCandidates/{aid}/{it["rev"]}/frames/{name}';paths.append(rel)
  records.append({'frame':name,'source_cell_px':[box[0],box[1],box[2]-box[0],box[3]-box[1]],'translation_px':[dx,dy],'alpha16_bounds_px':bb,'alpha16_size_px':size(bb),'alpha16_pixels':int((a>16).sum()),'source_alpha16_component_count':int(num),'largest_alpha16_component_pixels':component_sizes[0] if component_sizes else 0,'other_alpha16_component_pixels':component_sizes[1:],'alpha_preserved_from_source_cell':True,'sha256':sha(dest)})
 qa=Image.new('RGB',(1536,1632),(27,34,43));draw=ImageDraw.Draw(qa)
 for n,im in enumerate(frames):
  r,c=divmod(n,3);bg=Image.new('RGBA',(512,512),(27,34,43,255));bg.alpha_composite(im);qa.paste(bg.convert('RGB'),(c*512,r*544+32));draw.text((c*512+8,r*544+8),f'{aid} / {n:03}',fill=(235,235,235))
 qap=out/'qa_contact_sheet.jpg';qa.save(qap,quality=94)
 base=json.loads((ART/it['base']).read_text())['entries'][aid];entry=json.loads(json.dumps(base));entry.setdefault('sequenceFrames',{})['walk']=paths
 idle_paths=base.get('clips',{}).get('idle',{}).get('frames',[]);ib=[bbox(ART/p) for p in idle_paths if (ART/p).is_file()];ib=[b for b in ib if b]
 entry.setdefault('clips',{})['walk']={'frames':paths,'frame_count':9,'fps':it['fps'],'duration_seconds':9/it['fps'],'loop':True,'complete_animation':False,'status':'UNAPPROVED_NINE_FRAME_MOTION_CANDIDATE_NOT_NATURAL_MOTION_COMPLETE','canvas_px':it['canvas'],'anchor':it['anchor'],'anchor_status':'VISUAL_ESTIMATE_UNAPPROVED','movement_semantics':it['semantic'],'display_scale':it['display_scale'],'quality_limit':it['limit']}
 entry['canvas_px']=it['canvas'];entry['anchor']=it['anchor'];entry['anchor_status']='VISUAL_ESTIMATE_UNAPPROVED';entry['states_present']=sorted(set(entry.get('states_present',[])+['walk']));entry['status']='UNAPPROVED_PARTIAL_MOTION_CANDIDATE';entry['complete_animation']=False
 ov={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY','complete_animation':False,'candidate_manifest':f'GeneratedCandidates/{aid}/{it["rev"]}/manifest.json','entries':{aid:entry}};(ART/it['overlay']).write_text(json.dumps(ov,ensure_ascii=False,indent=2)+'\n')
 m={'asset_id':aid,'revision':it['rev'],'movement_semantics':it['semantic'],'quality_limit':it['limit'],'source_still_path':it['source'],'source_still_sha256':source_sha,'atlas_path':f'GeneratedCandidates/{aid}/{it["rev"]}/imagegen_atlas_source.png','atlas_sha256':sha(out/'imagegen_atlas_source.png'),'atlas_px':list(atlas.size),'grid_x':xs,'grid_y':ys,'frame_canvas_px':it['canvas'],'anchor_candidate_px':it['anchor'],'registration':'alpha16 x-centering and foot baseline to visual anchor or alpha16 bbox centering for hover. Translation only, no resize/recolor; frame RGBA preserved byte-for-byte from source cell, with no alpha cleanup. Constant clip display_scale from config. Alpha16 occupancy and connected-component sizes are measured only.','idle_alpha16_bounds_px':ib,'idle_alpha16_size_px':[size(b) for b in ib],'candidate_walk_alpha16_bounds_px':[r['alpha16_bounds_px'] for r in records],'candidate_walk_alpha16_size_px':[r['alpha16_size_px'] for r in records],'clip_display_scale':it['display_scale'],'fps_candidate':it['fps'],'frames':records,'qa_contact_sheet':f'GeneratedCandidates/{aid}/{it["rev"]}/qa_contact_sheet.jpg','runtime_overlay':it['overlay'],'visual_status':'UNAPPROVED_CANDIDATE_PENDING_ROOT_NATIVE_SCREEN_REVIEW','approval_status':'HUMAN_ADOPTION_PENDING','natural_motion_complete':False}
 (out/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n');allrec['items'].append(m)
 if sha(src)!=source_sha:raise RuntimeError('source changed '+aid)
allrec['status']='UNAPPROVED_PARTIAL_MOTION_CANDIDATES_PENDING_NATIVE_SCREEN_REVIEW'
(ROOT/'docs/production/current/art/R03B_R04_enemy_motion_candidates_r002.json').write_text(json.dumps(allrec,ensure_ascii=False,indent=2)+'\n')
print(json.dumps([{'id':m['asset_id'],'qa':m['qa_contact_sheet'],'overlay':m['runtime_overlay'],'idle_px':m['idle_alpha16_size_px'],'walk_px':m['candidate_walk_alpha16_size_px']} for m in allrec['items']],ensure_ascii=False,indent=2))
