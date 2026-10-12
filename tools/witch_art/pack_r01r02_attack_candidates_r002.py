import hashlib,json,os,statistics
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2]; ART=ROOT/'native/Art'
CONFIGS=[
 {'actor':'ACT_B_R01_B','atlas':'GeneratedCandidates/ACT_B_R01_B/attack_cycle_r001/imagegen_atlas_corrected.png','base':'runtime_overlay_act_b_r01_b_pose_candidate_r003_rooted_sway_cycle.json','still':'ActorStills/ACT_B_R01_B/ACT_B_R01_B__still__B_R01_B_ANCIENT_TREE_base_v1.png','canvas':[512,600],'anchor':[256,490],'fps':8,'semantics':'Rooted ancient tree boss raises/cocks branches, sweeps limbs forward, then settles canopy; rooted branch attack, not locomotion.','scale_mode':'walk'},
 {'actor':'ACT_E_R02_01','atlas':'GeneratedCandidates/ACT_E_R02_01/attack_cycle_r001/imagegen_atlas_corrected.png','base':'runtime_overlay_act_e_r02_01_walk_cycle_candidate_r003.json','still':'ActorStills/ACT_E_R02_01/ACT_E_R02_01__still__r002.png','canvas':[512,600],'anchor':[256,460],'fps':10,'semantics':'Mud jelly compresses low into a strike, extends/slides forward, then rebounds to its upright body; squash-and-lunge, not legged walk.','scale_mode':'walk'},
 {'actor':'ACT_E_R02_02','atlas':'GeneratedCandidates/ACT_E_R02_02/attack_cycle_r001/imagegen_atlas_corrected_r002.png','base':'runtime_overlay_act_e_r02_02_pose_candidate_r001.json','still':'ActorStills/ACT_E_R02_02/ACT_E_R02_02__still__r001.png','canvas':[512,544],'anchor':[256,442],'fps':10,'semantics':'Blue scale-drake draws its head back, lunges to bite while tail counterswings, then retracts and settles; four-footed bite attack.','scale_mode':'walk'},
]
STATES=['anticipate','execute','recover']
def atomic_bytes(path,data):
 path=Path(path);path.parent.mkdir(parents=True,exist_ok=True);tmp=path.with_name(path.name+'.tmp');tmp.write_bytes(data);os.replace(tmp,path)
