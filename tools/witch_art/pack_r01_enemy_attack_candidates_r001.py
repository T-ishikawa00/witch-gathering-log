#!/usr/bin/env python3
"""Alpha-preserving packer for the R01 E03/E04 nine-cell attack candidates."""
import hashlib, json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'native/Art'
CONFIGS=[
 {'actor':'ACT_E_R01_03','source_still':'ActorStills/ACT_E_R01_03/ACT_E_R01_03__still__E_R01_03_base_v1.png','atlas':'GeneratedCandidates/ACT_E_R01_03/attack_cycle_r001/imagegen_atlas_corrected.png','base_overlay':'runtime_overlay_act_e_r01_03_pose_candidate_r003_flight_cycle.json','revision':'attack_cycle_packed_r001','canvas':[512,512],'anchor':[256,300],'semantics':'airborne leaf-wing slash: brief wing draw-back, alternating blade-wing sweep, wings re-open for recovery'},
 {'actor':'ACT_E_R01_04','source_still':'ActorStills/ACT_E_R01_04/ACT_E_R01_04__still__E_R01_04_base_v2.png','atlas':'GeneratedCandidates/ACT_E_R01_04/attack_cycle_r001/imagegen_atlas_corrected.png','base_overlay':'runtime_overlay_act_e_r01_04_pose_candidate_r003_walk_cycle.json','revision':'attack_cycle_packed_r001','canvas':[512,640],'anchor':[256,490],'semantics':'grounded resin beetle shell-first lunge: shell lowers and braces, forelegs thrust, claws plant and shell rebounds'},
]
STATES=('anticipate','execute','recover')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def alpha_bbox(im,threshold=16):return im.getchannel('A').point(lambda v:255 if v>threshold else 0).getbbox()
for cfg in CONFIGS:
 actor=cfg['actor']; atlas_path=ART/cfg['atlas']; atlas=Image.open(atlas_path).convert('RGBA');w,h=atlas.size
 if w%3:raise SystemExit(f'{actor}: atlas width not divisible by 3 {atlas.size}')
 xedges=[round(i*w/3) for i in range(4)];yedges=[round(i*h/3) for i in range(4)]
 source=json.loads((ART/cfg['base_overlay']).read_text())['entries'][actor]
 walk=source['clips']['walk'];base_canvas=walk.get('canvas_px',source.get('canvas_px'));base_anchor=walk.get('anchor',source.get('anchor'))
 if not base_canvas or not base_anchor:raise SystemExit(f'{actor}: missing source walk canvas/anchor')
 outdir=ART/'GeneratedCandidates'/actor/cfg['revision'];framesdir=outdir/'frames';framesdir.mkdir(parents=True,exist_ok=True)
 # Keep a byte-identical copy of the selected imagegen atlas in its packed revision.
 packed_atlas=outdir/'imagegen_atlas_source.png';packed_atlas.write_bytes(atlas_path.read_bytes())
 cw_names=[f'{s}_{i:03d}.png' for s in STATES for i in range(3)];records=[];packed=[];heights=[]
 W,H=cfg['canvas'];ax,ay=cfg['anchor']
 for idx,name in enumerate(cw_names):
  row,col=divmod(idx,3);cell=atlas.crop((xedges[col],yedges[row],xedges[col+1],yedges[row+1]));cw,ch=cell.size
  bbox=alpha_bbox(cell);arr=np.asarray(cell);mask=arr[:,:,3]>16;yy,xx=np.where(mask)
  if not len(xx):raise SystemExit(f'{actor}: empty cell {idx}')
  margins=[int(xx.min()),int(yy.min()),cw-1-int(xx.max()),ch-1-int(yy.max())]
  edge=int(mask[[0,-1],:].sum()+mask[:,[0,-1]].sum())
  if edge or min(margins)<18:raise SystemExit(f'{actor}: alpha16 cell edge/margin fail {idx} {margins} edges={edge}')
  full=cell.getchannel('A').getbbox();l,t,r,b=full
  if W==512 and cw==512:dx=0
  else:dx=round(W/2-(l+r)/2)
  if ay>=450:dy=ay-int(yy.max())
  else:
   # Aerial motion is registered around the base actor's visual center, not a floor contact.
   dy=round(H/2-(int(yy.min())+int(yy.max()))/2)
  if dx<0 or dy<0 or dx+cw>W or dy+ch>H:raise SystemExit(f'{actor}: source cell would clip in output {idx}: size={(cw,ch)} offset={(dx,dy)} canvas={(W,H)}')
  frame=Image.new('RGBA',(W,H),(0,0,0,0));frame.paste(cell,(dx,dy))
  if frame.crop((dx,dy,dx+cw,dy+ch)).tobytes()!=cell.tobytes():raise SystemExit(f'{actor}: source RGBA mismatch {idx}')
  out=framesdir/name;frame.save(out,optimize=True);pb=alpha_bbox(frame);heights.append(pb[3]-pb[1]);packed.append((name,frame))
  records.append({'frame':name,'phase':STATES[row],'sourceCellBoundsPx':[xedges[col],yedges[row],xedges[col+1],yedges[row+1]],'sourceCellPx':[cw,ch],'sourceAlpha16BBox':[int(xx.min()),int(yy.min()),int(xx.max())+1,int(yy.max())+1],'sourceAlpha16MarginsLTRB':margins,'sourceAlpha16EdgePixels':edge,'packingOffsetPx':[dx,dy],'packedAlpha16BBox':list(pb),'allSourceCellRGBABytesPreserved':True,'sha256':sha(out)})
 # Fit new action art against the current candidate walk clip's visible alpha16 height after its scale.
 walk_heights=[]
 for rel in walk['frames']:
  q=Image.open(ART/rel).convert('RGBA');bb=alpha_bbox(q)
  if bb:walk_heights.append(bb[3]-bb[1])
 if not walk_heights:raise SystemExit(f'{actor}: cannot measure source walk')
 import statistics
 current_scale=float(walk.get('display_scale',1.0) or 1.0)
 target_height=statistics.median(walk_heights)*current_scale
 display_scale=round(target_height/statistics.median(heights),6)
 clips={};sequence={}
 for state in STATES:
  paths=[f'GeneratedCandidates/{actor}/{cfg["revision"]}/frames/{state}_{i:03d}.png' for i in range(3)]
  clips[state]={'frames':paths,'frame_count':3,'fps':10,'duration_seconds':0.3,'loop':False,'complete_animation':False,'status':'UNAPPROVED_THREE_FRAME_ATTACK_PHASE_CANDIDATE_NOT_NATURAL_MOTION_COMPLETE','canvas_px':cfg['canvas'],'anchor':cfg['anchor'],'display_scale':display_scale,'anchor_status':'INHERITED_VISUAL_ESTIMATE_UNAPPROVED','movement_semantics':cfg['semantics']}
  sequence[state]=paths
 overlay_path=ART/f'runtime_overlay_{actor.lower()}_attack_cycle_candidate_r001.json'
 overlay={'status':'UNAPPROVED_PARTIAL_ATTACK_MOTION_CANDIDATE_OVERLAY','complete_animation':False,'candidate_manifest':f'GeneratedCandidates/{actor}/{cfg["revision"]}/manifest.json','entries':{actor:{'clips':clips,'sequenceFrames':sequence}}}
 overlay_path.write_text(json.dumps(overlay,ensure_ascii=False,indent=2)+'\n')
 panel=Image.new('RGB',(3*(W+12)+12,3*(H+28)+12),(30,36,34));draw=ImageDraw.Draw(panel)
 for i,(name,frame) in enumerate(packed):
  x=12+(i%3)*(W+12);y=12+(i//3)*(H+28);bg=Image.new('RGBA',frame.size,(30,36,34,255));bg.alpha_composite(frame);panel.paste(bg.convert('RGB'),(x,y));draw.text((x+5,y+H+4),f'{STATES[i//3]} {i%3}',fill=(230,235,230))
 panel.save(outdir/'qa_contact_dark.jpg',quality=95)
 still=ART/cfg['source_still'];manifest={'schema':'witch.enemy_attack_cycle_candidate.v1','actorId':actor,'revision':cfg['revision'],'status':'UNAPPROVED_PARTIAL_ATTACK_MOTION_CANDIDATE','sourceApprovedStill':cfg['source_still'],'sourceApprovedStillSHA256':sha(still),'sourceAtlas':cfg['atlas'],'sourceAtlasSHA256':sha(atlas_path),'atlasPx':[w,h],'gridXEdgesPx':xedges,'gridYEdgesPx':yedges,'phaseOrder':['anticipate_000..002','execute_000..002','recover_000..002'],'runtimeCanvasPx':cfg['canvas'],'candidateAnchorPx':cfg['anchor'],'candidateDisplayScale':display_scale,'candidateWalkAlpha16HeightsPx':walk_heights,'targetDisplayAlpha16HeightPx':target_height,'newAttackAlpha16HeightsPx':heights,'movementSemantics':cfg['semantics'],'packing':'Exact source cell RGBA copied into runtime transparent canvas; no resize, recolor, alpha cleanup or drawing.','frameRecords':records,'qaContactDark':'qa_contact_dark.jpg','runtimeOverlay':overlay_path.name,'visualQA':'Candidate reviewed after dark compositing; native SpriteKit screen review pending.','completeNaturalMotion':False,'humanApproval':False,'limitations':['3 frames per phase only; timing/transition quality needs native game review.','Do not treat as approved or naturally complete.']}
 (outdir/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 print(actor,'scale',display_scale,'walkTargetAlpha16',round(target_height,1),'attackHeights',heights,'overlay',overlay_path)
