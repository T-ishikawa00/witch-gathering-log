#!/usr/bin/env python3
"""Pack selected R02B/R03 movement cycles. All outputs remain unapproved candidates."""
from pathlib import Path
import hashlib,json,shutil
from PIL import Image,ImageDraw
import numpy as np
from scipy import ndimage
ROOT=Path(__file__).resolve().parents[2];ART=ROOT/'native/Art'
GEN=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65')
ITEMS=[
 {'id':'ACT_E_R03_01','atlas':GEN/'exec-4e398a26-2e34-44c3-8278-c60655186276.png','source':'ActorStills/ACT_E_R03_01/ACT_E_R03_01__still__r001.png','base':'runtime_overlay_act_e_r03_01_pose_candidate_r001.json','rev':'ground_scuttle_cycle_r001','overlay':'runtime_overlay_act_e_r03_01_pose_candidate_r002_scuttle_cycle.json','canvas':[512,512],'anchor':[256,490],'align':'floor','semantic':'armored_crab_sideways_tripod_scuttle','fps':10,'limit':'Candidate gait only; foot contact timing and native game presentation pending review.'},
 {'id':'ACT_E_R03_02','atlas':GEN/'exec-c4e73834-dfcd-45f4-92e3-ec84144d8743.png','source':'ActorStills/ACT_E_R03_02/ACT_E_R03_02__still__r001.png','base':'runtime_overlay_act_e_r03_02_pose_candidate_r001.json','rev':'hover_wingbeat_cycle_r001','overlay':'runtime_overlay_act_e_r03_02_pose_candidate_r002_hover_cycle.json','canvas':[512,512],'anchor':[256,300],'align':'center','semantic':'bat_in_place_hover_with_attached_wingbeat_not_ground_walk','fps':10,'limit':'Wing beat is pose-only; phase cadence, looping and visually consistent crystal horn details need native screen review.'},
 {'id':'ACT_E_R03_03','atlas':GEN/'exec-f82228f6-457c-4f37-8309-a8e2f72925ff.png','source':'ActorStills/ACT_E_R03_03/ACT_E_R03_03__still__r001.png','base':'runtime_overlay_act_e_r03_03_pose_candidate_r001.json','rev':'heavy_stone_gait_cycle_r001','overlay':'runtime_overlay_act_e_r03_03_pose_candidate_r002_walk_cycle.json','canvas':[512,512],'anchor':[256,490],'align':'floor','semantic':'heavy_stone_golem_alternating_leg_plant_and_weight_shift','fps':8,'limit':'Heavy limb pose candidate; foot plant, contact continuity and weight timing pending native screen review.'},
 {'id':'ACT_E_R03_04','atlas':GEN/'exec-bb67c3b2-ce5e-4e66-acc9-2ae1c012eca4.png','source':'ActorStills/ACT_E_R03_04/ACT_E_R03_04__still__r001.png','base':'runtime_overlay_act_e_r03_04_pose_candidate_r001.json','rev':'stalking_walk_cycle_r001','overlay':'runtime_overlay_act_e_r03_04_pose_candidate_r002_walk_cycle.json','canvas':[512,512],'anchor':[256,490],'align':'floor','semantic':'low_quadruped_stalk_with_alternating_ground_contacts','fps':10,'limit':'Candidate gait only; cadence and tail attachment/registration require native screen review.'},
]
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1<<20),b''):h.update(b)
 return h.hexdigest()
def splits(n):return [round(i*n/3) for i in range(4)]
def bbox(path):
 a=np.asarray(Image.open(path).convert('RGBA').getchannel('A'));y,x=np.where(a>16)
 if not len(x):return None
 return [int(x.min()),int(y.min()),int(x.max()),int(y.max())]
