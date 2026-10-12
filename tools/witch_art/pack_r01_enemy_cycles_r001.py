#!/usr/bin/env python3
"""Package four non-destructive R01 movement-cycle candidates from generated 3x3 atlases."""
from pathlib import Path
import hashlib,json,shutil
from PIL import Image,ImageDraw
import numpy as np
from scipy import ndimage
ROOT=Path(__file__).resolve().parents[2]; ART=ROOT/'native/Art'
ITEMS=[
 {'id':'ACT_E_R01_02','name':'spider_crawl','atlas':Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-d2b45fb5-19c5-4e7a-aa5c-fdefe5298cb1.png'),'rev':'walk_cycle_r001','overlay':'runtime_overlay_act_e_r01_02_walk_cycle_candidate_r001.json','base':'generated_runtime_overlay.json','source':'ActorStills/ACT_E_R01_02/ACT_E_R01_02__still__E_R01_02_base_v2.png','canvas':[512,341],'anchor':[256,330],'align':'floor','semantic':'low_spider_crawl_tripod_gait','fps':12},
 {'id':'ACT_E_R01_03','name':'leafblade_hover','atlas':Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-d05bf4f6-1b6d-4810-a8df-695486813911.png'),'rev':'flight_cycle_r002','overlay':'runtime_overlay_act_e_r01_03_pose_candidate_r003_flight_cycle.json','base':'runtime_overlay_act_e_r01_03_pose_candidate_r002.json','source':'ActorStills/ACT_E_R01_03/ACT_E_R01_03__still__E_R01_03_base_v1.png','canvas':[512,512],'anchor':[256,300],'align':'center','semantic':'in_place_hover_leaf_blade_wingbeat_not_foot_walk','fps':12,'rejected_prior':{'revision':'flight_cycle_r001','atlas':'/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-f314088e-8312-445f-9139-164d194bb50d.png','reason':'Only about three repeated wing phases across the 3x3 atlas; insufficient 9-frame cadence.'}},
 {'id':'ACT_E_R01_04','name':'resin_beetle_gait','atlas':Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-72818795-2c9d-4fa7-8388-9f6f59b42330.png'),'rev':'walk_cycle_r001','overlay':'runtime_overlay_act_e_r01_04_pose_candidate_r003_walk_cycle.json','base':'runtime_overlay_act_e_r01_04_pose_candidate_r002.json','source':'ActorStills/ACT_E_R01_04/ACT_E_R01_04__still__E_R01_04_base_v2.png','canvas':[512,512],'anchor':[256,490],'align':'floor','semantic':'slow_heavy_six_leg_tripod_ground_gait','fps':12},
 {'id':'ACT_B_R01_A','name':'root_guardian_stroll','atlas':Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-17860fca-f586-4d04-9fab-57593fe65473.png'),'rev':'walk_cycle_r001','overlay':'runtime_overlay_act_b_r01_a_pose_candidate_r004_walk_cycle.json','base':'runtime_overlay_act_b_r01_a_pose_candidate_r003.json','source':'ActorStills/ACT_B_R01_A/ACT_B_R01_A__still__B_R01_A_base_v2.png','canvas':[512,512],'anchor':[256,490],'align':'floor','semantic':'heavy_quadruped_root_guardian_stroll','fps':12},
]
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1<<20),b''):h.update(b)
 return h.hexdigest()
def splits(n,parts):return [round(i*n/parts) for i in range(parts+1)]
manifest_all={'schema':'r01_enemy_motion_candidates_r001','approval':'UNAPPROVED_CANDIDATES','items':[]}
for item in ITEMS:
 aid=item['id']; out=ART/'GeneratedCandidates'/aid/item['rev']; fd=out/'frames';fd.mkdir(parents=True,exist_ok=True)
 src=ART/item['source']; before=sha(src); atlas=Image.open(item['atlas']).convert('RGBA')
 if atlas.size==(1377,1142): x=splits(atlas.width,3); y=[0,381,761,1142]
 elif atlas.size==(1536,1024): x=[0,512,1024,1536]; y=[0,341,683,1024]
 else:raise ValueError((aid,atlas.size))
 shutil.copy2(item['atlas'],out/'imagegen_atlas.png');shutil.copy2(src,out/'identity_reference_still.png')
 records=[]; paths=[]; rgbaFrames=[]
 for n in range(9):
  row,col=divmod(n,3); box=(x[col],y[row],x[col+1],y[row+1]); cell=atlas.crop(box)
  ar=np.array(cell.getchannel('A')); labels,num=ndimage.label(ar>16,structure=np.ones((3,3),dtype=np.uint8))
  counts=np.bincount(labels.ravel()); counts[0]=0; main_label=int(counts.argmax()); main=(labels==main_label)
  # Remove only disconnected generated atlas debris; keep two-pixel antialias fringe around the principal silhouette.
  keep=ndimage.binary_dilation(main,iterations=2); removed=int(((ar>0)&~keep).sum())
  clean=cell.copy(); aa=np.array(clean.getchannel('A')); aa[~keep]=0; clean.putalpha(Image.fromarray(aa.astype('uint8')))
  cell=clean; ar=np.array(cell.getchannel('A')); yy,xx=np.where(ar>16)
  if len(xx)==0:raise ValueError(f'{aid} empty pose {n}')
  cw,ch=item['canvas']; dx=round(cw/2-(xx.min()+xx.max())/2)
  if item['align']=='floor':dy=item['anchor'][1]-int(yy.max())
  else:dy=round(ch/2-(yy.min()+yy.max())/2)
  packed=Image.new('RGBA',(cw,ch),(0,0,0,0));packed.alpha_composite(cell,(dx,dy))
  a2=np.asarray(packed.getchannel('A')); py,px=np.where(a2>16)
  bound=[int(px.min()),int(py.min()),int(px.max()),int(py.max())]
  if bound[0]<0 or bound[1]<0 or bound[2]>=cw or bound[3]>=ch:raise ValueError(f'{aid} crop overflow {n}: {bound}')
  name=f'walk_{n:03}.png';dest=fd/name;packed.save(dest);rgbaFrames.append(packed)
  rel=f'GeneratedCandidates/{aid}/{item["rev"]}/frames/{name}';paths.append(rel)
  records.append({'frame':name,'source_cell_px':[box[0],box[1],box[2]-box[0],box[3]-box[1]],'translation_px':[dx,dy],'packed_alpha16_bounds':bound,'alpha16_pixels':int((a2>16).sum()),'removed_disconnected_alpha_pixels':removed,'source_alpha16_component_count':int(num),'sha256':sha(dest)})
 # Composite QA on neutral dark gray to catch low-alpha edge colors and transparent leftovers.
 qa=Image.new('RGB',(3*512,3*544),(27,34,43));draw=ImageDraw.Draw(qa)
 for n,im in enumerate(rgbaFrames):
  r,c=divmod(n,3);scaled=im.resize((512,512),Image.Resampling.NEAREST)
  bg=Image.new('RGBA',(512,512),(27,34,43,255));bg.alpha_composite(scaled)
  qa.paste(bg.convert('RGB'),(c*512,r*544+32));draw.text((c*512+8,r*544+8),f'{aid} / {n:03}',fill=(235,235,235))
 qa_path=out/'qa_contact_sheet.jpg';qa.save(qa_path,quality=94)
 base=json.loads((ART/item['base']).read_text())['entries'][aid]
 entry=json.loads(json.dumps(base));entry.setdefault('sequenceFrames',{});entry['sequenceFrames']['walk']=paths
 entry.setdefault('clips',{})['walk']={'frames':paths,'frame_count':9,'fps':item['fps'],'duration_seconds':9/item['fps'],'loop':True,'status':'UNAPPROVED_NINE_FRAME_MOTION_CANDIDATE_NOT_NATURAL_MOTION_COMPLETE','canvas_px':item['canvas'],'anchor':item['anchor'],'anchor_status':'VISUAL_ESTIMATE_UNAPPROVED','movement_semantics':item['semantic']}
 entry['canvas_px']=item['canvas'];entry['anchor']=item['anchor'];entry['anchor_status']='VISUAL_ESTIMATE_UNAPPROVED';entry['states_present']=sorted(set(entry.get('states_present',[])+['walk']));entry['status']='UNAPPROVED_PARTIAL_MOTION_CANDIDATE';entry['complete_animation']=False
 ov={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY','complete_animation':False,'candidate_manifest':f'GeneratedCandidates/{aid}/{item["rev"]}/manifest.json','entries':{aid:entry}}
 (ART/item['overlay']).write_text(json.dumps(ov,ensure_ascii=False,indent=2)+'\n')
 rec={'asset_id':aid,'revision':item['rev'],'movement_semantics':item['semantic'],'source_still_path':item['source'],'source_still_sha256':before,'atlas_path':f'GeneratedCandidates/{aid}/{item["rev"]}/imagegen_atlas.png','atlas_sha256':sha(out/'imagegen_atlas.png'),'atlas_px':list(atlas.size),'grid_crop_x':x,'grid_crop_y':y,'frame_canvas_px':item['canvas'],'anchor_candidate_px':item['anchor'],'registration':'center x to canvas midpoint; lower alpha16 bound to candidate anchor for grounded motion; alpha-bbox center for hover; translation only, no rescale or recolor. Disconnected generated cell debris with alpha>0 outside the 2px fringe of largest alpha>16 component is zeroed; core RGBA retained.','fps_candidate':item['fps'],'frames':records,'qa_contact_sheet':f'GeneratedCandidates/{aid}/{item["rev"]}/qa_contact_sheet.jpg','runtime_overlay':item['overlay'],'visual_status':'CANDIDATE_PENDING_ROOT_SCREEN_REVIEW','approval_status':'HUMAN_ADOPTION_PENDING','natural_motion_complete':False}
 if item.get('rejected_prior'):rec['rejected_prior']=item['rejected_prior']
 (out/'manifest.json').write_text(json.dumps(rec,ensure_ascii=False,indent=2)+'\n')
 if sha(src)!=before:raise RuntimeError('source changed '+aid)
 manifest_all['items'].append(rec)
manifest_all['status']='UNAPPROVED_PARTIAL_MOTION_CANDIDATES_PENDING_NATIVE_SCREEN_REVIEW';manifest_all['natural_motion_complete']=False
(ROOT/'docs/production/current/art/R01_enemy_walk_cycle_candidates_r001.json').write_text(json.dumps(manifest_all,ensure_ascii=False,indent=2)+'\n')
print(json.dumps([{'id':x['asset_id'],'rev':x['revision'],'qa':x['qa_contact_sheet'],'overlay':x['runtime_overlay'],'alpha16_bounds':[f['packed_alpha16_bounds'] for f in x['frames']]} for x in manifest_all['items']],ensure_ascii=False,indent=2))
