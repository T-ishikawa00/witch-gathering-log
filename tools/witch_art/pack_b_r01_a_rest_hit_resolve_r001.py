#!/usr/bin/env python3
"""Pack the B_R01_A additive idle/hit/resolve imagegen atlas candidate."""
from pathlib import Path
from PIL import Image, ImageDraw
import hashlib, json, os, statistics, shutil

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'native/Art'
ACTOR='ACT_B_R01_A'
REV='rest_hit_resolve_r001'
ATLAS_SOURCE=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-85a48dfd-8f8b-4481-874c-8f3e527fdfbe.png')
OUT=ART/'GeneratedCandidates'/ACTOR/REV
STATES=('idle','hit','resolve')
STATUS='UNAPPROVED_AUTHORED_REST_HIT_RESOLVE_CANDIDATE'

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def atomic_bytes(p,data):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);tmp=p.with_name(p.name+'.tmp');tmp.write_bytes(data);os.replace(tmp,p)
def atomic_json(p,obj): atomic_bytes(p,(json.dumps(obj,ensure_ascii=False,indent=2)+'\n').encode())
def alpha16(im): return im.getchannel('A').point(lambda a:255 if a>=16 else 0)
def find_gutter(mask,axis,near):
 limit=mask.width if axis=='x' else mask.height; groups=[];current=[]
 for v in range(max(1,round(near-90)),min(limit-1,round(near+90))):
  sl=(v,0,v+1,mask.height) if axis=='x' else (0,v,mask.width,v+1)
  if mask.crop(sl).getbbox() is None: current.append(v)
  elif current: groups.append(current);current=[]
 if current: groups.append(current)
 if not groups: raise ValueError(('transparent gutter missing',axis,near))
 return round(statistics.mean(min(groups,key=lambda g:abs(statistics.mean(g)-near)-min(20,len(g))*.25)))