def boundsize(b):return [b[2]-b[0]+1,b[3]-b[1]+1]
allrec={'schema':'r02b_r03_enemy_motion_candidates_r001','approval':'UNAPPROVED_CANDIDATES','natural_motion_complete':False,'items':[]}
for it in ITEMS:
 aid=it['id'];out=ART/'GeneratedCandidates'/aid/it['rev'];fd=out/'frames';fd.mkdir(parents=True,exist_ok=True)
 atlas=Image.open(it['atlas']).convert('RGBA');src=ART/it['source'];source_sha=sha(src)
 if atlas.width%3 or atlas.height%3:raise ValueError(f'bad grid {aid}: {atlas.size}')
 xs=splits(atlas.width);ys=splits(atlas.height)
 shutil.copy2(it['atlas'],out/'imagegen_atlas_source.png');shutil.copy2(src,out/'identity_reference_still.png')
 frames=[];paths=[];records=[]
 for n in range(9):
  row,col=divmod(n,3);box=(xs[col],ys[row],xs[col+1],ys[row+1]);cell=atlas.crop(box)
  ar=np.asarray(cell.getchannel('A'));labels,num=ndimage.label(ar>16,structure=np.ones((3,3),dtype=np.uint8));counts=np.bincount(labels.ravel());counts[0]=0;lab=int(counts.argmax());keep=ndimage.binary_dilation(labels==lab,iterations=2)
  removed=int(((ar>0)&~keep).sum());a=ar.copy();a[~keep]=0;cell.putalpha(Image.fromarray(a.astype('uint8')))
  a=np.asarray(cell.getchannel('A'));yy,xx=np.where(a>16)
  if not len(xx):raise ValueError(f'empty pose {aid}:{n}')
  cw,ch=it['canvas'];dx=round(cw/2-(xx.min()+xx.max())/2)
  dy=it['anchor'][1]-int(yy.max()) if it['align']=='floor' else round(ch/2-(yy.min()+yy.max())/2)
  packed=Image.new('RGBA',(cw,ch),(0,0,0,0));packed.alpha_composite(cell,(dx,dy));a=np.asarray(packed.getchannel('A'));py,px=np.where(a>16);bb=[int(px.min()),int(py.min()),int(px.max()),int(py.max())]
  if bb[0]<0 or bb[1]<0 or bb[2]>=cw or bb[3]>=ch:raise ValueError(f'overflow {aid}:{n} {bb}')
  name=f'walk_{n:03}.png';dest=fd/name;packed.save(dest);frames.append(packed);rel=f'GeneratedCandidates/{aid}/{it["rev"]}/frames/{name}';paths.append(rel)
  records.append({'frame':name,'source_cell_px':[box[0],box[1],box[2]-box[0],box[3]-box[1]],'translation_px':[dx,dy],'alpha16_bounds_px':bb,'alpha16_size_px':boundsize(bb),'alpha16_pixels':int((a>16).sum()),'disconnected_alpha_pixels_zeroed':removed,'source_alpha16_component_count':int(num),'sha256':sha(dest)})
 qa=Image.new('RGB',(1536,1632),(27,34,43));draw=ImageDraw.Draw(qa)
 for n,im in enumerate(frames):
  r,c=divmod(n,3);bg=Image.new('RGBA',(512,512),(27,34,43,255));bg.alpha_composite(im);qa.paste(bg.convert('RGB'),(c*512,r*544+32));draw.text((c*512+8,r*544+8),f'{aid} / {n:03}',fill=(235,235,235))
 qap=out/'qa_contact_sheet.jpg';qa.save(qap,quality=94)
 base=json.loads((ART/it['base']).read_text())['entries'][aid];entry=json.loads(json.dumps(base));entry.setdefault('sequenceFrames',{})['walk']=paths
 idle_paths=base.get('clips',{}).get('idle',{}).get('frames',[]);idle_bounds=[bbox(ART/p) for p in idle_paths if (ART/p).is_file()];idle_sizes=[boundsize(b) for b in idle_bounds if b]
 entry.setdefault('clips',{})['walk']={'frames':paths,'frame_count':9,'fps':it['fps'],'duration_seconds':9/it['fps'],'loop':True,'status':'UNAPPROVED_NINE_FRAME_MOTION_CANDIDATE_NOT_NATURAL_MOTION_COMPLETE','canvas_px':it['canvas'],'anchor':it['anchor'],'anchor_status':'VISUAL_ESTIMATE_UNAPPROVED','movement_semantics':it['semantic'],'display_scale':1.0,'quality_limit':it['limit']}
 entry['canvas_px']=it['canvas'];entry['anchor']=it['anchor'];entry['anchor_status']='VISUAL_ESTIMATE_UNAPPROVED';entry['states_present']=sorted(set(entry.get('states_present',[])+['walk']));entry['status']='UNAPPROVED_PARTIAL_MOTION_CANDIDATE';entry['complete_animation']=False
 ov={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY','complete_animation':False,'candidate_manifest':f'GeneratedCandidates/{aid}/{it["rev"]}/manifest.json','entries':{aid:entry}};(ART/it['overlay']).write_text(json.dumps(ov,ensure_ascii=False,indent=2)+'\n')
 m={'asset_id':aid,'revision':it['rev'],'movement_semantics':it['semantic'],'quality_limit':it['limit'],'source_still_path':it['source'],'source_still_sha256':source_sha,'atlas_path':f'GeneratedCandidates/{aid}/{it["rev"]}/imagegen_atlas_source.png','atlas_sha256':sha(out/'imagegen_atlas_source.png'),'atlas_px':list(atlas.size),'grid_x':xs,'grid_y':ys,'frame_canvas_px':it['canvas'],'anchor_candidate_px':it['anchor'],'registration':'alpha16 x-centering and either foot-baseline-to-anchor or visual-center alignment. Translation only, no resize/recolor. Per-frame and idle alpha16 occupancy are measured; display_scale remains constant at 1.0 by default pending visual runtime review. Detached generated alpha outside 2px fringe of largest alpha16 component zeroed.','idle_alpha16_bounds_px':idle_bounds,'idle_alpha16_size_px':idle_sizes,'candidate_walk_alpha16_bounds_px':[r['alpha16_bounds_px'] for r in records],'candidate_walk_alpha16_size_px':[r['alpha16_size_px'] for r in records],'clip_display_scale':1.0,'fps_candidate':it['fps'],'frames':records,'qa_contact_sheet':f'GeneratedCandidates/{aid}/{it["rev"]}/qa_contact_sheet.jpg','runtime_overlay':it['overlay'],'visual_status':'UNAPPROVED_CANDIDATE_PENDING_ROOT_NATIVE_SCREEN_REVIEW','approval_status':'HUMAN_ADOPTION_PENDING','natural_motion_complete':False}
 (out/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n');allrec['items'].append(m)
 if sha(src)!=source_sha:raise RuntimeError('source changed '+aid)
allrec['status']='UNAPPROVED_PARTIAL_MOTION_CANDIDATES_PENDING_NATIVE_SCREEN_REVIEW'
(ROOT/'docs/production/current/art/R02B_R03_enemy_motion_candidates_r001.json').write_text(json.dumps(allrec,ensure_ascii=False,indent=2)+'\n')
print(json.dumps([{'id':m['asset_id'],'qa':m['qa_contact_sheet'],'overlay':m['runtime_overlay'],'idle_size':m['idle_alpha16_size_px'],'walk_size':m['candidate_walk_alpha16_size_px']} for m in allrec['items']],ensure_ascii=False,indent=2))