def atomic_json(path,obj):atomic_bytes(path,(json.dumps(obj,ensure_ascii=False,indent=2)+'\n').encode())
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def alpha_bbox(im,th=16):return im.getchannel('A').point(lambda x:255 if x>th else 0).getbbox()
results={}
for cfg in CONFIGS:
 actor=cfg['actor'];ap=ART/cfg['atlas']; atlas=Image.open(ap).convert('RGBA');w,h=atlas.size
 if w%3:raise RuntimeError(f'{actor}: noninteger 3-column grid {atlas.size}')
 xedges=[round(i*w/3) for i in range(4)]; yedges=[round(i*h/3) for i in range(4)]
 source=json.loads((ART/cfg['base']).read_text())['entries'][actor]
 walk=source.get('clips',{}).get('walk',{})
 walkframes=walk.get('frames') or source.get('sequenceFrames',{}).get('walk',[])
 walkheights=[]
 for rel in walkframes:
  q=Image.open(ART/rel).convert('RGBA');bb=alpha_bbox(q)
  if bb:walkheights.append(bb[3]-bb[1])
 if not walkheights:raise RuntimeError(f'{actor}: no measurable walk')
 scale=float(walk.get('display_scale',1.0) or 1.0)
 target=statistics.median(walkheights)*scale
 W,H=cfg['canvas'];ax,ay=cfg['anchor'];outdir=ART/'GeneratedCandidates'/actor/'attack_cycle_packed_r002';framesdir=outdir/'frames';framesdir.mkdir(parents=True,exist_ok=True)
 frame_records=[];frame_images=[];heights=[]
 names=[]
 for si,state in enumerate(STATES):
  for i in range(3):
   idx=si*3+i;row,col=divmod(idx,3);x0,x1=xedges[col],xedges[col+1];y0,y1=yedges[row],yedges[row+1];cw,ch=x1-x0,y1-y0;cell=atlas.crop((x0,y0,x1,y1));arr=np.asarray(cell);mask=arr[:,:,3]>16;yy,xx=np.where(mask)
   if not len(xx):raise RuntimeError(f'{actor}: empty cell {idx}')
   margins=[int(xx.min()),int(yy.min()),cw-1-int(xx.max()),ch-1-int(yy.max())];edge=int(mask[[0,-1],:].sum()+mask[:,[0,-1]].sum())
   if edge or min(margins)<12:raise RuntimeError(f'{actor}: edge alpha / margin failure cell={idx}, margins={margins}, edge={edge}')
   if ax>=W or ay>=H:raise RuntimeError('anchor outside canvas')
   # Keep exact source RGBA, floor-registered when a floor anchor is declared.
   dx=round((W-cw)/2)
   if ay>H*.72:dy=ay-int(yy.max())
   else:dy=round((H-ch)/2)
   if dx<0 or dy<0 or dx+cw>W or dy+ch>H:raise RuntimeError(f'{actor}: cell would clip: offset={(dx,dy)} cell={(cw,ch)} canvas={(W,H)}')
   frame=Image.new('RGBA',(W,H),(0,0,0,0));frame.paste(cell,(dx,dy))
   if frame.crop((dx,dy,dx+cw,dy+ch)).tobytes()!=cell.tobytes():raise RuntimeError(f'{actor}: RGBA mismatch {idx}')
   name=f'{state}_{i:03}.png';names.append(name);p=framesdir/name
   tmp=p.with_name(p.name+'.tmp');frame.save(tmp,format='PNG',optimize=True);os.replace(tmp,p)
   bb=alpha_bbox(frame);heights.append(bb[3]-bb[1]);frame_images.append((name,frame))
   frame_records.append({'frame':name,'state':state,'atlasCell':[col,row],'sourceCellBoundsPx':[x0,y0,x1,y1],'sourceAlpha16BBox':[int(xx.min()),int(yy.min()),int(xx.max())+1,int(yy.max())+1],'sourceAlpha16MarginsLTRB':margins,'sourceAlpha16EdgePixels':edge,'canvasPx':[W,H],'packingOffsetPx':[dx,dy],'packedAlpha16BBox':list(bb),'sourceCellRgbaPreserved':True,'sha256':sha(p)})
 display=round(target/statistics.median(heights),6)
 clips={};sequences={}
 for si,state in enumerate(STATES):
  paths=[f'GeneratedCandidates/{actor}/attack_cycle_packed_r002/frames/{state}_{i:03}.png' for i in range(3)]
  clips[state]={'frames':paths,'frame_count':3,'fps':cfg['fps'],'duration_seconds':round(3/cfg['fps'],6),'loop':False,'complete_animation':False,'status':'UNAPPROVED_THREE_FRAME_ATTACK_PHASE_CANDIDATE_NOT_NATURAL_MOTION_COMPLETE','canvas_px':cfg['canvas'],'anchor':cfg['anchor'],'display_scale':display,'anchor_status':'CANDIDATE_VISUAL_ESTIMATE_UNAPPROVED','movement_semantics':cfg['semantics']}
  sequences[state]=paths
 overlay={'status':'UNAPPROVED_PARTIAL_ATTACK_MOTION_CANDIDATE_OVERLAY','complete_animation':False,'candidate_manifest':f'GeneratedCandidates/{actor}/attack_cycle_packed_r002/manifest.json','entries':{actor:{'clips':clips,'sequenceFrames':sequences}}}
 overlaypath=ART/f'runtime_overlay_{actor.lower()}_attack_cycle_candidate_r002.json';atomic_json(overlaypath,overlay)
 # Contact sheet on uniform dark matte; no source alpha changes.
 panel=Image.new('RGB',(3*(W+10)+10,3*(H+26)+10),(30,36,34));draw=ImageDraw.Draw(panel)
 for i,(name,frame) in enumerate(frame_images):
  x=10+(i%3)*(W+10);y=10+(i//3)*(H+26);bg=Image.new('RGBA',(W,H),(30,36,34,255));bg.alpha_composite(frame);panel.paste(bg.convert('RGB'),(x,y));draw.text((x+4,y+H+3),f'{STATES[i//3]} {i%3}',fill=(235,235,230))
 qap=outdir/'qa_contact_dark.jpg';tmp=qap.with_name(qap.name+'.tmp');panel.save(tmp,format='JPEG',quality=94);os.replace(tmp,qap)
 manifest={'schema':'witch.enemy_attack_cycle_candidate.v1','actorId':actor,'revision':'attack_cycle_packed_r002','status':'UNAPPROVED_PARTIAL_ATTACK_MOTION_CANDIDATE','sourceApprovedStill':cfg['still'],'sourceApprovedStillSHA256':sha(ART/cfg['still']),'imagegenAtlas':cfg['atlas'],'imagegenAtlasSHA256':sha(ap),'atlasPx':[w,h],'gridXEdgesPx':xedges,'gridYEdgesPx':yedges,'grid':'3x3 row-major: anticipate, execute, recover','runtimeCanvasPx':cfg['canvas'],'candidateAnchorPx':cfg['anchor'],'candidateDisplayScale':display,'baseWalkAlpha16HeightsPx':walkheights,'baseWalkDisplayScale':scale,'targetVisibleAlpha16HeightPx':target,'attackVisibleAlpha16HeightsPx':heights,'movementSemantics':cfg['semantics'],'packing':'Cell RGBA bytes copied unchanged onto transparent registered canvas; no resizing/recolor/alpha edits. PNGs atomically published.','frameRecords':frame_records,'qaContactDark':'qa_contact_dark.jpg','runtimeOverlay':overlaypath.name,'visualQA':'Dark-composited contact reviewed for identity, margins, severed parts and phase readability. Native SpriteKit audit pending.','naturalMotionComplete':False,'humanApproved':False,'limitations':['Only 3 frames per phase; transition quality and timing require native review.','Tree branch attack differences are subtle; do not treat as complete motion.']}
 atomic_json(outdir/'manifest.json',manifest)
 results[actor]={'overlay':overlaypath.name,'manifest':str(outdir/'manifest.json'),'contact':str(qap),'display_scale':display,'heights':heights,'walk_heights':walkheights,'cell':[w//3,h//3],'atlas':[w,h]}
 print(json.dumps(results[actor]))
# Late partial-state master overlay: retain the prior three actors, then add this batch.
prior_path=ART/'runtime_overlay_zz_r01r02_attack_cycles_r001.json'
prior=json.loads(prior_path.read_text())
entries=prior['entries']
new_actors=[cfg['actor'] for cfg in CONFIGS]
for actor in new_actors:
 entries[actor]=json.loads((ART/f'runtime_overlay_{actor.lower()}_attack_cycle_candidate_r002.json').read_text())['entries'][actor]
master={'schemaVersion':1,'status':'UNAPPROVED_PARTIAL_ATTACK_MOTION_CANDIDATES_PENDING_NATIVE_REVIEW','completeAnimation':False,'humanApproval':False,'assemblyRule':'Late-sorting partial-state overlay. Only anticipate/execute/recover are changed; existing idle/walk/hit/resolve are preserved.','entries':entries}
master_path=ART/'runtime_overlay_zz_r01r02_attack_cycles_r002.json';atomic_json(master_path,master)
# Evidence report covers the inherited three and this added batch.
report={'schemaVersion':1,'status':'UNAPPROVED_ATTACK_PHASE_CANDIDATES_PENDING_NATIVE_REVIEW','overlay':str(master_path.relative_to(ROOT)),'overlaySHA256':sha(master_path),'assemblyRule':master['assemblyRule'],'actors':{},'qualityNotes':{'ACT_B_R01_B':'Rooted tree attack phases are visually subtle; keep partial pending in-game review.','ACT_E_R02_01':'Squash/lunge/rebound is readable; several source cells have only 14px alpha16 bottom clearance but no alpha touches a cell edge.','ACT_E_R02_02':'Bite windup/execute/recovery retains drake identity; corrected atlas r002 cleared the observed row-edge contact.','otherThree':'Prior spider, leaf-blade, resin-beetle candidates retained from r001; native review remains pending.'},'limitations':['Three frames per phase only; no natural-motion completion claim.','Human approval is false.','Full SpriteKit gameplay review is pending.']}
for actor,e in entries.items():
 clips=e['clips']; report['actors'][actor]={'framesByState':{s:clips[s]['frames'] for s in STATES},'displayScaleByState':{s:clips[s].get('display_scale',1.0) for s in STATES},'canvasByState':{s:clips[s]['canvas_px'] for s in STATES},'anchorByState':{s:clips[s]['anchor'] for s in STATES},'status':'UNAPPROVED_PARTIAL_ATTACK_CANDIDATE'}
 if actor in new_actors:
  d=json.loads((ART/'GeneratedCandidates'/actor/'attack_cycle_packed_r002'/'manifest.json').read_text())
  report['actors'][actor].update({'manifest':f'native/Art/GeneratedCandidates/{actor}/attack_cycle_packed_r002/manifest.json','qaContactDark':f'native/Art/GeneratedCandidates/{actor}/attack_cycle_packed_r002/qa_contact_dark.jpg','atlasSHA256':d['imagegenAtlasSHA256'],'displayScale':d['candidateDisplayScale'],'alpha16Heights':d['attackVisibleAlpha16HeightsPx'],'framesAllCellRGBABytesPreserved':all(r['sourceCellRgbaPreserved'] for r in d['frameRecords'])})
atomic_json(ROOT/'docs/production/current/art/R01R02_attack_motion_candidates_r002.json',report)
print('master overlay',master_path,'sha256',sha(master_path),'actors',len(entries))