def main():
 if not ATLAS_SOURCE.is_file(): raise FileNotFoundError(ATLAS_SOURCE)
 if OUT.exists(): raise SystemExit(f'refusing to overwrite {OUT}')
 ref=ART/'ActorStills/ACT_B_R01_A/ACT_B_R01_A__still__B_R01_A_base_v2.png'
 baselines=[ART/'GeneratedCandidates/ACT_B_R01_A/pose_candidate_r003/frames'/f'idle_{x}.png' for x in ('a','b')]
 for p in [ref,*baselines]:
  if not p.is_file(): raise FileNotFoundError(p)
 (OUT/'frames').mkdir(parents=True)
 atlas_path=OUT/'imagegen_atlas_r001.png';shutil.copy2(ATLAS_SOURCE,atlas_path)
 atlas=Image.open(atlas_path).convert('RGBA');mask=alpha16(atlas)
 if mask.getbbox() is None or atlas.getchannel('A').getextrema()[0]!=0: raise ValueError('atlas must retain real transparent background')
 y=[0,find_gutter(mask,'y',atlas.height/3),find_gutter(mask,'y',2*atlas.height/3),atlas.height]
 cells=[];x_by_row=[]
 for row in range(3):
  band=mask.crop((0,y[row],atlas.width,y[row+1]));x=[0,find_gutter(band,'x',atlas.width/3),find_gutter(band,'x',2*atlas.width/3),atlas.width];x_by_row.append(x)
  for col in range(3):
   box=(x[col],y[row],x[col+1],y[row+1]);cell=atlas.crop(box);b=alpha16(cell).getbbox()
   if not b: raise ValueError(('empty frame',row,col))
   margin=min(b[0],b[1],cell.width-b[2],cell.height-b[3])
   if margin<2: raise ValueError(('art reaches measured cell edge',row,col,box,b,margin))
   cells.append((cell,box,b,margin))
 base=[]
 for p in baselines:
  im=Image.open(p).convert('RGBA');b=alpha16(im).getbbox()
  if not b: raise ValueError(('empty baseline',p))
  base.append({'path':str(p.relative_to(ROOT)),'bbox_alpha16':list(b),'height_px':b[3]-b[1],'width_px':b[2]-b[0]})
 target_h=statistics.median(v['height_px'] for v in base)
 generated_idle_h=statistics.median(b[3]-b[1] for _,_,b,_ in cells[:3])
 desired=target_h/generated_idle_h
 fit=min(desired,470/max(b[2]-b[0] for _,_,b,_ in cells),460/max(b[3]-b[1] for _,_,b,_ in cells))
 anchor=[256,490]
 frames=[];contact=Image.new('RGBA',(1536,1536),(31,36,41,255));draw=ImageDraw.Draw(contact)
 labels=[]
 for s in STATES:
  labels += [f'{s}_{i:03}' for i in range(3)]
 for n,(cell,box,b,margin) in enumerate(cells):
  # One shared fit preserves body scale across all poses. No alpha repainting or per-frame resizing.
  size=(round(cell.width*fit),round(cell.height*fit))
  scaled=cell.resize(size,Image.Resampling.LANCZOS);sb=alpha16(scaled).getbbox()
  dx=round(256-(sb[0]+sb[2])/2);dy=round(anchor[1]-sb[3])
  frame=Image.new('RGBA',(512,512),(0,0,0,0));frame.alpha_composite(scaled,(dx,dy));fb=alpha16(frame).getbbox()
  if min(fb[0],fb[1],512-fb[2],512-fb[3])<2: raise ValueError(('packed frame clipping',labels[n],fb))
  rel=f'GeneratedCandidates/{ACTOR}/{REV}/frames/{labels[n]}.png';p=ART/rel
  tmp=p.with_name(p.name+'.tmp.png');frame.save(tmp,format='PNG',optimize=True);os.replace(tmp,p)
  contact.alpha_composite(frame,((n%3)*512,(n//3)*512));draw.text(((n%3)*512+10,(n//3)*512+8),labels[n],fill='white',stroke_width=2,stroke_fill=(0,0,0,255))
  frames.append({'state':STATES[n//3],'index':n%3,'path':rel,'sha256':sha(p),'source_cell_xyxy':list(box),'source_alpha16_bbox':list(b),'source_alpha16_margin_px':margin,'packed_alpha16_bbox':list(fb),'translation_px':[dx,dy]})
 contact_path=OUT/'qa_contact_dark.jpg';tmp=contact_path.with_name(contact_path.name+'.tmp.jpg');contact.convert('RGB').save(tmp,format='JPEG',quality=94);os.replace(tmp,contact_path)
 entry={'kind':'enemy_actor_kit','selectedPNG':frames[0]['path'],'canvas_px':[512,512],'anchor':anchor,'anchor_status':'VISUAL_ESTIMATE_UNAPPROVED','anchor_type':'foot_registration_candidate','states_present':list(STATES),'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE','clips':{},'sequenceFrames':{}}
 fps={'idle':4,'hit':12,'resolve':8}
 semantics={'idle':'Large root boar guardian: subtle breath while keeping the established low quadruped stance.','hit':'Non-gory hit reaction: shoulders and head brace/recoil; hooves remain planted.','resolve':'Non-gory resolve: lowers into a quiet settled quadruped stance; no collapse or injury depiction.'}
 for i,s in enumerate(STATES):
  paths=[f['path'] for f in frames[i*3:(i+1)*3]];entry['sequenceFrames'][s]=paths
  entry['clips'][s]={'frames':paths,'frame_count':3,'fps':fps[s],'duration_seconds':round(3/fps[s],6),'loop':s=='idle','canvas_px':[512,512],'anchor':anchor,'display_scale':1.0,'status':STATUS,'complete_animation':False,'movement_semantics':semantics[s],'anchor_status':'VISUAL_ESTIMATE_UNAPPROVED'}
 overlay={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY','complete_animation':False,'human_approval':False,'source_art_untouched':True,'entries':{ACTOR:entry}}
 overlay_path=ART/'runtime_overlay_zzzzzz_act_b_r01_a_rest_hit_resolve_r001.json';atomic_json(overlay_path,overlay)
 manifest={'schema':'witch.enemy_rest_hit_resolve_candidate.v1','actorId':ACTOR,'revision':REV,'status':STATUS,'referenceStill':str(ref.relative_to(ROOT)),'referenceStillSHA256':sha(ref),'atlasOriginalPath':str(ATLAS_SOURCE),'atlasPackedPath':str(atlas_path.relative_to(ROOT)),'atlasSHA256':sha(atlas_path),'atlasPx':list(atlas.size),'gridYEdgesPx':y,'gridXEdgesByRowPx':x_by_row,'baselineIdleFrames':base,'targetIdleAlpha16HeightPx':target_h,'generatedIdleAlpha16MedianHeightPx':generated_idle_h,'uniformFitScale':fit,'candidateCanvasPx':[512,512],'candidateAnchorPx':anchor,'sharedDisplayScaleAcrossStates':1.0,'frames':frames,'contactSheet':str(contact_path.relative_to(ROOT)),'overlay':str(overlay_path.relative_to(ROOT)),'overlaySHA256':sha(overlay_path),'packingMethod':'Measured fully transparent alpha>=16 gutters; preserve full RGBA cell art; one common Lanczos downscale factor; position on transparent 512x512 canvases at common foot baseline. No alpha cleanup, recoloring, or source edits. Atomic PNG and JSON publish.','nativeRuntimeReview':'PENDING_ROOT_REVIEW','humanAdoption':'PENDING','naturalMotionComplete':False,'limitations':['Generated poses retain source identity broadly but remain subject to close review for redraw drift and motion quality.','3 sampled frames per state do not establish natural continuous animation.','The overlay updates idle/hit/resolve only and leaves walk and attack state clips inherited.']}
 atomic_json(OUT/'manifest.json',manifest)
 report={'schema':'witch.enemy_rest_hit_resolve_candidate_report.v1','status':'CANDIDATE_EVIDENCE_ONLY_PENDING_ROOT_VISUAL_REVIEW','actorId':ACTOR,'previousEffectiveCounts':{'idle':2,'hit':2,'resolve':2,'walk':9,'anticipate':2,'execute':2,'recover':3},'newCounts':{'idle':3,'hit':3,'resolve':3},'candidateManifest':str((OUT/'manifest.json').relative_to(ROOT)),'contactSheet':str(contact_path.relative_to(ROOT)),'overlay':str(overlay_path.relative_to(ROOT)),'overlaySHA256':sha(overlay_path),'baselineIdle':base,'alphaGutter':{'y':y,'xByRow':x_by_row,'minimumMarginPx':min(f['source_alpha16_margin_px'] for f in frames)},'nativeReview':'PENDING','humanAdoption':'PENDING','naturalMotionComplete':False}
 atomic_json(ROOT/'docs/production/current/art/ACT_B_R01_A_rest_hit_resolve_candidate_r001.json',report)
 print(json.dumps({'overlay':str(overlay_path.relative_to(ROOT)),'sha256':report['overlaySHA256'],'manifest':str((OUT/'manifest.json').relative_to(ROOT)),'contact':str(contact_path.relative_to(ROOT)),'fit':fit,'targetIdleHeightPx':target_h,'generatedIdleHeightPx':generated_idle_h,'gutterY':y,'xByRow':x_by_row},ensure_ascii=False))
if __name__=='__main__': main()
